import Vapor

// MARK: - Pull (GET /v1/sync?since=<epochSeconds>)

struct TripSyncDTO: Content {
    let id: UUID
    let name: String
    let currencyCode: String
    let exchangeRate: Decimal
    let mascot: String?
    let rowVersion: Int
    let updatedAt: Date?
    let deleted: Bool

    init(_ t: Trip) throws {
        self.id = try t.requireID()
        self.name = t.name
        self.currencyCode = t.currencyCode
        self.exchangeRate = t.exchangeRate
        self.mascot = t.mascot
        self.rowVersion = t.rowVersion
        self.updatedAt = t.updatedAt
        self.deleted = t.deletedAt != nil
    }
}

struct BillSyncDTO: Content {
    let id: UUID
    let tripID: UUID
    let merchant: String?
    let amount: Decimal
    let currencyCode: String
    let date: Date
    let categoryRaw: String?
    let source: String
    let notes: String?
    let rowVersion: Int
    let updatedAt: Date?
    let deleted: Bool

    init(_ b: Bill) throws {
        self.id = try b.requireID()
        self.tripID = b.$trip.id
        self.merchant = b.merchant
        self.amount = b.amount
        self.currencyCode = b.currencyCode
        self.date = b.date
        self.categoryRaw = b.categoryRaw
        self.source = b.source
        self.notes = b.notes
        self.rowVersion = b.rowVersion
        self.updatedAt = b.updatedAt
        self.deleted = b.deletedAt != nil
    }
}

struct SyncDelta: Content {
    let trips: [TripSyncDTO]
    let bills: [BillSyncDTO]
    let cursor: Double          // epoch seconds; pass back as ?since=
}

// MARK: - Push (POST /v1/sync)

struct BillUpsert: Content {
    let id: UUID
    let tripID: UUID
    let merchant: String?
    let amount: Decimal
    let currencyCode: String?
    let date: Date
    let categoryRaw: String?
    let source: String?
    let notes: String?
    let rowVersion: Int
    let deleted: Bool?
}

struct SyncPush: Content {
    let bills: [BillUpsert]?
}

struct SyncPushResult: Content {
    let appliedBills: Int
    let conflicts: [UUID]       // ids rejected by last-write-wins (stale rowVersion) or not owned
}
