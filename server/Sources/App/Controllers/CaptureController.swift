import Vapor
import Fluent
import BillMindCore

/// `POST /v1/recognition` — the text-capture entry: moderation gate → local
/// DraftExtractor → BillValidator → a card. (Photo/Gemini recognition lands in a
/// later slice; the same card shape is returned.)
struct CaptureController: RouteCollection {
    let moderation: ModerationService

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

        // Moderation gate (capture surface = catastrophic-only; expense-shaped text
        // raises the gray-zone bar so a lawful purchase never blocks).
        let expenseShaped = DraftExtractor.firstAmount(in: body.text) != nil
        let verdict = try await moderation.evaluate(body.text, surface: .recognition,
                                                    expenseShaped: expenseShaped, on: req)
        try await moderation.logEvent(verdict, raw: body.text, surface: .recognition,
                                      userID: uid, requestID: req.id, on: req.db)
        if verdict.decision == .block {
            return CaptureResponse(declined: true,
                                   message: "I can't help with that one — I'm your travel-and-money agent.",
                                   card: nil)
        }

        // Recognition (local, deterministic) → validation. Amount is never guessed.
        let draft = DraftExtractor.parse(body.text, currencyCode: trip.currencyCode)
        let validator = BillValidator(
            knownCategoryRaws: Set(BillCategory.allCases.map(\.rawValue)),
            journalCurrencyCode: trip.currencyCode, today: Date()
        )
        let gaps = validator.validate(draft).map {
            GapDTO(field: $0.field.rawValue, reason: $0.reason,
                   prompt: $0.question.prompt, options: $0.question.options.map(\.label))
        }
        let card = CardDTO(tripID: try trip.requireID(), draft: BillDraftDTO(draft),
                           gaps: gaps, canSave: draft.amount != nil)
        return CaptureResponse(declined: false, message: nil, card: card)
    }
}
