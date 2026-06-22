import Vapor
import BillMindCore

/// DTOs for `POST /v1/untangle` — the held-batch reasoning hop. The client sends
/// the cards it already holds (from /v1/recognition, no image bytes) and gets back
/// a PLAN over those cards: which are one bill (fuse), which are the same bill
/// (dup), and which are clean. The save path is unchanged; this returns a plan only.
///
/// Money rule: an amount on a fused card is provenance-traced (`amountTrace`) to a
/// real input the user provided. The server enforces this regardless of the model
/// (see UntangleController's verbatim post-check); the client never invents one.

// MARK: - Request

/// One held card the client is asking the server to reason about. Carries the
/// recognized `draft` (no image bytes — only a `photoHash` for same-photo dedup)
/// plus the optional note/photo provenance signals the reasoner may use.
struct UntangleInput: Content {
    let cardID: UUID
    let draft: BillDraftDTO
    let hasPhoto: Bool
    let noteText: String?
    let photoHash: String?
    let photoAssetID: String?

    init(cardID: UUID, draft: BillDraftDTO, hasPhoto: Bool = false,
         noteText: String? = nil, photoHash: String? = nil, photoAssetID: String? = nil) {
        self.cardID = cardID
        self.draft = draft
        self.hasPhoto = hasPhoto
        self.noteText = noteText
        self.photoHash = photoHash
        self.photoAssetID = photoAssetID
    }
}

struct UntangleRequest: Content {
    let tripID: UUID
    /// The device's local date (yyyy-MM-dd); validated server-side before use.
    let clientDate: String?
    let inputs: [UntangleInput]

    init(tripID: UUID, clientDate: String? = nil, inputs: [UntangleInput]) {
        self.tripID = tripID
        self.clientDate = clientDate
        self.inputs = inputs
    }
}

// MARK: - Response

/// Where the (single) amount on a fused card came from. `null` ⇒ no card supplied
/// the amount → the client renders "amount required" and never invents one.
struct AmountTraceDTO: Content {
    let sourceCardID: UUID
    let field: String   // e.g. "amount" — the member-card field the value traces to

    init(sourceCardID: UUID, field: String = "amount") {
        self.sourceCardID = sourceCardID
        self.field = field
    }
}

/// Several cards that together describe ONE bill (e.g. a partial photo completed by
/// a note). `resolvedDraft` is assembled field-by-field from member cards; its
/// amount is byte-equal to one member's amount (or omitted), traced by `amountTrace`.
struct FuseGroupDTO: Content {
    let groupID: UUID
    let sourceCardIDs: [UUID]
    let resolvedDraft: BillDraftDTO
    let amountTrace: AmountTraceDTO?
    let reason: String
    let confidence: Double
}

/// Several cards that are the SAME bill (duplicates). `survivorCardID` is the one
/// to keep; the rest are set aside (never persisted — no delete). `tier` records
/// how the duplicate was detected.
struct DuplicateGroupDTO: Content {
    let groupID: UUID
    let memberCardIDs: [UUID]
    let survivorCardID: UUID
    let tier: String    // "samePhoto" | "sameDetails"
    let reason: String
}

/// The untangle plan. Partition invariant: every input cardID appears in EXACTLY
/// one of fuseGroups / duplicateGroups / cleanCardIDs (the server guarantees it;
/// the client also validates against its live cards and fails open if not).
struct UntangleResponse: Content {
    let declined: Bool
    let message: String?
    let fuseGroups: [FuseGroupDTO]
    let duplicateGroups: [DuplicateGroupDTO]
    let cleanCardIDs: [UUID]

    static func declinedResponse(_ message: String) -> UntangleResponse {
        UntangleResponse(declined: true, message: message,
                         fuseGroups: [], duplicateGroups: [], cleanCardIDs: [])
    }
}
