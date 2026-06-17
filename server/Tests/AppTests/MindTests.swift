import XCTVapor
import Fluent
import FluentSQLiteDriver
import BillMindCore
@testable import App

private struct StubOIDCMind: OIDCVerifier {
    let identity: VerifiedIdentity
    func verify(idToken: String, provider: OIDCProvider, on req: Request) async throws -> VerifiedIdentity { identity }
}

/// Returns a fixed tiny image so the endpoint is tested without calling Gemini.
private struct StubMindGen: MindGenerating {
    func generate(prompt: String, on req: Request) async throws -> (base64: String, mime: String) {
        ("ZmFrZS1pbWFnZQ==", "image/png")   // "fake-image"
    }
}

final class MindTests: XCTestCase {
    private func makeApp() async throws -> Application {
        let app = try await Application.make(.testing)
        app.databases.use(.sqlite(.memory), as: .sqlite)
        app.migrations.add(CreateInitialSchema())
        try await app.autoMigrate()
        app.jwt.signers.use(.hs256(key: Array("test-signing-key-0123456789abcdef".utf8)))
        let id = VerifiedIdentity(provider: .google, subject: "u1", email: "u1@example.com", isPrivateRelay: false, name: "u1")
        try app.register(collection: AuthController(oidc: StubOIDCMind(identity: id)))
        try app.register(collection: TripController())
        try app.register(collection: MindController(generator: StubMindGen()))
        return app
    }

    private func signInAndTrip(_ app: Application) async throws -> (AuthTokensDTO, TripDTO) {
        var tokens: AuthTokensDTO!
        try await app.test(.POST, "v1/auth/google",
            beforeRequest: { try $0.content.encode(["idToken": "stub"]) },
            afterResponse: { res async throws in tokens = try res.content.decode(AuthTokensDTO.self) })
        var trip: TripDTO!
        try await app.test(.POST, "v1/trips", headers: ["Authorization": "Bearer \(tokens.accessToken)"],
            beforeRequest: { try $0.content.encode(CreateTripRequest(name: "Osaka", currencyCode: "JPY", mascot: nil)) },
            afterResponse: { res async throws in trip = try res.content.decode(TripDTO.self) })
        return (tokens, trip)
    }

    private func seedBill(_ app: Application, tripID: UUID) async throws {
        let user = try await User.query(on: app.db).first()
        let bill = Bill(tripID: tripID, merchant: "Ramen", amount: 980, currencyCode: "JPY",
                        date: Date(), categoryRaw: "food", source: "manual",
                        createdByID: try XCTUnwrap(user).requireID())
        try await bill.save(on: app.db)
    }

    func testGeneratesMindForTripWithBills() async throws {
        let app = try await makeApp()
        let (t, trip) = try await signInAndTrip(app)
        try await seedBill(app, tripID: trip.id)
        try await app.test(.POST, "v1/minds", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: { try $0.content.encode(MindRequest(tripID: trip.id)) },
            afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let r = try res.content.decode(MindResponse.self)
                XCTAssertEqual(r.imageBase64, "ZmFrZS1pbWFnZQ==")
                XCTAssertEqual(r.mimeType, "image/png")
            })
        try await app.asyncShutdown()
    }

    func testEmptyTripIsRejected() async throws {
        let app = try await makeApp()
        let (t, trip) = try await signInAndTrip(app)   // no bills seeded
        try await app.test(.POST, "v1/minds", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: { try $0.content.encode(MindRequest(tripID: trip.id)) },
            afterResponse: { res async throws in
                XCTAssertEqual(res.status, .unprocessableEntity)
            })
        try await app.asyncShutdown()
    }

    func testUnknownTripIsNotFound() async throws {
        let app = try await makeApp()
        let (t, _) = try await signInAndTrip(app)
        try await app.test(.POST, "v1/minds", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: { try $0.content.encode(MindRequest(tripID: UUID())) },
            afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        try await app.asyncShutdown()
    }

    func testRequiresAuth() async throws {
        let app = try await makeApp()
        try await app.test(.POST, "v1/minds",
            beforeRequest: { try $0.content.encode(MindRequest(tripID: UUID())) },
            afterResponse: { res async throws in
                XCTAssertEqual(res.status, .unauthorized)
            })
        try await app.asyncShutdown()
    }

    func testBuildPromptIncludesTitleAndTotal() async throws {
        // Pure prompt builder — no network. Verifies the trip name + bill data land.
        let app = try await makeApp()
        let (_, tripDTO) = try await signInAndTrip(app)
        let foundTrip = try await Trip.find(tripDTO.id, on: app.db)
        let trip = try XCTUnwrap(foundTrip)
        let foundUser = try await User.query(on: app.db).first()
        let user = try XCTUnwrap(foundUser)
        let bill = Bill(tripID: tripDTO.id, merchant: "Ramen", amount: 980, currencyCode: "JPY",
                        date: Date(), categoryRaw: "food", source: "manual", createdByID: try user.requireID())
        let prompt = MindController.buildPrompt(trip: trip, bills: [bill])
        XCTAssertTrue(prompt.contains("Osaka"))
        XCTAssertTrue(prompt.contains("Ramen"))
        XCTAssertTrue(prompt.contains("980"))
        try await app.asyncShutdown()
    }
}
