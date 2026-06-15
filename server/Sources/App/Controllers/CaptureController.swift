import Vapor
import Fluent
import BillMindCore

/// `POST /v1/recognition` — capture entry for text OR a photo:
/// text → local DraftExtractor; image → Gemini vision → AIRecognitionMapper.
/// Both run the moderation gate first and return the same CardDTO. Amount is
/// never guessed (the validator flags a missing amount; canSave gates on it).
struct CaptureController: RouteCollection {
    let moderation: ModerationService
    let recognizer: Recognizer
    let textRecognizer: TextRecognizer

    init(moderation: ModerationService, recognizer: Recognizer,
         textRecognizer: TextRecognizer = LocalTextRecognizer()) {
        self.moderation = moderation
        self.recognizer = recognizer
        self.textRecognizer = textRecognizer
    }

    func boot(routes: RoutesBuilder) throws {
        let group = routes.grouped("v1").grouped(UserAuthMiddleware())
        group.post("recognition", use: recognize)
    }

    func recognize(_ req: Request) async throws -> CaptureResponse {
        let user = try req.auth.require(User.self)
        let uid = try user.requireID()
        let body = try req.content.decode(CaptureRequest.self)

        guard let trip = try await Trip.query(on: req.db)
            .filter(\.$id == body.tripID).filter(\.$owner.$id == uid).first()
        else { throw Abort(.notFound, reason: "trip not found") }

        let draft: BillDraft

        if let imageBase64 = body.imageBase64, !imageBase64.isEmpty {
            // Photo path — server-side recognition.
            let result = try await recognizer.recognize(imageBase64: imageBase64,
                                                         mimeType: body.mimeType ?? "image/jpeg", on: req)
            // Moderate the recognized text (treated as untrusted), catastrophic-only.
            let recognizedText = [result.merchant, result.notes].compactMap { $0 }.joined(separator: " ")
            if let declined = try await guardModeration(recognizedText.isEmpty ? "receipt" : recognizedText,
                                                        uid: uid, req: req) { return declined }
            draft = AIRecognitionMapper.draft(from: result, currencyCode: trip.currencyCode)

        } else if let text = body.text, !text.isEmpty {
            // Text path — AI (Gemini) with a deterministic local fallback. Moderate
            // first (untrusted input), then recognize; the validator still guards
            // money downstream (a missing amount blocks Save, never guessed).
            if let declined = try await guardModeration(text, uid: uid, req: req,
                                                        expenseShaped: DraftExtractor.firstAmount(in: text) != nil) {
                return declined
            }
            draft = await textRecognizer.recognize(text: text, currencyCode: trip.currencyCode, on: req)

        } else {
            throw Abort(.badRequest, reason: "provide text or imageBase64")
        }

        return makeCard(draft, tripID: try trip.requireID(), currencyCode: trip.currencyCode)
    }

    /// Runs the gate; returns a decline response if blocked, else nil (proceed).
    private func guardModeration(_ text: String, uid: UUID, req: Request,
                                 expenseShaped: Bool = true) async throws -> CaptureResponse? {
        let verdict = try await moderation.evaluate(text, surface: .recognition, expenseShaped: expenseShaped, on: req)
        try await moderation.logEvent(verdict, raw: text, surface: .recognition, userID: uid,
                                      requestID: req.id, on: req.db)
        guard verdict.decision == .block else { return nil }
        return CaptureResponse(declined: true,
                               message: "I can't help with that one — I'm your travel-and-money agent.",
                               card: nil)
    }

    private func makeCard(_ draft: BillDraft, tripID: UUID, currencyCode: String) -> CaptureResponse {
        let validator = BillValidator(
            knownCategoryRaws: Set(BillCategory.allCases.map(\.rawValue)),
            journalCurrencyCode: currencyCode, today: Date()
        )
        let gaps = validator.validate(draft).map {
            GapDTO(field: $0.field.rawValue, reason: $0.reason,
                   prompt: $0.question.prompt, options: $0.question.options.map(\.label))
        }
        let card = CardDTO(tripID: tripID, draft: BillDraftDTO(draft), gaps: gaps, canSave: draft.amount != nil)
        return CaptureResponse(declined: false, message: nil, card: card)
    }
}
