import Foundation

/// A bill being assembled by the recording agent.
///
/// A `BillDraft` lives only in memory (inside `RecordingSession`) until the user
/// confirms it; only at confirmation does the host persist a `BillRecord`. This is
/// the agent equivalent of an open issue: it carries everything extracted so far
/// plus the user's decisions about it.
///
/// Foundation-only by design — no SwiftData, SwiftUI, or UIKit — so the recording
/// agent's logic compiles and unit-tests without the iOS SDK and stays decoupled
/// from persistence and presentation.
public struct BillDraft: Identifiable, Sendable, Equatable {
    public let id: UUID

    public var merchant: String?
    /// The total. `nil` means "unknown" — the agent never guesses an amount; a
    /// missing amount becomes a clarifying question or blocks confirmation.
    public var amount: Decimal?
    public var currencyCode: String
    public var date: Date?
    /// A date string the extractor read but could not parse (smudged/ambiguous).
    public var rawDateText: String?
    /// The category as returned by extraction, lowercased when compared. May be a
    /// value outside the known set, which the validator flags.
    public var categoryRaw: String?
    public var lineItems: [DraftLineItem]
    public var source: DraftSource

    /// Fields the user has explicitly decided. Validation must not re-question a
    /// pinned field, which is what makes the clarify→re-validate loop terminate.
    public var pinnedFields: Set<BillField>
    /// Gaps the user chose to leave unresolved (via "skip"/budget exhaustion).
    /// These require an explicit acknowledgment before the draft can be recorded.
    public var acknowledgedGaps: Set<BillField>

    public init(
        id: UUID = UUID(),
        merchant: String? = nil,
        amount: Decimal? = nil,
        currencyCode: String,
        date: Date? = nil,
        rawDateText: String? = nil,
        categoryRaw: String? = nil,
        lineItems: [DraftLineItem] = [],
        source: DraftSource,
        pinnedFields: Set<BillField> = [],
        acknowledgedGaps: Set<BillField> = []
    ) {
        self.id = id
        self.merchant = merchant
        self.amount = amount
        self.currencyCode = currencyCode
        self.date = date
        self.rawDateText = rawDateText
        self.categoryRaw = categoryRaw
        self.lineItems = lineItems
        self.source = source
        self.pinnedFields = pinnedFields
        self.acknowledgedGaps = acknowledgedGaps
    }

    /// Sum of line-item amounts, or `nil` when there are no line items to reconcile.
    public var lineItemTotal: Decimal? {
        guard !lineItems.isEmpty else { return nil }
        return lineItems.reduce(Decimal.zero) { $0 + $1.amount }
    }
}

/// A single line on a receipt. Value type so drafts stay `Sendable` and copyable.
public struct DraftLineItem: Sendable, Equatable {
    public var label: String
    public var amount: Decimal

    public init(label: String, amount: Decimal) {
        self.label = label
        self.amount = amount
    }
}

/// How a draft entered the pipeline. Drives provenance on the recorded bill.
public enum DraftSource: String, Sendable, Equatable, CaseIterable {
    case photo
    case voice
    case text
    case manual
}

/// The editable fields a clarification can target. Simple enum so it is `Hashable`
/// (usable in `Set`) and `Sendable` automatically.
public enum BillField: String, Sendable, Equatable, CaseIterable {
    case amount
    case date
    case category
    case currency
    case merchant
}
