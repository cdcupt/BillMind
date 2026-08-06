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

/// Counts every `score` call and records the texts it was asked to evaluate, so a
/// test can assert the caption actually went through the moderation gate.
private final class SpyMod: ModerationClient, @unchecked Sendable {
    let scores: [String: Double]
    private let lock = NSLock()
    private(set) var seen: [String] = []
    var callCount: Int { lock.lock(); defer { lock.unlock() }; return seen.count }

    init(scores: [String: Double] = [:]) { self.scores = scores }

    func score(_ text: String, on req: Request) async throws -> ModerationScores {
        lock.lock(); seen.append(text); lock.unlock()
        return ModerationScores(categories: scores)
    }
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
                         textRecognizer: TextRecognizer = LocalTextRecognizer(),
                         recognizer: Recognizer = StubRecognizer(),
                         moderationClient: ModerationClient? = nil) async throws -> Application {
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
            moderation: ModerationService(client: moderationClient ?? StubMod(scores: modScores)),
            recognizer: recognizer,
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

    func testTextCaptureCarriesRawDateTextOverTheWire() async throws {
        // An ambiguous slash date must reach the client as rawDateText so its
        // date clarify fires — otherwise the client stamps "today" over what the
        // user actually typed.
        let app = try await makeApp()
        let (t, trip) = try await signInAndTrip(app)
        try await app.test(.POST, "v1/recognition", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: { try $0.content.encode(CaptureRequest(text: "05/08/2026 taxi 20", tripID: trip.id)) },
            afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let r = try res.content.decode(CaptureResponse.self)
                XCTAssertEqual(r.card?.draft.rawDateText, "05/08/2026")
                XCTAssertNil(r.card?.draft.date)
                XCTAssertEqual(r.card?.draft.amount, Decimal(20))
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

    /// A phone photo arrives base64-in-JSON and easily clears the 1mb global cap
    /// (`defaultMaxBodySize`). The recognition route sets its own 10mb ceiling, so a
    /// ~2MB payload must succeed (`.ok`) rather than 413 — this is the "413 Payload
    /// Too Large" fix. The StubRecognizer ignores the image bytes.
    func testRecognitionAcceptsLargePhotoPayloadOverGlobalCap() async throws {
        let app = try await makeApp()
        let (t, trip) = try await signInAndTrip(app)

        // ~2MB of valid base64 chars — over the 1mb global cap, under the 10mb route cap.
        let bigBase64 = String(repeating: "A", count: 2 * 1024 * 1024)
        XCTAssertGreaterThan(bigBase64.count, 1 * 1024 * 1024)   // exceeds the global 1mb cap

        try await app.test(.POST, "v1/recognition", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: {
                try $0.content.encode(CaptureRequest(tripID: trip.id, imageBase64: bigBase64, mimeType: "image/jpeg"))
            },
            afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)                  // NOT .payloadTooLarge — route's 10mb limit
                let r = try res.content.decode(CaptureResponse.self)
                XCTAssertFalse(r.declined)
                XCTAssertNotNil(r.card)                          // StubRecognizer returned a card
            })
        try await app.asyncShutdown()
    }

    // MARK: - Compose (photo + caption → one card)

    /// Compose path: a staged photo whose total the OCR could NOT read, plus a
    /// caption that states it ("total was 240"). The two arrive as ONE request and
    /// come back as ONE card whose amount is filled from the caption — money is never
    /// invented, but a clearly-stated caption total fills the photo's gap.
    func testComposePhotoPlusCaptionReturnsOneCard() async throws {
        // Stub photo result with NO total (cut-off receipt) but a real merchant/category.
        let photoNoAmount = AIRecognitionResult(merchant: "Sakura Diner", totalAmount: nil,
                                                currency: "JPY", category: "food")
        let app = try await makeApp(recognizer: StubRecognizer(result: photoNoAmount))
        let (t, trip) = try await signInAndTrip(app)
        let tinyJPEG = String(repeating: "A", count: 64)   // stub ignores the bytes
        try await app.test(.POST, "v1/recognition", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: {
                try $0.content.encode(CaptureRequest(text: "total was 240, lunch with the team",
                                                     tripID: trip.id, imageBase64: tinyJPEG, mimeType: "image/jpeg"))
            },
            afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let r = try res.content.decode(CaptureResponse.self)
                XCTAssertFalse(r.declined)
                XCTAssertEqual(r.cards.count, 1)                            // ONE card from both
                XCTAssertEqual(r.card?.draft.amount, Decimal(240))         // caption filled the missing total
                XCTAssertEqual(r.card?.draft.merchant, "Sakura Diner")     // photo's merchant kept
                XCTAssertEqual(r.card?.draft.categoryRaw, "food")          // photo's category kept
                XCTAssertEqual(r.card?.canSave, true)                       // amount present → savable
                XCTAssertFalse(r.card?.gaps.contains { $0.field == "amount" } ?? true)
            })
        try await app.asyncShutdown()
    }

    /// Compose still honours the money rule: when NEITHER the photo OCR nor the
    /// caption yields a total, the one card comes back amount-less and the validator's
    /// "amount required" gate blocks Save — the caption never invents a number.
    func testComposeWithNoAmountAnywhereCannotSave() async throws {
        let photoNoAmount = AIRecognitionResult(merchant: "Faded Receipt", totalAmount: nil,
                                                currency: "JPY", category: "shopping")
        let app = try await makeApp(recognizer: StubRecognizer(result: photoNoAmount))
        let (t, trip) = try await signInAndTrip(app)
        try await app.test(.POST, "v1/recognition", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: {
                try $0.content.encode(CaptureRequest(text: "souvenirs for the office",   // no number
                                                     tripID: trip.id, imageBase64: "AAAA", mimeType: "image/jpeg"))
            },
            afterResponse: { res async throws in
                let r = try res.content.decode(CaptureResponse.self)
                XCTAssertEqual(r.cards.count, 1)
                XCTAssertNil(r.card?.draft.amount)                          // never invented
                XCTAssertEqual(r.card?.canSave, false)
                XCTAssertTrue(r.card?.gaps.contains { $0.field == "amount" } ?? false)
            })
        try await app.asyncShutdown()
    }

    /// The caption is user free-text, so it MUST pass through the moderation gate just
    /// like the text path. The spy asserts `score` was called at least once with the
    /// caption text during a composed send.
    func testComposeCaptionIsModerated() async throws {
        let spy = SpyMod()   // benign scores → allow
        let app = try await makeApp(recognizer: StubRecognizer(result:
                AIRecognitionResult(merchant: "Hotel Kyoto", totalAmount: nil, currency: "JPY", category: "accommodation")),
            moderationClient: spy)
        let (t, trip) = try await signInAndTrip(app)
        let caption = "the total was 1820, two nights"
        try await app.test(.POST, "v1/recognition", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: {
                try $0.content.encode(CaptureRequest(text: caption, tripID: trip.id,
                                                     imageBase64: "AAAA", mimeType: "image/jpeg"))
            },
            afterResponse: { res async throws in
                let r = try res.content.decode(CaptureResponse.self)
                XCTAssertFalse(r.declined)
                XCTAssertEqual(r.card?.draft.amount, Decimal(1820))        // caption filled total
            })
        XCTAssertGreaterThanOrEqual(spy.callCount, 1)                       // caption was evaluated
        XCTAssertTrue(spy.seen.contains { $0.contains("1820") })           // and it was THIS caption
        try await app.asyncShutdown()
    }

    /// Regression: the image-only and text-only paths still behave exactly as before
    /// — the new compose branch only fires when BOTH fields are non-empty.
    func testImageOnlyAndTextOnlyUnchanged() async throws {
        let app = try await makeApp()   // StubRecognizer default: Konbini / 980 / food
        let (t, trip) = try await signInAndTrip(app)

        // Image-only: no caption → photo recognised alone (the stub's 980 total).
        try await app.test(.POST, "v1/recognition", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: {
                try $0.content.encode(CaptureRequest(tripID: trip.id, imageBase64: "AAAA", mimeType: "image/jpeg"))
            },
            afterResponse: { res async throws in
                let r = try res.content.decode(CaptureResponse.self)
                XCTAssertEqual(r.cards.count, 1)
                XCTAssertEqual(r.card?.draft.merchant, "Konbini")
                XCTAssertEqual(r.card?.draft.amount, Decimal(980))         // straight from the photo
                XCTAssertEqual(r.card?.draft.categoryRaw, "food")
            })

        // Text-only: no image → local DraftExtractor parses the sentence.
        try await app.test(.POST, "v1/recognition", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: { try $0.content.encode(CaptureRequest(text: "ramen 2840", tripID: trip.id)) },
            afterResponse: { res async throws in
                let r = try res.content.decode(CaptureResponse.self)
                XCTAssertEqual(r.cards.count, 1)
                XCTAssertEqual(r.card?.draft.amount, Decimal(2840))
                XCTAssertEqual(r.card?.draft.categoryRaw, "food")
                XCTAssertEqual(r.card?.canSave, true)
            })
        try await app.asyncShutdown()
    }
}
