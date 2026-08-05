import Vapor
import Fluent
import BillMindCore

/// `/v1/trips` — create / list / list-bills. All behind auth + tenant-scoped.
struct TripController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let trips = routes.grouped("v1", "trips").grouped(UserAuthMiddleware())
        trips.post(use: create)
        trips.get(use: list)
        trips.get(":tripID", "bills", use: bills)
        trips.patch(":tripID", use: update)
        trips.delete(":tripID", use: delete)
    }

    /// A trip name ceiling consistent with BillController's merchant cap: blocks
    /// absurd input while clearing any realistic trip title.
    private static let maxTripNameLength = 200

    /// PATCH /v1/trips/:tripID — rename a trip. Bumps `row_version` so the rename
    /// wins last-write-wins on every other device via sync. Scoped to the owner;
    /// another user's id returns 404, never their data. An empty/whitespace-only
    /// name is rejected (a rename never blanks the title).
    func update(_ req: Request) async throws -> TripDTO {
        let user = try req.auth.require(User.self)
        let uid = try user.requireID()
        guard let tripID = req.parameters.get("tripID", as: UUID.self) else { throw Abort(.badRequest) }
        guard let trip = try await Trip.query(on: req.db)
            .filter(\.$id == tripID).filter(\.$owner.$id == uid).first()
        else { throw Abort(.notFound) }

        let body = try req.content.decode(UpdateTripRequest.self)
        let name = body.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw Abort(.unprocessableEntity, reason: "trip name must not be empty")
        }
        guard name.count <= Self.maxTripNameLength else {
            throw Abort(.unprocessableEntity, reason: "trip name is too long")
        }

        if let rawCurrency = body.currencyCode {
            let currency = rawCurrency.uppercased()
            guard currency.count == 3, currency.allSatisfy({ $0.isLetter && $0.isASCII }) else {
                throw Abort(.unprocessableEntity, reason: "currencyCode must be a 3-letter ISO 4217 code")
            }
            trip.currencyCode = currency
        }
        trip.name = name
        trip.rowVersion += 1
        try await trip.save(on: req.db)
        return try TripDTO(trip)
    }

    /// DELETE /v1/trips/:tripID — soft-delete the trip AND all its bills (tombstones),
    /// bumping each row_version so every device drops them on the next sync. Scoped
    /// to the owner; another user's id returns 404, never their data.
    func delete(_ req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        let uid = try user.requireID()
        guard let tripID = req.parameters.get("tripID", as: UUID.self) else { throw Abort(.badRequest) }
        guard let trip = try await Trip.query(on: req.db)
            .filter(\.$id == tripID).filter(\.$owner.$id == uid).first()
        else { throw Abort(.notFound) }

        try await req.db.transaction { db in
            let bills = try await Bill.query(on: db).filter(\.$trip.$id == tripID).all()
            for bill in bills {
                bill.rowVersion += 1
                try await bill.save(on: db)        // persist the bump before tombstoning
                try await bill.delete(on: db)      // soft-delete (tombstone)
            }
            trip.rowVersion += 1
            try await trip.save(on: db)
            try await trip.delete(on: db)
        }
        return .noContent
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
    /// A generous single-bill ceiling: blocks absurd/overflow values (e.g. `1e400`)
    /// while clearing any realistic travel expense in any currency.
    private static let maxBillAmount: Decimal = 1_000_000_000_000
    private static let maxMerchantLength = 200
    private static let maxNotesLength = 2000

    func boot(routes: RoutesBuilder) throws {
        let bills = routes.grouped("v1", "bills").grouped(UserAuthMiddleware())
        bills.post(use: create)
        bills.post("confirm", use: confirm)
        bills.patch(":billID", use: update)
        bills.delete(":billID", use: delete)
    }

    /// Tenant-scoped fetch: the bill must belong to a trip the caller owns. A bill
    /// id that isn't theirs (or doesn't exist) returns 404 — never another user's
    /// data, and never a 403 that confirms the id exists.
    private func ownedBill(_ req: Request, uid: User.IDValue) async throws -> Bill {
        guard let billID = req.parameters.get("billID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "invalid bill id")
        }
        guard let bill = try await Bill.query(on: req.db).filter(\.$id == billID).first(),
              let _ = try await Trip.query(on: req.db)
                  .filter(\.$id == bill.$trip.id).filter(\.$owner.$id == uid).first()
        else { throw Abort(.notFound) }
        return bill
    }

    /// PATCH /v1/bills/:billID — edit a saved bill. Bumps `row_version` so the
    /// change wins last-write-wins on every other device via sync. Amount must stay
    /// positive; an unknown category is rejected.
    func update(_ req: Request) async throws -> BillDTO {
        let user = try req.auth.require(User.self)
        let bill = try await ownedBill(req, uid: try user.requireID())
        let body = try req.content.decode(UpdateBillRequest.self)

        guard body.amount > 0, body.amount <= Self.maxBillAmount else {
            throw Abort(.unprocessableEntity, reason: "amount must be positive and within range")
        }
        guard BillCategory(rawValue: body.categoryRaw) != nil else {
            throw Abort(.unprocessableEntity, reason: "unknown category")
        }
        let currency = body.currencyCode.uppercased()
        guard currency.count == 3, currency.allSatisfy(\.isLetter) else {
            throw Abort(.unprocessableEntity, reason: "currencyCode must be a 3-letter ISO 4217 code")
        }
        let merchant = body.merchant?.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = body.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (merchant?.count ?? 0) <= Self.maxMerchantLength else {
            throw Abort(.unprocessableEntity, reason: "merchant is too long")
        }
        guard (notes?.count ?? 0) <= Self.maxNotesLength else {
            throw Abort(.unprocessableEntity, reason: "notes are too long")
        }

        bill.merchant = (merchant?.isEmpty == false) ? merchant : nil
        bill.amount = body.amount
        bill.currencyCode = currency
        bill.date = body.date
        bill.categoryRaw = body.categoryRaw
        bill.notes = (notes?.isEmpty == false) ? notes : nil
        bill.rowVersion += 1
        try await bill.save(on: req.db)
        return try BillDTO(bill)
    }

    /// DELETE /v1/bills/:billID — soft-delete (tombstone). The bumped `row_version`
    /// is persisted by the soft-delete write so the tombstone wins LWW on sync.
    func delete(_ req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        let bill = try await ownedBill(req, uid: try user.requireID())
        // Atomic: bump the version (soft-delete alone won't persist it) then tombstone,
        // so a crash can't leave a version-bumped-but-not-deleted row.
        try await req.db.transaction { db in
            bill.rowVersion += 1
            try await bill.save(on: db)
            try await bill.delete(on: db)
        }
        return .noContent
    }

    /// Confirm a resolved draft → write a Bill. This is the ONLY write path, and
    /// it runs the shared BillValidator: a missing amount is rejected (the agent
    /// never guesses money). Soft gaps (date/category) carry safe defaults.
    func confirm(_ req: Request) async throws -> BillDTO {
        let user = try req.auth.require(User.self)
        let uid = try user.requireID()
        let body = try req.content.decode(ConfirmRequest.self)
        guard let trip = try await Trip.query(on: req.db)
            .filter(\.$id == body.tripID).filter(\.$owner.$id == uid).first()
        else { throw Abort(.notFound, reason: "trip not found") }

        let draft = BillDraft(
            merchant: body.merchant, amount: body.amount,
            currencyCode: body.currencyCode ?? trip.currencyCode,
            date: body.date, categoryRaw: body.categoryRaw,
            source: DraftSource(rawValue: body.source ?? "text") ?? .text
        )
        let validator = BillValidator(
            knownCategoryRaws: Set(BillCategory.allCases.map(\.rawValue)),
            journalCurrencyCode: trip.currencyCode, today: Date()
        )
        guard !validator.unresolvedFields(for: draft).contains(.amount) else {
            throw Abort(.unprocessableEntity, reason: "amount is required — the agent never guesses it")
        }
        let bill = Bill(tripID: try trip.requireID(), merchant: draft.merchant,
                        amount: draft.amount!, currencyCode: draft.currencyCode,
                        date: draft.date ?? Date(), categoryRaw: draft.categoryRaw,
                        source: draft.source.rawValue, createdByID: uid)
        try await bill.save(on: req.db)
        return try BillDTO(bill)
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
