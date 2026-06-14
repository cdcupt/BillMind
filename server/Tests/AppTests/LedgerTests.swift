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
        try await app.test(.POST, "v1/bills", headers: bearer(t),
            beforeRequest: {
                try $0.content.encode(CreateBillRequest(
                    tripID: trip.id, merchant: merchant, amount: amount, currencyCode: "JPY",
                    date: Date(), categoryRaw: category, source: "manual", notes: nil))
            },
            afterResponse: { res async in XCTAssertEqual(res.status, .ok) })
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
}
