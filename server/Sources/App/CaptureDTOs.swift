import Vapor
import BillMindCore

/// A draft serialized for the client to render + edit.
struct BillDraftDTO: Content {
    let merchant: String?
    @OptionalDecimalString var amount: Decimal?
    let currencyCode: String
    let categoryRaw: String?
    let date: Date?
    let source: String

    init(_ d: BillDraft) {
        self.merchant = d.merchant
        self.amount = d.amount
        self.currencyCode = d.currencyCode
        self.categoryRaw = d.categoryRaw
        self.date = d.date
        self.source = d.source.rawValue
    }

    init(merchant: String?, amount: Decimal?, currencyCode: String,
         categoryRaw: String?, date: Date?, source: String) {
        self.merchant = merchant
        self.amount = amount
        self.currencyCode = currencyCode
        self.categoryRaw = categoryRaw
        self.date = date
        self.source = source
    }

    /// Rebuild a core `BillDraft` from the wire DTO so the existing `BillValidator`
    /// can gate a resolved fused draft exactly as the recognition path does.
    func asDraft() -> BillDraft {
        BillDraft(
            merchant: merchant,
            amount: amount,
            currencyCode: currencyCode,
            date: date,
            categoryRaw: categoryRaw,
            source: DraftSource(rawValue: source) ?? .manual
        )
    }
}

/// A validation gap → the chip-answerable clarification the client renders.
struct GapDTO: Content {
    let field: String
    let reason: String
    let prompt: String
    let options: [String]
}

/// The server-rendered capture card. `canSave` is the hard gate: amount present.
///
/// `clientCardID` is a per-session UUID the client assigns to each held card so
/// the untangle plan (POST /v1/untangle) can reference cards by a stable id. It is
/// additive and optional: older clients omit it and the field decodes as nil, so
/// the recognition contract is unchanged.
struct CardDTO: Content {
    let tripID: UUID
    let draft: BillDraftDTO
    let gaps: [GapDTO]
    let canSave: Bool
    let clientCardID: UUID?

    init(tripID: UUID, draft: BillDraftDTO, gaps: [GapDTO], canSave: Bool, clientCardID: UUID? = nil) {
        self.tripID = tripID
        self.draft = draft
        self.gaps = gaps
        self.canSave = canSave
        self.clientCardID = clientCardID
    }
}

/// Recognition result: a list of cards to confirm (one per recognized bill — a
/// single sentence can yield several), or a calm decline. `card` is kept as the
/// first card for backward-compatibility with older clients; new clients use
/// `cards`.
struct CaptureResponse: Content {
    let declined: Bool
    let message: String?
    let card: CardDTO?
    let cards: [CardDTO]

    static func declinedResponse(_ message: String) -> CaptureResponse {
        CaptureResponse(declined: true, message: message, card: nil, cards: [])
    }

    static func cardsResponse(_ cards: [CardDTO]) -> CaptureResponse {
        CaptureResponse(declined: false, message: nil, card: cards.first, cards: cards)
    }
}

struct CaptureRequest: Content {
    let text: String?
    let tripID: UUID
    let imageBase64: String?
    let mimeType: String?
    /// The device's local date (yyyy-MM-dd) so relative dates ("today", "yesterday")
    /// resolve against the user's calendar, not the server's UTC clock.
    let clientDate: String?

    init(text: String? = nil, tripID: UUID, imageBase64: String? = nil, mimeType: String? = nil,
         clientDate: String? = nil) {
        self.text = text
        self.tripID = tripID
        self.imageBase64 = imageBase64
        self.mimeType = mimeType
        self.clientDate = clientDate
    }
}

/// The resolved draft the client confirms → the only write path.
struct ConfirmRequest: Content {
    let tripID: UUID
    let merchant: String?
    @OptionalDecimalString var amount: Decimal?
    let currencyCode: String?
    let date: Date?
    let categoryRaw: String?
    let source: String?
}
