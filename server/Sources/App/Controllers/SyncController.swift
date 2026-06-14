import Vapor
import Fluent

/// `/v1/sync` — delta pull + push. The bill is the conflict unit; conflicts
/// resolve by per-bill last-write-wins on `row_version`. Tombstones (soft-deletes)
/// propagate through the same delta. All tenant-scoped to the user's trips.
struct SyncController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let sync = routes.grouped("v1", "sync").grouped(UserAuthMiddleware())
        sync.get(use: pull)
        sync.post(use: push)
    }

    /// GET /v1/sync?since=<epochSeconds> — everything changed since the cursor,
    /// including tombstones, scoped to the user.
    func pull(_ req: Request) async throws -> SyncDelta {
        let user = try req.auth.require(User.self)
        let uid = try user.requireID()
        let since = (try? req.query.get(Double.self, at: "since")) ?? 0
        let sinceDate = Date(timeIntervalSince1970: since)

        let trips = try await Trip.query(on: req.db).withDeleted()
            .filter(\.$owner.$id == uid).all()
        let tripIDs = try trips.map { try $0.requireID() }
        let bills = tripIDs.isEmpty ? [] : try await Bill.query(on: req.db).withDeleted()
            .filter(\.$trip.$id ~~ tripIDs).all()

        func changed(_ updated: Date?, _ created: Date?) -> Bool {
            (updated ?? created ?? .distantPast) > sinceDate
        }
        let changedTrips = try trips.filter { changed($0.updatedAt, $0.createdAt) }.map { try TripSyncDTO($0) }
        let changedBills = try bills.filter { changed($0.updatedAt, $0.createdAt) }.map { try BillSyncDTO($0) }

        return SyncDelta(trips: changedTrips, bills: changedBills, cursor: Date().timeIntervalSince1970)
    }

    /// POST /v1/sync — push bill upserts; last-write-wins by row_version.
    func push(_ req: Request) async throws -> SyncPushResult {
        let user = try req.auth.require(User.self)
        let uid = try user.requireID()
        let body = try req.content.decode(SyncPush.self)

        var applied = 0
        var conflicts: [UUID] = []

        for upsert in body.bills ?? [] {
            // Tenant guard: the target trip must be the user's.
            guard let trip = try await Trip.query(on: req.db).withDeleted()
                .filter(\.$id == upsert.tripID).filter(\.$owner.$id == uid).first()
            else { conflicts.append(upsert.id); continue }

            let existing = try await Bill.query(on: req.db).withDeleted()
                .filter(\.$id == upsert.id).first()

            if let bill = existing {
                // Only the owner's bill, and only a newer (or equal) row_version wins.
                guard bill.$trip.id == (try trip.requireID()), upsert.rowVersion >= bill.rowVersion else {
                    conflicts.append(upsert.id); continue
                }
                bill.merchant = upsert.merchant
                bill.amount = upsert.amount
                bill.currencyCode = upsert.currencyCode ?? trip.currencyCode
                bill.date = upsert.date
                bill.categoryRaw = upsert.categoryRaw
                bill.source = upsert.source ?? bill.source
                bill.notes = upsert.notes
                bill.rowVersion = upsert.rowVersion
                if upsert.deleted == true {
                    if bill.deletedAt == nil { try await bill.delete(on: req.db) }   // soft-delete (tombstone)
                    else { try await bill.save(on: req.db) }
                } else {
                    bill.deletedAt = nil                                             // un-delete if it comes back
                    try await bill.save(on: req.db)
                }
                applied += 1
            } else {
                if upsert.deleted == true { continue }   // nothing to create for a delete
                let bill = Bill(id: upsert.id, tripID: try trip.requireID(), merchant: upsert.merchant,
                                amount: upsert.amount, currencyCode: upsert.currencyCode ?? trip.currencyCode,
                                date: upsert.date, categoryRaw: upsert.categoryRaw,
                                source: upsert.source ?? "manual", notes: upsert.notes,
                                createdByID: uid, rowVersion: upsert.rowVersion)
                try await bill.create(on: req.db)
                applied += 1
            }
        }
        return SyncPushResult(appliedBills: applied, conflicts: conflicts)
    }
}
