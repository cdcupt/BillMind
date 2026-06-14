import Vapor
import Fluent

/// The read-only tools the agent drives. Every figure the agent states is the
/// output of one of these deterministic DB computations — never the model's
/// prose — and every query is scoped to the requesting user (tenant isolation).
enum AgentTools {
    /// Trip IDs the user owns — the tenant scope for every read.
    static func ownedTripIDs(_ db: Database, userID: UUID, tripID: UUID? = nil) async throws -> [UUID] {
        var query = Trip.query(on: db).filter(\.$owner.$id == userID)
        if let tripID { query = query.filter(\.$id == tripID) }
        return try await query.all().map { try $0.requireID() }
    }

    /// Bills within the user's owned trip(s).
    static func bills(_ db: Database, userID: UUID, tripID: UUID? = nil) async throws -> [Bill] {
        let tripIDs = try await ownedTripIDs(db, userID: userID, tripID: tripID)
        guard !tripIDs.isEmpty else { return [] }
        return try await Bill.query(on: db).filter(\.$trip.$id ~~ tripIDs).all()
    }

    struct Totals {
        let total: Decimal
        let count: Int
        let byCategory: [(category: String, amount: Decimal)]
    }

    /// `compute_totals` — total + per-category breakdown, exact Decimal sums.
    static func computeTotals(_ db: Database, userID: UUID, tripID: UUID? = nil) async throws -> Totals {
        let all = try await bills(db, userID: userID, tripID: tripID)
        let total = all.reduce(Decimal(0)) { $0 + $1.amount }
        var byCategory: [String: Decimal] = [:]
        for bill in all {
            byCategory[bill.categoryRaw ?? "misc", default: 0] += bill.amount
        }
        let sorted = byCategory.sorted { $0.value > $1.value }
            .map { (category: $0.key, amount: $0.value) }
        return Totals(total: total, count: all.count, byCategory: sorted)
    }

    /// `query_bills` — filtered list (category / merchant substring), tenant-scoped.
    static func queryBills(_ db: Database, userID: UUID, tripID: UUID? = nil,
                           category: String? = nil, merchant: String? = nil) async throws -> [Bill] {
        var result = try await bills(db, userID: userID, tripID: tripID)
        if let category { result = result.filter { $0.categoryRaw == category } }
        if let merchant {
            let needle = merchant.lowercased()
            result = result.filter { ($0.merchant ?? "").lowercased().contains(needle) }
        }
        return result
    }
}
