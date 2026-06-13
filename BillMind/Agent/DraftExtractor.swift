import Foundation

/// Turns a typed phrase like `"ramen 2840"` into a `BillDraft` — locally, with no
/// network and no AI. This is the Record tab's text-capture path: deterministic,
/// API-key-free, and the basis of the E2E.
///
/// Foundation-only by design. Emits `BillCategory` **raw values** (not display
/// names) so `BillValidator` recognizes them; date is left `nil` so the agent asks
/// for it (Today / Yesterday / pick a date).
enum DraftExtractor {

    /// Keyword → `BillCategory.rawValue`. First match wins; unmatched → `misc`.
    private static let categoryKeywords: [(words: Set<String>, raw: String)] = [
        (["taxi", "train", "bus", "metro", "subway", "uber", "fare", "flight", "ferry"], "transport"),
        (["hotel", "inn", "hostel", "airbnb", "ryokan", "lodging", "motel"], "accommodation"),
        (["ramen", "sushi", "dinner", "lunch", "breakfast", "coffee", "cafe", "café",
          "food", "restaurant", "drink", "drinks", "beer", "meal", "snack", "izakaya"], "food"),
        (["shop", "store", "mall", "clothes", "uniqlo", "muji", "souvenir", "konbini", "market"], "shopping"),
        (["movie", "cinema", "game", "bar", "club", "ktv", "museum", "ticket", "show"], "entertainment"),
        (["pharmacy", "clinic", "hospital", "doctor", "medicine", "dental"], "medical"),
        (["sim", "data", "wifi", "electric", "water", "gas", "utility"], "utilities"),
        (["course", "class", "lesson", "book", "tuition"], "education"),
        (["subscription", "netflix", "spotify", "icloud", "membership"], "subscription"),
    ]

    /// Filler tokens stripped before deriving a merchant name.
    private static let fillerWords: Set<String> = [
        "cash", "card", "paid", "for", "the", "a", "an", "at", "in", "on", "with", "by",
        "yen", "jpy", "usd", "eur", "dollars", "euros", "yuan", "rmb", "cny",
    ]

    static func parse(_ raw: String, currencyCode: String) -> BillDraft {
        BillDraft(
            merchant: merchant(in: raw),
            amount: firstAmount(in: raw),
            currencyCode: currencyCode,
            date: nil,
            categoryRaw: category(in: raw),
            source: .text
        )
    }

    /// First numeric run (supports thousands separators and decimals). `nil` when
    /// no number is present — the agent then blocks confirmation until an amount is
    /// entered, never guessing one.
    static func firstAmount(in raw: String) -> Decimal? {
        let pattern = "[0-9][0-9,]*(?:\\.[0-9]+)?"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let range = Range(match.range, in: raw) else { return nil }
        let cleaned = raw[range].replacingOccurrences(of: ",", with: "")
        return Decimal(string: cleaned)
    }

    /// Keyword-matched category raw value, defaulting to `misc` (a valid category
    /// the user can change via the picker — not flagged as unknown).
    static func category(in raw: String) -> String {
        let tokens = Set(raw.lowercased().split { !$0.isLetter }.map(String.init))
        for entry in categoryKeywords where !entry.words.isDisjoint(with: tokens) {
            return entry.raw
        }
        return "misc"
    }

    /// Leftover words after removing the amount and filler, title-cased; `nil` when
    /// nothing meaningful remains.
    static func merchant(in raw: String) -> String? {
        var text = raw
        if let amount = try? NSRegularExpression(pattern: "[0-9][0-9,]*(?:\\.[0-9]+)?") {
            let full = NSRange(text.startIndex..., in: text)
            text = amount.stringByReplacingMatches(in: text, range: full, withTemplate: " ")
        }
        let words = text.split { !$0.isLetter }.map(String.init)
            .filter { !fillerWords.contains($0.lowercased()) }
        guard !words.isEmpty else { return nil }
        return words.prefix(4)
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}
