import Vapor
import BillMindCore

/// A draft serialized for the client to render + edit.
struct BillDraftDTO: Content {
    let merchant: String?
    let amount: Decimal?
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
}

/// A validation gap → the chip-answerable clarification the client renders.
struct GapDTO: Content {
    let field: String
    let reason: String
    let prompt: String
    let options: [String]
}

/// The server-rendered capture card. `canSave` is the hard gate: amount present.
struct CardDTO: Content {
    let tripID: UUID
    let draft: BillDraftDTO
    let gaps: [GapDTO]
    let canSave: Bool
}

/// Recognition result: either a card to confirm, or a calm decline.
struct CaptureResponse: Content {
    let declined: Bool
    let message: String?
    let card: CardDTO?
}

struct CaptureRequest: Content {
    let text: String?
    let tripID: UUID
    let imageBase64: String?
    let mimeType: String?

    init(text: String? = nil, tripID: UUID, imageBase64: String? = nil, mimeType: String? = nil) {
        self.text = text
        self.tripID = tripID
        self.imageBase64 = imageBase64
        self.mimeType = mimeType
    }
}

/// The resolved draft the client confirms → the only write path.
struct ConfirmRequest: Content {
    let tripID: UUID
    let merchant: String?
    let amount: Decimal?
    let currencyCode: String?
    let date: Date?
    let categoryRaw: String?
    let source: String?
}
