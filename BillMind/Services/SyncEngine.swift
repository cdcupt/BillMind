import Foundation
import SwiftData

/// One full reconcile's tallies (for logging / pull-to-refresh feedback).
struct SyncOutcome: Sendable {
    let createdTrips: Int
    let pushedBills: Int
    let conflicts: Int
    let pulledTrips: Int
    let pulledBills: Int
}

/// Reconciles the local SwiftData cache with the server via `/v1/sync`.
///
/// Order is **push then pull**: local bill edits go up first, then the server's
/// authoritative state comes down. The server is the source of truth and the
/// cache is disposable, so the pull simply applies server state to matching
/// `serverID`s — which implements last-write-wins (a push conflict means the
/// server is newer, and the following pull overwrites the local row) and
/// honours tombstones (a `deleted` row is removed locally).
///
/// An `actor` (not `@ModelActor`) so it can also hold the `SyncAPI`; each method
/// makes its own `ModelContext` from the shared container for background work.
actor SyncEngine {
    private let container: ModelContainer
    private let api: SyncAPI

    init(container: ModelContainer, api: SyncAPI) {
        self.container = container
        self.api = api
    }

    @discardableResult
    func sync() async throws -> SyncOutcome {
        let context = ModelContext(container)
        let createdTrips = try await pushPendingTrips(context)   // trips must exist before their bills
        let pushed = try await pushPendingBills(context)
        let pulled = try await pullDeltas(context)
        return SyncOutcome(createdTrips: createdTrips,
                           pushedBills: pushed.applied, conflicts: pushed.conflicts,
                           pulledTrips: pulled.trips, pulledBills: pulled.bills)
    }

    // MARK: - Push trips (created via /v1/trips; the sync contract pushes bills only)

    private func pushPendingTrips(_ context: ModelContext) async throws -> Int {
        // Locally-created trips have no serverID yet. Create them on the server so
        // their bills become pushable. (Trip edits/deletes are out of scope for v1.)
        let pending = try context.fetch(FetchDescriptor<Journal>(
            predicate: #Predicate { $0.serverID == nil && $0.isDeleted == false }))
        var created = 0
        for journal in pending {
            let trip = try await api.createTrip(APICreateTripRequest(
                name: journal.name, currencyCode: journal.currency, mascot: journal.coverAnimalRaw))
            journal.serverID = trip.id
            journal.rowVersion = trip.rowVersion
            journal.syncState = .synced
            created += 1
        }
        if created > 0 { try context.save() }
        return created
    }

    // MARK: - Push (bills only; trips are created via /v1/trips)

    private func pushPendingBills(_ context: ModelContext) async throws -> (applied: Int, conflicts: Int) {
        let localRaw = SyncState.local.rawValue
        let dirty = try context.fetch(FetchDescriptor<BillRecord>(
            predicate: #Predicate { $0.syncStateRaw == localRaw || $0.isDeleted }))

        // A bill can only be pushed once its trip exists on the server.
        let upserts: [APIBillUpsert] = dirty.compactMap { bill in
            guard let tripServerID = bill.journal?.serverID else { return nil }
            return APIBillUpsert(
                id: bill.serverID ?? bill.id,
                tripID: tripServerID,
                merchant: bill.merchant,
                amount: bill.amount,
                currencyCode: bill.originalCurrency,
                date: bill.date,
                categoryRaw: bill.categoryRaw,
                source: nil,
                notes: bill.note,
                rowVersion: bill.rowVersion,
                deleted: bill.isDeleted ? true : nil)
        }
        guard !upserts.isEmpty else { return (0, 0) }

        let result = try await api.syncPush(APISyncPush(bills: upserts))
        let conflicts = Set(result.conflicts)
        for bill in dirty {
            let pushedID = bill.serverID ?? bill.id
            guard !conflicts.contains(pushedID) else { continue }   // overwritten by the pull below
            bill.serverID = pushedID
            bill.syncState = .synced                                // rowVersion corrected by the pull
        }
        try context.save()
        return (result.appliedBills, result.conflicts.count)
    }

    // MARK: - Pull (server authoritative)

    private func pullDeltas(_ context: ModelContext) async throws -> (trips: Int, bills: Int) {
        let delta = try await api.syncPull(since: SyncCursor.value)
        for trip in delta.trips { try applyTrip(trip, context) }
        for bill in delta.bills { try applyBill(bill, context) }
        try context.save()
        SyncCursor.value = delta.cursor
        return (delta.trips.count, delta.bills.count)
    }

    private func applyTrip(_ t: APITripSync, _ context: ModelContext) throws {
        let sid = t.id
        let existing = try context.fetch(FetchDescriptor<Journal>(
            predicate: #Predicate { $0.serverID == sid })).first
        if t.deleted {
            if let existing { context.delete(existing) }
            return
        }
        let journal = existing ?? Journal(name: t.name, currency: t.currencyCode)
        journal.name = t.name
        journal.currency = t.currencyCode
        if let mascot = t.mascot { journal.coverAnimalRaw = mascot }
        journal.serverID = sid
        journal.rowVersion = t.rowVersion
        journal.updatedAt = t.updatedAt
        journal.syncState = .synced
        if existing == nil { context.insert(journal) }
    }

    private func applyBill(_ b: APIBillSync, _ context: ModelContext) throws {
        let sid = b.id
        let existing = try context.fetch(FetchDescriptor<BillRecord>(
            predicate: #Predicate { $0.serverID == sid })).first
        if b.deleted {
            if let existing { context.delete(existing) }
            return
        }
        let bill = existing ?? BillRecord()
        bill.merchant = b.merchant
        bill.amount = b.amount
        bill.originalCurrency = b.currencyCode
        bill.date = b.date
        bill.categoryRaw = b.categoryRaw ?? BillCategory.misc.rawValue
        bill.note = b.notes
        bill.serverID = sid
        bill.rowVersion = b.rowVersion
        bill.updatedAt = b.updatedAt
        bill.syncState = .synced

        let tripSID = b.tripID
        if bill.journal?.serverID != tripSID {
            bill.journal = try context.fetch(FetchDescriptor<Journal>(
                predicate: #Predicate { $0.serverID == tripSID })).first
        }
        if existing == nil { context.insert(bill) }
    }
}
