import XCTVapor
import Fluent
import FluentSQLiteDriver
@testable import App

private struct StubOIDCVerifier: OIDCVerifier {
    let identity: VerifiedIdentity
    func verify(idToken: String, provider: OIDCProvider, on req: Request) async throws -> VerifiedIdentity {
        identity
    }
}

final class AuthTests: XCTestCase {
    private func makeApp(_ verified: VerifiedIdentity) async throws -> Application {
        let app = try await Application.make(.testing)
        app.databases.use(.sqlite(.memory), as: .sqlite)
        app.migrations.add(CreateInitialSchema())
        try await app.autoMigrate()
        app.jwt.signers.use(.hs256(key: Array("test-signing-key-0123456789abcdef".utf8)))
        try app.register(collection: AuthController(oidc: StubOIDCVerifier(identity: verified)))
        try app.register(collection: AccountController())
        return app
    }

    private func google(sub: String = "google-sub-1", email: String? = "erik@example.com") -> VerifiedIdentity {
        VerifiedIdentity(provider: .google, subject: sub, email: email, isPrivateRelay: false, name: "Erik")
    }

    private func signIn(_ app: Application) async throws -> AuthTokensDTO {
        var tokens: AuthTokensDTO!
        try await app.test(.POST, "v1/auth/google",
            beforeRequest: { try $0.content.encode(["idToken": "stub"]) },
            afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                tokens = try res.content.decode(AuthTokensDTO.self)
            })
        return tokens
    }

    func testSignInCreatesUserIdentityAndSession() async throws {
        let app = try await makeApp(google())
        let tokens = try await signIn(app)
        XCTAssertFalse(tokens.accessToken.isEmpty)
        XCTAssertFalse(tokens.refreshToken.isEmpty)
        let users = try await User.query(on: app.db).count()
        let identities = try await Identity.query(on: app.db).count()
        XCTAssertEqual(users, 1)
        XCTAssertEqual(identities, 1)
        try await app.asyncShutdown()
    }

    func testSameSubjectReusesUser() async throws {
        let app = try await makeApp(google())
        let first = try await signIn(app)
        let second = try await signIn(app)
        XCTAssertEqual(first.userID, second.userID)
        let userCount = try await User.query(on: app.db).count()
        XCTAssertEqual(userCount, 1)
        try await app.asyncShutdown()
    }

    func testRefreshRotatesAndOldTokenIsRevoked() async throws {
        let app = try await makeApp(google())
        let tokens = try await signIn(app)

        var rotated: AuthTokensDTO!
        try await app.test(.POST, "v1/auth/refresh",
            beforeRequest: { try $0.content.encode(["refreshToken": tokens.refreshToken]) },
            afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                rotated = try res.content.decode(AuthTokensDTO.self)
            })
        XCTAssertNotEqual(rotated.refreshToken, tokens.refreshToken)

        // Re-using the now-rotated old refresh token must fail.
        try await app.test(.POST, "v1/auth/refresh",
            beforeRequest: { try $0.content.encode(["refreshToken": tokens.refreshToken]) },
            afterResponse: { res async throws in
                XCTAssertEqual(res.status, .unauthorized)
            })
        try await app.asyncShutdown()
    }

    func testMeRequiresAuth() async throws {
        let app = try await makeApp(google())
        let tokens = try await signIn(app)

        try await app.test(.GET, "v1/account/me", afterResponse: { res async in
            XCTAssertEqual(res.status, .unauthorized)
        })
        try await app.test(.GET, "v1/account/me",
            headers: ["Authorization": "Bearer \(tokens.accessToken)"],
            afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let dto = try res.content.decode(UserDTO.self)
                XCTAssertEqual(dto.id, tokens.userID)
            })
        try await app.asyncShutdown()
    }

    func testDeleteAccountPurgesUserData() async throws {
        let app = try await makeApp(google())
        let tokens = try await signIn(app)

        // Seed a trip + bill owned by the user.
        let trip = Trip(ownerID: tokens.userID, name: "Osaka", currencyCode: "JPY")
        try await trip.save(on: app.db)
        let bill = Bill(tripID: try trip.requireID(), merchant: "Ichiran",
                        amount: 2840, currencyCode: "JPY", date: Date(),
                        categoryRaw: "food", source: "text", createdByID: tokens.userID)
        try await bill.save(on: app.db)

        try await app.test(.DELETE, "v1/account",
            headers: ["Authorization": "Bearer \(tokens.accessToken)"],
            afterResponse: { res async in
                XCTAssertEqual(res.status, .noContent)
            })

        let users = try await User.query(on: app.db).count()
        let identities = try await Identity.query(on: app.db).count()
        let trips = try await Trip.query(on: app.db).count()
        let bills = try await Bill.query(on: app.db).count()
        let refresh = try await RefreshToken.query(on: app.db).count()
        XCTAssertEqual(users, 0)
        XCTAssertEqual(identities, 0)
        XCTAssertEqual(trips, 0)
        XCTAssertEqual(bills, 0)
        XCTAssertEqual(refresh, 0)
        try await app.asyncShutdown()
    }
}
