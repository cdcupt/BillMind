import XCTVapor
import Fluent
import FluentSQLiteDriver
import BillMindCore
@testable import App

private struct StubOIDC2: OIDCVerifier {
    let identity: VerifiedIdentity
    func verify(idToken: String, provider: OIDCProvider, on req: Request) async throws -> VerifiedIdentity { identity }
}

private struct StubMod: ModerationClient {
    let scores: [String: Double]
    func score(_ text: String, on req: Request) async throws -> ModerationScores { ModerationScores(categories: scores) }
}

private struct StubRecognizer: Recognizer {
    var result = AIRecognitionResult(merchant: "Konbini", totalAmount: 980, currency: "JPY", category: "food")
    func recognize(imageBase64: String, mimeType: String, on req: Request) async throws -> AIRecognitionResult { result }
}

private struct StubTextRecognizer: TextRecognizer {
    let drafts: [BillDraft]
    func recognize(text: String, currencyCode: String, today: String, on req: Request) async -> [BillDraft] { drafts }
}

final class CaptureTests: XCTestCase {
    private func makeApp(modScores: [String: Double] = [:],
                         textRecognizer: TextRecognizer = LocalTextRecognizer()) async throws -> Application {
        let app = try await Application.make(.testing)
        app.databases.use(.sqlite(.memory), as: .sqlite)
        app.migrations.add(CreateInitialSchema())
        try await app.autoMigrate()
        app.jwt.signers.use(.hs256(key: Array("test-signing-key-0123456789abcdef".utf8)))
        let id = VerifiedIdentity(provider: .google, subject: "u1", email: "u1@example.com", isPrivateRelay: false, name: "u1")
        try app.register(collection: AuthController(oidc: StubOIDC2(identity: id)))
        try app.register(collection: TripController())
        try app.register(collection: BillController())
        try app.register(collection: CaptureController(
            moderation: ModerationService(client: StubMod(scores: modScores)),
            recognizer: StubRecognizer(),
            textRecognizer: textRecognizer))
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

    func testTextCaptureWithAmountIsSavable() async throws {
        let app = try await makeApp()
        let (t, trip) = try await signInAndTrip(app)
        try await app.test(.POST, "v1/recognition", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: { try $0.content.encode(CaptureRequest(text: "ramen 2840", tripID: trip.id)) },
            afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let r = try res.content.decode(CaptureResponse.self)
                XCTAssertFalse(r.declined)
                XCTAssertEqual(r.card?.draft.amount, Decimal(2840))
                XCTAssertEqual(r.card?.draft.categoryRaw, "food")
                XCTAssertEqual(r.card?.canSave, true)
                XCTAssertFalse(r.card?.gaps.contains { $0.field == "amount" } ?? true)
            })
        try await app.asyncShutdown()
    }

    func testTextCaptureWithoutAmountCannotSave() async throws {
        let app = try await makeApp()
        let (t, trip) = try await signInAndTrip(app)
        try await app.test(.POST, "v1/recognition", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: { try $0.content.encode(CaptureRequest(text: "dinner in kyoto", tripID: trip.id)) },
            afterResponse: { res async throws in
                let r = try res.content.decode(CaptureResponse.self)
                XCTAssertNil(r.card?.draft.amount)
                XCTAssertEqual(r.card?.canSave, false)        // never guess money
                XCTAssertTrue(r.card?.gaps.contains { $0.field == "amount" } ?? false)
            })
        try await app.asyncShutdown()
    }

    /// Text capture routes through the injected `TextRecognizer` (the AI path) —
    /// here a stub returns a draft the local parser couldn't get from the words.
    func testTextCaptureUsesTheTextRecognizer() async throws {
        let aiDraft = BillDraft(merchant: "Airport Taxi", amount: Decimal(3000), currencyCode: "JPY",
                                date: nil, categoryRaw: "transport", source: .text)
        let app = try await makeApp(textRecognizer: StubTextRecognizer(drafts: [aiDraft]))
        let (t, trip) = try await signInAndTrip(app)
        try await app.test(.POST, "v1/recognition", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: { try $0.content.encode(CaptureRequest(text: "cab from the airport, about 3000", tripID: trip.id)) },
            afterResponse: { res async throws in
                let r = try res.content.decode(CaptureResponse.self)
                XCTAssertEqual(r.cards.count, 1)
                XCTAssertEqual(r.card?.draft.merchant, "Airport Taxi")
                XCTAssertEqual(r.card?.draft.amount, Decimal(3000))
                XCTAssertEqual(r.card?.draft.categoryRaw, "transport")
            })
        try await app.asyncShutdown()
    }

    /// One sentence → several bills: the text recognizer returns multiple drafts and
    /// the response carries one card per bill (with `card` = the first, for compat).
    func testTextCaptureProducesMultipleCards() async throws {
        let drafts = [
            BillDraft(merchant: "Lunch", amount: Decimal(500), currencyCode: "JPY", date: nil, categoryRaw: "food", source: .text),
            BillDraft(merchant: "Taxi", amount: Decimal(200), currencyCode: "JPY", date: nil, categoryRaw: "transport", source: .text),
            BillDraft(merchant: "Coffee", amount: Decimal(80), currencyCode: "JPY", date: nil, categoryRaw: "food", source: .text),
        ]
        let app = try await makeApp(textRecognizer: StubTextRecognizer(drafts: drafts))
        let (t, trip) = try await signInAndTrip(app)
        try await app.test(.POST, "v1/recognition", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: { try $0.content.encode(CaptureRequest(text: "lunch 500, taxi 200, coffee 80", tripID: trip.id)) },
            afterResponse: { res async throws in
                let r = try res.content.decode(CaptureResponse.self)
                XCTAssertEqual(r.cards.count, 3)
                XCTAssertEqual(r.cards.map { $0.draft.merchant }, ["Lunch", "Taxi", "Coffee"])
                XCTAssertEqual(r.cards.map { $0.draft.amount }, [Decimal(500), Decimal(200), Decimal(80)])
                XCTAssertEqual(r.card?.draft.merchant, "Lunch")   // compat: first card
            })
        try await app.asyncShutdown()
    }

    /// The live Gemini text recognizer degrades gracefully: with no GEMINI_API_KEY
    /// it falls back to the deterministic DraftExtractor (offline/E2E still works).
    func testGeminiTextRecognizerFallsBackToLocalWithoutKey() async throws {
        let app = try await makeApp(textRecognizer: GeminiTextRecognizer())
        let (t, trip) = try await signInAndTrip(app)
        try await app.test(.POST, "v1/recognition", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: { try $0.content.encode(CaptureRequest(text: "ramen 2840", tripID: trip.id)) },
            afterResponse: { res async throws in
                let r = try res.content.decode(CaptureResponse.self)
                XCTAssertEqual(r.card?.draft.amount, Decimal(2840))   // parsed locally
                XCTAssertEqual(r.card?.draft.categoryRaw, "food")
            })
        try await app.asyncShutdown()
    }

    /// The client's local date is accepted only when it's a strict, near-now
    /// yyyy-MM-dd — otherwise we fall back to UTC today (and never inject junk).
    func testValidClientDateGuard() {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: Date())

        XCTAssertEqual(CaptureController.validClientDate(today), today)        // accepted
        XCTAssertNil(CaptureController.validClientDate("2020-01-01"))          // too far in the past
        XCTAssertNil(CaptureController.validClientDate("2099-12-31"))          // too far in the future
        XCTAssertNil(CaptureController.validClientDate("not-a-date"))          // garbage
        XCTAssertNil(CaptureController.validClientDate("2026-13-40"))          // impossible
        XCTAssertNil(CaptureController.validClientDate("\(today)'; DROP"))     // injection attempt
        XCTAssertNil(CaptureController.validClientDate(nil))                   // absent
    }

    func testConfirmWritesBill() async throws {
        let app = try await makeApp()
        let (t, trip) = try await signInAndTrip(app)
        try await app.test(.POST, "v1/bills/confirm", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: {
                try $0.content.encode(ConfirmRequest(tripID: trip.id, merchant: "Ichiran", amount: 2840,
                    currencyCode: "JPY", date: Date(), categoryRaw: "food", source: "text"))
            },
            afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let bill = try res.content.decode(BillDTO.self)
                XCTAssertEqual(bill.amount, Decimal(2840))
            })
        let count = try await Bill.query(on: app.db).count()
        XCTAssertEqual(count, 1)
        try await app.asyncShutdown()
    }

    func testConfirmWithoutAmountRejected() async throws {
        let app = try await makeApp()
        let (t, trip) = try await signInAndTrip(app)
        try await app.test(.POST, "v1/bills/confirm", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: {
                try $0.content.encode(ConfirmRequest(tripID: trip.id, merchant: "Mystery", amount: nil,
                    currencyCode: "JPY", date: Date(), categoryRaw: "food", source: "text"))
            },
            afterResponse: { res async in
                XCTAssertEqual(res.status, .unprocessableEntity)   // amount required, never guessed
            })
        let count = try await Bill.query(on: app.db).count()
        XCTAssertEqual(count, 0)
        try await app.asyncShutdown()
    }

    func testCaptureDeclinedOnHardBlock() async throws {
        let app = try await makeApp(modScores: ["sexual/minors": 0.95])
        let (t, trip) = try await signInAndTrip(app)
        try await app.test(.POST, "v1/recognition", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: { try $0.content.encode(CaptureRequest(text: "...", tripID: trip.id)) },
            afterResponse: { res async throws in
                let r = try res.content.decode(CaptureResponse.self)
                XCTAssertTrue(r.declined)
                XCTAssertNil(r.card)
            })
        try await app.asyncShutdown()
    }
}
