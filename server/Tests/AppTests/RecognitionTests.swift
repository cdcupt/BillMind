import XCTVapor
import Fluent
import FluentSQLiteDriver
import BillMindCore
@testable import App

private struct StubOIDC5: OIDCVerifier {
    let identity: VerifiedIdentity
    func verify(idToken: String, provider: OIDCProvider, on req: Request) async throws -> VerifiedIdentity { identity }
}
private struct AllowMod2: ModerationClient {
    func score(_ text: String, on req: Request) async throws -> ModerationScores { ModerationScores(categories: [:]) }
}
private struct FixedRecognizer: Recognizer {
    let result: AIRecognitionResult
    func recognize(imageBase64: String, mimeType: String, on req: Request) async throws -> AIRecognitionResult { result }
}

final class RecognitionTests: XCTestCase {
    // The pure parse — Gemini returns fenced JSON; we extract + decode it.
    func testGeminiRecognizerParsesFencedJSON() throws {
        let body = #"""
        {"candidates":[{"content":{"parts":[{"text":"```json\n{\"merchant\":\"Ichiran\",\"totalAmount\":2840,\"currency\":\"JPY\",\"category\":\"food\"}\n```"}]}}]}
        """#
        let result = try GeminiRecognizer.parse(Data(body.utf8))
        XCTAssertEqual(result.merchant, "Ichiran")
        XCTAssertEqual(result.parsedAmount, Decimal(2840))
        XCTAssertEqual(result.category, "food")
    }

    func testGeminiRecognizerOmitsUnreadableTotal() throws {
        let body = #"{"candidates":[{"content":{"parts":[{"text":"{\"merchant\":\"Blurry\",\"currency\":\"JPY\"}"}]}}]}"#
        let result = try GeminiRecognizer.parse(Data(body.utf8))
        XCTAssertNil(result.parsedAmount)   // never invented
    }

    // The photo capture path end-to-end (stub recognizer → card).
    func testPhotoCaptureProducesCard() async throws {
        let app = try await Application.make(.testing)
        app.databases.use(.sqlite(.memory), as: .sqlite)
        app.migrations.add(CreateInitialSchema())
        try await app.autoMigrate()
        app.jwt.signers.use(.hs256(key: Array("test-signing-key-0123456789abcdef".utf8)))
        let id = VerifiedIdentity(provider: .google, subject: "u1", email: "u1@example.com", isPrivateRelay: false, name: "u1")
        try app.register(collection: AuthController(oidc: StubOIDC5(identity: id)))
        try app.register(collection: TripController())
        try app.register(collection: CaptureController(
            moderation: ModerationService(client: AllowMod2()),
            recognizer: FixedRecognizer(result: AIRecognitionResult(
                merchant: "Konbini", totalAmount: 980, currency: "JPY", category: "food"))))

        var t: AuthTokensDTO!
        try await app.test(.POST, "v1/auth/google",
            beforeRequest: { try $0.content.encode(["idToken": "stub"]) },
            afterResponse: { res async throws in t = try res.content.decode(AuthTokensDTO.self) })
        var trip: TripDTO!
        try await app.test(.POST, "v1/trips", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: { try $0.content.encode(CreateTripRequest(name: "Osaka", currencyCode: "JPY", mascot: nil)) },
            afterResponse: { res async throws in trip = try res.content.decode(TripDTO.self) })

        try await app.test(.POST, "v1/recognition", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: { try $0.content.encode(CaptureRequest(tripID: trip.id, imageBase64: "ZmFrZQ==", mimeType: "image/jpeg")) },
            afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let r = try res.content.decode(CaptureResponse.self)
                XCTAssertFalse(r.declined)
                XCTAssertEqual(r.card?.draft.merchant, "Konbini")
                XCTAssertEqual(r.card?.draft.amount, Decimal(980))
                XCTAssertEqual(r.card?.canSave, true)
            })
        try await app.asyncShutdown()
    }
}
