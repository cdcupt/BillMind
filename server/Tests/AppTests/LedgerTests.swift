import XCTVapor
import Fluent
import FluentSQLiteDriver
@testable import App

private struct StubOIDC: OIDCVerifier {
    let identity: VerifiedIdentity
    func verify(idToken: String, provider: OIDCProvider, on req: Request) async throws -> VerifiedIdentity { identity }
}

final class LedgerTests: XCTestCase {
    /// Builds an app whose stub OIDC returns the given subject, so each test can
    /// sign in as a chosen user.
    private func makeApp(subject: String) async throws -> Application {
        let app = try await Application.make(.testing)
        app.databases.use(.sqlite(.memory), as: .sqlite)
        app.migrations.add(CreateInitialSchema())
        try await app.autoMigrate()
        app.jwt.signers.use(.hs256(key: Array("test-signing-key-0123456789abcdef".utf8)))
        let id = VerifiedIdentity(provider: .google, subject: subject, email: "\(subject)@example.com",
                                  isPrivateRelay: false, name: subject)
        try app.register(collection: AuthController(oidc: StubOIDC(identity: id)))
        try app.register(collection: TripController())
        try app.register(collection: BillController())
        try app.register(collection: StatsController())
        try app.register(collection: SyncController())
        return app
    }

    private func signIn(_ app: Application) async throws -> AuthTokensDTO {
        var tokens: AuthTokensDTO!
        try await app.test(.POST, "v1/auth/google",
            beforeRequest: { try $0.content.encode(["idToken": "stub"]) },
            afterResponse: { res async throws in tokens = try res.content.decode(AuthTokensDTO.self) })
        return tokens
    }

    private func bearer(_ t: AuthTokensDTO) -> HTTPHeaders { ["Authorization": "Bearer \(t.accessToken)"] }

    private func createTrip(_ app: Application, _ t: AuthTokensDTO, name: String = "Osaka") async throws -> TripDTO {
        var trip: TripDTO!
        try await app.test(.POST, "v1/trips", headers: bearer(t),
            beforeRequest: { try $0.content.encode(CreateTripRequest(name: name, currencyCode: "JPY", mascot: nil)) },
            afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                trip = try res.content.decode(TripDTO.self)
            })
        return trip
    }

    private func addBill(_ app: Application, _ t: AuthTokensDTO, trip: TripDTO,
                         merchant: String, amount: Decimal, category: String) async throws {
        _ = try await addBillReturning(app, t, trip: trip, merchant: merchant, amount: amount, category: category)
    }

    @discardableResult
    private func addBillReturning(_ app: Application, _ t: AuthTokensDTO, trip: TripDTO,
                                  merchant: String, amount: Decimal, category: String) async throws -> BillDTO {
        var bill: BillDTO!
        try await app.test(.POST, "v1/bills", headers: bearer(t),
            beforeRequest: {
                try $0.content.encode(CreateBillRequest(
                    tripID: trip.id, merchant: merchant, amount: amount, currencyCode: "JPY",
                    date: Date(), categoryRaw: category, source: "manual", notes: nil))
            },
            afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                bill = try res.content.decode(BillDTO.self)
            })
        return bill
    }

    /// Registers user B (a second OIDC subject) and returns their tokens.
    private func signInSecondUser(_ app: Application) async throws -> AuthTokensDTO {
        let idB = VerifiedIdentity(provider: .apple, subject: "u2", email: nil, isPrivateRelay: true, name: nil)
        try app.register(collection: AuthController(oidc: StubOIDC(identity: idB)))
        var b: AuthTokensDTO!
        try await app.test(.POST, "v1/auth/apple",
            beforeRequest: { try $0.content.encode(["idToken": "stub"]) },
            afterResponse: { res async throws in b = try res.content.decode(AuthTokensDTO.self) })
        return b
    }

    func testCreateTripAddBillsAndStats() async throws {
        let app = try await makeApp(subject: "u1")
        let tokens = try await signIn(app)
        let trip = try await createTrip(app, tokens)
        try await addBill(app, tokens, trip: trip, merchant: "Ichiran", amount: 2840, category: "food")
        try await addBill(app, tokens, trip: trip, merchant: "Lawson", amount: 680, category: "food")
        try await addBill(app, tokens, trip: trip, merchant: "MK Taxi", amount: 3200, category: "transport")

        try await app.test(.GET, "v1/stats?scope=all", headers: bearer(tokens),
            afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let stats = try res.content.decode(StatsDTO.self)
                XCTAssertEqual(stats.total, Decimal(6720))
                XCTAssertEqual(stats.billCount, 3)
                // food (3520) sorts above transport (3200)
                XCTAssertEqual(stats.byCategory.first?.category, "food")
                XCTAssertEqual(stats.byCategory.first?.amount, Decimal(3520))
            })
        try await app.asyncShutdown()
    }

    /// Tenant isolation: a second user cannot read the first user's trip bills,
    /// and their stats never include the first user's money.
    func testCrossTenantIsolation() async throws {
        let app = try await makeApp(subject: "u1")
        let a = try await signIn(app)            // user A
        let tripA = try await createTrip(app, a, name: "A-Osaka")
        try await addBill(app, a, trip: tripA, merchant: "Ichiran", amount: 2840, category: "food")

        // user B (different OIDC subject) — re-register auth with B's identity.
        let idB = VerifiedIdentity(provider: .apple, subject: "u2", email: "u2@example.com",
                                   isPrivateRelay: false, name: "u2")
        try app.register(collection: AuthController(oidc: StubOIDC(identity: idB)))
        var b: AuthTokensDTO!
        try await app.test(.POST, "v1/auth/apple",
            beforeRequest: { try $0.content.encode(["idToken": "stub"]) },
            afterResponse: { res async throws in b = try res.content.decode(AuthTokensDTO.self) })
        XCTAssertNotEqual(a.userID, b.userID)

        // B asks for A's trip bills → 404 (filter excludes it).
        try await app.test(.GET, "v1/trips/\(tripA.id)/bills", headers: bearer(b),
            afterResponse: { res async in XCTAssertEqual(res.status, .notFound) })

        // B's stats are empty — A's ¥2840 is invisible.
        try await app.test(.GET, "v1/stats?scope=all", headers: bearer(b),
            afterResponse: { res async throws in
                let stats = try res.content.decode(StatsDTO.self)
                XCTAssertEqual(stats.total, Decimal(0))
                XCTAssertEqual(stats.billCount, 0)
            })
        try await app.asyncShutdown()
    }

    func testCannotCreateBillInAnothersTrip() async throws {
        let app = try await makeApp(subject: "u1")
        let a = try await signIn(app)
        let tripA = try await createTrip(app, a)

        let idB = VerifiedIdentity(provider: .apple, subject: "u2", email: nil, isPrivateRelay: true, name: nil)
        try app.register(collection: AuthController(oidc: StubOIDC(identity: idB)))
        var b: AuthTokensDTO!
        try await app.test(.POST, "v1/auth/apple",
            beforeRequest: { try $0.content.encode(["idToken": "stub"]) },
            afterResponse: { res async throws in b = try res.content.decode(AuthTokensDTO.self) })

        // B tries to write a bill into A's trip → 404.
        try await app.test(.POST, "v1/bills", headers: bearer(b),
            beforeRequest: {
                try $0.content.encode(CreateBillRequest(
                    tripID: tripA.id, merchant: "x", amount: 100, currencyCode: "JPY",
                    date: Date(), categoryRaw: "misc", source: "manual", notes: nil))
            },
            afterResponse: { res async in XCTAssertEqual(res.status, .notFound) })
        try await app.asyncShutdown()
    }

    // MARK: - Edit / delete

    func testUpdateBillEditsFieldsAndBumpsRowVersion() async throws {
        let app = try await makeApp(subject: "u1")
        let t = try await signIn(app)
        let trip = try await createTrip(app, t)
        let bill = try await addBillReturning(app, t, trip: trip, merchant: "Lawson", amount: 680, category: "food")
        XCTAssertEqual(bill.rowVersion, 1)

        var updated: BillDTO!
        try await app.test(.PATCH, "v1/bills/\(bill.id)", headers: bearer(t),
            beforeRequest: {
                try $0.content.encode(UpdateBillRequest(
                    merchant: "FamilyMart", amount: 720, currencyCode: "JPY",
                    date: Date(), categoryRaw: "shopping", notes: "late-night snack"))
            },
            afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                updated = try res.content.decode(BillDTO.self)
            })
        XCTAssertEqual(updated.merchant, "FamilyMart")
        XCTAssertEqual(updated.amount, Decimal(720))
        XCTAssertEqual(updated.categoryRaw, "shopping")
        XCTAssertEqual(updated.notes, "late-night snack")
        XCTAssertEqual(updated.rowVersion, 2, "an edit must bump row_version so it wins LWW on sync")
        try await app.asyncShutdown()
    }

    func testRenameTripUpdatesNameAndBumpsRowVersion() async throws {
        let app = try await makeApp(subject: "u1")
        let t = try await signIn(app)
        let trip = try await createTrip(app, t, name: "Osaka")
        let before = trip.rowVersion

        try await app.test(.PATCH, "v1/trips/\(trip.id)", headers: bearer(t),
            beforeRequest: { try $0.content.encode(UpdateTripRequest(name: "New Name", currencyCode: nil)) },
            afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let renamed = try res.content.decode(TripDTO.self)
                XCTAssertEqual(renamed.name, "New Name")
                XCTAssertGreaterThan(renamed.rowVersion, before, "a rename must bump row_version so it wins LWW on sync")
            })
        try await app.asyncShutdown()
    }

    func testUpdateTripCurrencyPersistsAndBumpsRowVersion() async throws {
        let app = try await makeApp(subject: "u1")
        let t = try await signIn(app)
        let trip = try await createTrip(app, t, name: "England")
        let before = trip.rowVersion

        // A pre-departure currency switch (clients offer it only at 0 bills) must
        // land server-side — recognition validates against the trip currency.
        try await app.test(.PATCH, "v1/trips/\(trip.id)", headers: bearer(t),
            beforeRequest: { try $0.content.encode(UpdateTripRequest(name: "England", currencyCode: "gbp")) },
            afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let updated = try res.content.decode(TripDTO.self)
                XCTAssertEqual(updated.currencyCode, "GBP", "currency is normalized to uppercase ISO 4217")
                XCTAssertGreaterThan(updated.rowVersion, before, "a currency change must bump row_version so it wins LWW on sync")
            })
        try await app.asyncShutdown()
    }

    func testUpdateTripRejectsMalformedCurrency() async throws {
        let app = try await makeApp(subject: "u1")
        let t = try await signIn(app)
        let trip = try await createTrip(app, t)

        try await app.test(.PATCH, "v1/trips/\(trip.id)", headers: bearer(t),
            beforeRequest: { try $0.content.encode(UpdateTripRequest(name: "Trip", currencyCode: "££")) },
            afterResponse: { res async in XCTAssertEqual(res.status, .unprocessableEntity) })
        try await app.asyncShutdown()
    }

    func testRenameTripRejectsEmptyName() async throws {
        let app = try await makeApp(subject: "u1")
        let t = try await signIn(app)
        let trip = try await createTrip(app, t)

        try await app.test(.PATCH, "v1/trips/\(trip.id)", headers: bearer(t),
            beforeRequest: { try $0.content.encode(UpdateTripRequest(name: "   ")) },
            afterResponse: { res async in XCTAssertEqual(res.status, .unprocessableEntity) })
        try await app.asyncShutdown()
    }

    /// IDOR guard: user B cannot rename user A's trip (404).
    func testRenameTripForOtherUserIs404() async throws {
        let app = try await makeApp(subject: "u1")
        let a = try await signIn(app)
        let tripA = try await createTrip(app, a)
        let b = try await signInSecondUser(app)

        try await app.test(.PATCH, "v1/trips/\(tripA.id)", headers: bearer(b),
            beforeRequest: { try $0.content.encode(UpdateTripRequest(name: "Hijacked")) },
            afterResponse: { res async in XCTAssertEqual(res.status, .notFound) })

        // A's trip name is untouched.
        try await app.test(.GET, "v1/trips", headers: bearer(a),
            afterResponse: { res async throws in
                let trips = try res.content.decode([TripDTO].self)
                XCTAssertEqual(trips.first { $0.id == tripA.id }?.name, "Osaka")
            })
        try await app.asyncShutdown()
    }

    func testUpdateRejectsZeroAmountAndUnknownCategory() async throws {
        let app = try await makeApp(subject: "u1")
        let t = try await signIn(app)
        let trip = try await createTrip(app, t)
        let bill = try await addBillReturning(app, t, trip: trip, merchant: "Lawson", amount: 680, category: "food")

        try await app.test(.PATCH, "v1/bills/\(bill.id)", headers: bearer(t),
            beforeRequest: {
                try $0.content.encode(UpdateBillRequest(
                    merchant: "x", amount: 0, currencyCode: "JPY", date: Date(), categoryRaw: "food", notes: nil))
            },
            afterResponse: { res async in XCTAssertEqual(res.status, .unprocessableEntity) })

        try await app.test(.PATCH, "v1/bills/\(bill.id)", headers: bearer(t),
            beforeRequest: {
                try $0.content.encode(UpdateBillRequest(
                    merchant: "x", amount: 100, currencyCode: "JPY", date: Date(), categoryRaw: "spaceship", notes: nil))
            },
            afterResponse: { res async in XCTAssertEqual(res.status, .unprocessableEntity) })

        // negative amount → 422 (guard is > 0, not >= 0)
        try await app.test(.PATCH, "v1/bills/\(bill.id)", headers: bearer(t),
            beforeRequest: {
                try $0.content.encode(UpdateBillRequest(
                    merchant: "x", amount: -1, currencyCode: "JPY", date: Date(), categoryRaw: "food", notes: nil))
            },
            afterResponse: { res async in XCTAssertEqual(res.status, .unprocessableEntity) })

        // malformed currency → 422
        try await app.test(.PATCH, "v1/bills/\(bill.id)", headers: bearer(t),
            beforeRequest: {
                try $0.content.encode(UpdateBillRequest(
                    merchant: "x", amount: 100, currencyCode: "JPYEN", date: Date(), categoryRaw: "food", notes: nil))
            },
            afterResponse: { res async in XCTAssertEqual(res.status, .unprocessableEntity) })

        // oversized merchant → 422
        try await app.test(.PATCH, "v1/bills/\(bill.id)", headers: bearer(t),
            beforeRequest: {
                try $0.content.encode(UpdateBillRequest(
                    merchant: String(repeating: "a", count: 5000), amount: 100, currencyCode: "JPY",
                    date: Date(), categoryRaw: "food", notes: nil))
            },
            afterResponse: { res async in XCTAssertEqual(res.status, .unprocessableEntity) })
        try await app.asyncShutdown()
    }

    func testDeleteRemovesBillFromListAndStats() async throws {
        let app = try await makeApp(subject: "u1")
        let t = try await signIn(app)
        let trip = try await createTrip(app, t)
        let bill = try await addBillReturning(app, t, trip: trip, merchant: "Lawson", amount: 680, category: "food")

        try await app.test(.DELETE, "v1/bills/\(bill.id)", headers: bearer(t),
            afterResponse: { res async in XCTAssertEqual(res.status, .noContent) })

        try await app.test(.GET, "v1/trips/\(trip.id)/bills", headers: bearer(t),
            afterResponse: { res async throws in
                XCTAssertTrue(try res.content.decode([BillDTO].self).isEmpty)
            })
        try await app.test(.GET, "v1/stats?scope=all", headers: bearer(t),
            afterResponse: { res async throws in
                XCTAssertEqual(try res.content.decode(StatsDTO.self).billCount, 0)
            })
        try await app.asyncShutdown()
    }

    /// The delete must reach other devices: a sync pull returns the bill as a
    /// tombstone (deleted=true) with the bumped row_version.
    func testDeletePropagatesAsTombstoneInSync() async throws {
        let app = try await makeApp(subject: "u1")
        let t = try await signIn(app)
        let trip = try await createTrip(app, t)
        let bill = try await addBillReturning(app, t, trip: trip, merchant: "Lawson", amount: 680, category: "food")

        try await app.test(.DELETE, "v1/bills/\(bill.id)", headers: bearer(t),
            afterResponse: { res async in XCTAssertEqual(res.status, .noContent) })

        try await app.test(.GET, "v1/sync?since=0", headers: bearer(t),
            afterResponse: { res async throws in
                let delta = try res.content.decode(SyncDelta.self)
                let tomb = delta.bills.first { $0.id == bill.id }
                XCTAssertEqual(tomb?.deleted, true)
                XCTAssertEqual(tomb?.rowVersion, 2)
            })
        try await app.asyncShutdown()
    }

    /// Deleting a trip tombstones the trip AND cascades to its bills, so every
    /// device drops them on the next sync.
    func testDeleteTripTombstonesTripAndItsBills() async throws {
        let app = try await makeApp(subject: "u1")
        let t = try await signIn(app)
        let trip = try await createTrip(app, t)
        let bill = try await addBillReturning(app, t, trip: trip, merchant: "Lawson", amount: 680, category: "food")

        try await app.test(.DELETE, "v1/trips/\(trip.id)", headers: bearer(t),
            afterResponse: { res async in XCTAssertEqual(res.status, .noContent) })

        // Gone from the list…
        try await app.test(.GET, "v1/trips", headers: bearer(t),
            afterResponse: { res async throws in
                let trips = try res.content.decode([TripDTO].self)
                XCTAssertFalse(trips.contains { $0.id == trip.id })
            })

        // …and both the trip and its bill come back as tombstones in the delta.
        try await app.test(.GET, "v1/sync?since=0", headers: bearer(t),
            afterResponse: { res async throws in
                let delta = try res.content.decode(SyncDelta.self)
                XCTAssertEqual(delta.trips.first { $0.id == trip.id }?.deleted, true)
                XCTAssertEqual(delta.bills.first { $0.id == bill.id }?.deleted, true)
            })
        try await app.asyncShutdown()
    }

    /// IDOR guard: user B cannot delete user A's trip (404), and A's trip stays.
    func testCannotDeleteAnothersTrip() async throws {
        let app = try await makeApp(subject: "u1")
        let a = try await signIn(app)
        let tripA = try await createTrip(app, a)
        let b = try await signInSecondUser(app)

        try await app.test(.DELETE, "v1/trips/\(tripA.id)", headers: bearer(b),
            afterResponse: { res async in XCTAssertEqual(res.status, .notFound) })

        try await app.test(.GET, "v1/trips", headers: bearer(a),
            afterResponse: { res async throws in
                let trips = try res.content.decode([TripDTO].self)
                XCTAssertTrue(trips.contains { $0.id == tripA.id })
            })
        try await app.asyncShutdown()
    }

    /// IDOR guard: user B can neither edit nor delete user A's bill (404), and A's
    /// bill stays intact.
    func testCannotEditOrDeleteAnothersBill() async throws {
        let app = try await makeApp(subject: "u1")
        let a = try await signIn(app)
        let tripA = try await createTrip(app, a)
        let billA = try await addBillReturning(app, a, trip: tripA, merchant: "Ichiran", amount: 2840, category: "food")

        let b = try await signInSecondUser(app)

        try await app.test(.PATCH, "v1/bills/\(billA.id)", headers: bearer(b),
            beforeRequest: {
                try $0.content.encode(UpdateBillRequest(
                    merchant: "hax", amount: 1, currencyCode: "JPY", date: Date(), categoryRaw: "misc", notes: nil))
            },
            afterResponse: { res async in XCTAssertEqual(res.status, .notFound) })

        try await app.test(.DELETE, "v1/bills/\(billA.id)", headers: bearer(b),
            afterResponse: { res async in XCTAssertEqual(res.status, .notFound) })

        // A's bill is untouched.
        try await app.test(.GET, "v1/trips/\(tripA.id)/bills", headers: bearer(a),
            afterResponse: { res async throws in
                let bills = try res.content.decode([BillDTO].self)
                XCTAssertEqual(bills.count, 1)
                XCTAssertEqual(bills.first?.merchant, "Ichiran")
                XCTAssertEqual(bills.first?.amount, Decimal(2840))
            })
        try await app.asyncShutdown()
    }
}
