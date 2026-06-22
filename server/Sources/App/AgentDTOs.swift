import Vapor

// MARK: - Trips

struct CreateTripRequest: Content {
    let name: String
    let currencyCode: String
    let mascot: String?
}

/// Rename payload for `PATCH /v1/trips/:tripID`. Only the trip name is editable
/// through this route; the server trims + validates it (non-empty, length cap)
/// and bumps `row_version` so the rename wins last-write-wins on every device.
struct UpdateTripRequest: Content {
    let name: String
}

struct TripDTO: Content {
    let id: UUID
    let name: String
    let currencyCode: String
    @DecimalString var exchangeRate: Decimal
    let mascot: String?
    let rowVersion: Int

    init(_ t: Trip) throws {
        self.id = try t.requireID()
        self.name = t.name
        self.currencyCode = t.currencyCode
        self.exchangeRate = t.exchangeRate
        self.mascot = t.mascot
        self.rowVersion = t.rowVersion
    }
}

// MARK: - Bills

struct CreateBillRequest: Content {
    let tripID: UUID
    let merchant: String?
    @DecimalString var amount: Decimal
    let currencyCode: String?
    let date: Date
    let categoryRaw: String?
    let source: String?
    let notes: String?
}

/// Full edit payload for `PATCH /v1/bills/:billID`. The client sends the complete
/// editable state (no absent-vs-null ambiguity): amount/currency/date/category are
/// always present; merchant/notes are nullable. Amount stays a decimal string on
/// the wire and must be positive (money is never zeroed by an edit).
struct UpdateBillRequest: Content {
    let merchant: String?
    @DecimalString var amount: Decimal
    let currencyCode: String
    let date: Date
    let categoryRaw: String
    let notes: String?
}

struct BillDTO: Content {
    let id: UUID
    let tripID: UUID
    let merchant: String?
    @DecimalString var amount: Decimal
    let currencyCode: String
    let date: Date
    let categoryRaw: String?
    let source: String
    let notes: String?
    let rowVersion: Int

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
    }
}

// MARK: - Stats (the chart system the agent also drives as a tool)

struct CategoryTotalDTO: Content {
    let category: String
    @DecimalString var amount: Decimal
}

struct StatsDTO: Content {
    let scope: String          // trip | all
    @DecimalString var total: Decimal
    let billCount: Int
    let byCategory: [CategoryTotalDTO]
}
