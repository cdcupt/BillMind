import Vapor
import Fluent

/// `/v1/trips` — create / list / list-bills. All behind auth + tenant-scoped.
struct TripController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let trips = routes.grouped("v1", "trips").grouped(UserAuthMiddleware())
        trips.post(use: create)
        trips.get(use: list)
        trips.get(":tripID", "bills", use: bills)
    }

    func create(_ req: Request) async throws -> TripDTO {
        let user = try req.auth.require(User.self)
        let body = try req.content.decode(CreateTripRequest.self)
        let trip = Trip(ownerID: try user.requireID(), name: body.name,
                        currencyCode: body.currencyCode, mascot: body.mascot)
        try await trip.save(on: req.db)
        return try TripDTO(trip)
    }

    func list(_ req: Request) async throws -> [TripDTO] {
        let user = try req.auth.require(User.self)
        let trips = try await Trip.query(on: req.db)
            .filter(\.$owner.$id == (try user.requireID())).all()
        return try trips.map { try TripDTO($0) }
    }

    func bills(_ req: Request) async throws -> [BillDTO] {
        let user = try req.auth.require(User.self)
        guard let tripID = req.parameters.get("tripID", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        // Ownership guard: another user's trip id returns 404, never their data.
        guard let trip = try await Trip.query(on: req.db)
            .filter(\.$id == tripID).filter(\.$owner.$id == (try user.requireID())).first()
        else { throw Abort(.notFound) }
        let bills = try await Bill.query(on: req.db)
            .filter(\.$trip.$id == (try trip.requireID())).all()
        return try bills.map { try BillDTO($0) }
    }
}

/// `/v1/bills` — manual create (the agent capture-confirm path lands here too in 6b).
struct BillController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let bills = routes.grouped("v1", "bills").grouped(UserAuthMiddleware())
        bills.post(use: create)
    }

    func create(_ req: Request) async throws -> BillDTO {
        let user = try req.auth.require(User.self)
        let body = try req.content.decode(CreateBillRequest.self)
        guard let trip = try await Trip.query(on: req.db)
            .filter(\.$id == body.tripID).filter(\.$owner.$id == (try user.requireID())).first()
        else { throw Abort(.notFound, reason: "trip not found") }
        let bill = Bill(tripID: try trip.requireID(), merchant: body.merchant,
                        amount: body.amount, currencyCode: body.currencyCode ?? trip.currencyCode,
                        date: body.date, categoryRaw: body.categoryRaw,
                        source: body.source ?? "manual", notes: body.notes,
                        createdByID: try user.requireID())
        try await bill.save(on: req.db)
        return try BillDTO(bill)
    }
}

/// `/v1/stats?tripId=&scope=trip|all` — the same computation the agent embeds.
struct StatsController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let stats = routes.grouped("v1", "stats").grouped(UserAuthMiddleware())
        stats.get(use: stats(_:))
    }

    func stats(_ req: Request) async throws -> StatsDTO {
        let user = try req.auth.require(User.self)
        let uid = try user.requireID()
        let tripID = try? req.query.get(UUID.self, at: "tripId")
        let scope = (try? req.query.get(String.self, at: "scope")) ?? (tripID != nil ? "trip" : "all")
        let totals = try await AgentTools.computeTotals(req.db, userID: uid,
                                                        tripID: scope == "all" ? nil : tripID)
        return StatsDTO(
            scope: scope, total: totals.total, billCount: totals.count,
            byCategory: totals.byCategory.map { CategoryTotalDTO(category: $0.category, amount: $0.amount) }
        )
    }
}
