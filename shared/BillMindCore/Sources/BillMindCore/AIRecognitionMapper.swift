import Foundation

/// Maps an `AIRecognitionResult` (from `AIService`, photo path) into a `BillDraft`
/// for the recording agent.
///
/// Foundation-only. Preserves the AI's raw category string (so an unknown category
/// is flagged by the validator), and routes an unparseable date string into
/// `rawDateText` so the "date hard to read" clarify path is exercised.
public enum AIRecognitionMapper {
    public static func draft(from result: AIRecognitionResult, currencyCode: String,
                             source: DraftSource = .photo) -> BillDraft {
        let parsedDate = result.parsedDate
        // Keep the raw date string when it couldn't be parsed, so the agent asks.
        let rawDateText: String? = (parsedDate == nil) ? result.date : nil

        // Map recognized items straight into draft line items — the core never
        // touches the SwiftData `BillLineItem` (that conversion is app-only).
        let lineItems = (result.lineItems ?? []).map {
            DraftLineItem(label: $0.description, amount: Decimal($0.amount))
        }

        return BillDraft(
            merchant: result.merchant,
            amount: result.parsedAmount,                 // nil if AI returned no total — never guessed
            currencyCode: result.currency ?? currencyCode,
            date: parsedDate,
            rawDateText: rawDateText,
            categoryRaw: result.category?.lowercased(),   // raw kept verbatim; validator flags unknowns
            lineItems: lineItems,
            source: source
        )
    }
}
