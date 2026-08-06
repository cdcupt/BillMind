import Foundation

/// Turns a typed phrase like `"ramen 2840"` or `"taxi 202 june 10th 2026"` into a
/// `BillDraft` — locally, with no network and no AI. This is the Record tab's
/// text-capture path: deterministic, API-key-free, and the basis of the E2E.
///
/// Foundation-only by design. Emits `BillCategory` **raw values** (not display
/// names) so `BillValidator` recognizes them. An explicit calendar date the user
/// types (month-name or ISO) is parsed and stripped from the merchant; when no
/// explicit date is present, `date` is left `nil` so the Today / Yesterday clarify
/// (which knows the real local day) resolves it.
enum DraftExtractor {

    /// Keyword → `BillCategory.rawValue`. First match wins; unmatched → `misc`.
    private static let categoryKeywords: [(words: Set<String>, raw: String)] = [
        (["taxi", "train", "bus", "metro", "subway", "uber", "fare", "flight", "ferry",
          "tube", "underground", "rail", "railway", "cab", "coach", "tram"], "transport"),
        (["hotel", "inn", "hostel", "airbnb", "ryokan", "lodging", "motel"], "accommodation"),
        (["ramen", "sushi", "dinner", "lunch", "breakfast", "coffee", "cafe", "café",
          "food", "restaurant", "drink", "drinks", "beer", "meal", "snack", "izakaya",
          "pub", "pint", "pints", "chips", "takeaway", "tea", "pret", "greggs",
          "sandwich", "bakery"], "food"),
        (["shop", "store", "mall", "clothes", "uniqlo", "muji", "souvenir", "konbini", "market",
          "tesco", "sainsbury", "sainsburys", "boots", "primark", "asda", "waitrose",
          "aldi", "lidl"], "shopping"),
        (["movie", "cinema", "game", "bar", "club", "ktv", "museum", "ticket", "show",
          "theatre", "gallery"], "entertainment"),
        (["pharmacy", "clinic", "hospital", "doctor", "medicine", "dental"], "medical"),
        (["sim", "data", "wifi", "electric", "water", "gas", "utility"], "utilities"),
        (["course", "class", "lesson", "book", "tuition"], "education"),
        (["subscription", "netflix", "spotify", "icloud", "membership"], "subscription"),
    ]

    /// Filler tokens stripped before deriving a merchant name. Includes ordinal
    /// suffixes, relative-day words, and currency words so they never become a
    /// merchant.
    private static let fillerWords: Set<String> = [
        "cash", "card", "paid", "for", "the", "a", "an", "at", "in", "on", "with", "by",
        "to", "from",
        "yen", "jpy", "usd", "eur", "dollar", "dollars", "euro", "euros", "yuan", "rmb", "cny",
        "gbp", "pound", "pounds", "quid", "pence", "buck", "bucks",
        "st", "nd", "rd", "th", "today", "yesterday", "tomorrow", "tonight",
    ]

    /// Currency symbols the extractor reads as an explicit signal. `¥` is
    /// intentionally absent — it is ambiguous (JPY vs CNY), and the agent never
    /// guesses money, currency included.
    private static let currencySymbols: [(symbol: Character, code: String)] = [
        ("£", "GBP"), ("€", "EUR"), ("$", "USD"),
    ]

    /// Currency words (lowercased token → ISO 4217 code).
    private static let currencyWords: [String: String] = [
        "gbp": "GBP", "pound": "GBP", "pounds": "GBP", "quid": "GBP", "pence": "GBP",
        "usd": "USD", "dollar": "USD", "dollars": "USD", "buck": "USD", "bucks": "USD",
        "eur": "EUR", "euro": "EUR", "euros": "EUR",
        "jpy": "JPY", "yen": "JPY",
        "cny": "CNY", "yuan": "CNY", "rmb": "CNY",
    ]

    static func parse(_ raw: String, currencyCode: String, reference: Date = Date()) -> BillDraft {
        BillDraft(
            merchant: merchant(in: raw, reference: reference),
            amount: amount(in: raw, reference: reference),
            currencyCode: currency(in: raw) ?? currencyCode,
            date: date(in: raw, reference: reference),
            categoryRaw: category(in: raw),
            source: .text
        )
    }

    /// An explicit currency stated in the phrase — a symbol (`£4.50`) or a word
    /// (`"4.50 pounds"`, `"32 quid"`). `nil` when the phrase states none; the
    /// caller then falls back to the journal currency. A stated currency that
    /// differs from the journal's raises the currency clarify downstream, so a
    /// GBP receipt never silently files under the journal's currency.
    static func currency(in raw: String) -> String? {
        for entry in currencySymbols where raw.contains(entry.symbol) { return entry.code }
        for token in raw.lowercased().split(whereSeparator: { !$0.isLetter }) {
            if let code = currencyWords[String(token)] { return code }
        }
        return nil
    }

    /// First numeric run (supports thousands separators and decimals). `nil` when
    /// no number is present. Kept as the cheap "does this text look like an
    /// expense?" signal; `amount(in:reference:)` is the smarter pick `parse` uses.
    static func firstAmount(in raw: String) -> Decimal? {
        let pattern = "[0-9][0-9,]*(?:\\.[0-9]+)?"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let range = Range(match.range, in: raw) else { return nil }
        let cleaned = raw[range].replacingOccurrences(of: ",", with: "")
        return Decimal(string: cleaned)
    }

    /// The amount stated in the phrase — never a date fragment or a bare count
    /// when a better candidate exists. Candidate numeric runs exclude anything
    /// inside an explicit date span (`"5th August"`), ordinal day numbers
    /// (`"5th"`), and slash-date fragments (`"05/08/2026"`). Among candidates, a
    /// run adjacent to a currency symbol wins (`"£45"`), then a decimal-bearing
    /// run (`"2 pints 11.20"` → 11.20), then the first remaining run. `nil` when
    /// no candidate survives — the agent then blocks confirmation until an amount
    /// is entered, never guessing one.
    static func amount(in raw: String, reference: Date = Date()) -> Decimal? {
        var text = raw
        // Strip an explicit date span FIRST so its day/year numbers are never
        // amount candidates (this is what filed "5th August lunch 12" as 5).
        if let match = dateMatch(in: text, reference: reference) {
            text.replaceSubrange(match.range, with: " ")
        }
        guard let regex = try? NSRegularExpression(pattern: "[0-9][0-9,]*(?:\\.[0-9]+)?") else { return nil }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))

        struct Candidate { let value: Decimal; let hasDecimal: Bool; let currencyAdjacent: Bool }
        var candidates: [Candidate] = []
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let run = String(text[range])
            // An ordinal suffix marks a day number ("5th"), not money.
            if ["st", "nd", "rd", "th"].contains(text[range.upperBound...].prefix(2).lowercased()) { continue }
            // A neighbouring slash marks a date fragment ("05/08/2026"), not money.
            let slashBefore = range.lowerBound > text.startIndex
                && text[text.index(before: range.lowerBound)] == "/"
            let slashAfter = range.upperBound < text.endIndex && text[range.upperBound] == "/"
            if slashBefore || slashAfter { continue }
            guard let value = Decimal(string: run.replacingOccurrences(of: ",", with: "")) else { continue }
            // A currency marker beside the run marks the stated total: a symbol
            // before ("£45"), or a symbol / currency word right after ("45£",
            // "45 pounds", "11 quid"). Spaces are allowed on either side.
            var adjacent = false
            var i = range.lowerBound
            while i > text.startIndex {
                i = text.index(before: i)
                if text[i] == " " { continue }
                adjacent = currencySymbols.contains { $0.symbol == text[i] }
                break
            }
            if !adjacent {
                var j = range.upperBound
                while j < text.endIndex, text[j] == " " { j = text.index(after: j) }
                if j < text.endIndex, currencySymbols.contains(where: { $0.symbol == text[j] }) {
                    adjacent = true
                } else if j < text.endIndex {
                    let word = text[j...].prefix(while: { $0.isLetter }).lowercased()
                    adjacent = currencyWords[word] != nil
                }
            }
            candidates.append(Candidate(value: value, hasDecimal: run.contains("."), currencyAdjacent: adjacent))
        }
        if let pick = candidates.first(where: { $0.currencyAdjacent }) { return pick.value }
        if let pick = candidates.first(where: { $0.hasDecimal }) { return pick.value }
        return candidates.first?.value
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

    /// An explicit calendar date typed in the phrase — `"June 10th 2026"`,
    /// `"10 Jun 2026"`, `"Jun 10"` (year → `reference`'s year), or ISO `2026-06-10`.
    /// Relative words (today/yesterday) are intentionally *not* resolved here; the
    /// clarify handles those with the real local day.
    static func date(in raw: String, reference: Date = Date()) -> Date? {
        dateMatch(in: raw, reference: reference)?.date
    }

    /// Leftover words after removing an explicit date span, the amount, and filler,
    /// title-cased; `nil` when nothing meaningful remains.
    static func merchant(in raw: String, reference: Date = Date()) -> String? {
        var text = raw
        // Remove an explicit date span FIRST so its month/ordinal/year words don't
        // survive into the name (this is what produced "Taxi June Th").
        if let match = dateMatch(in: text, reference: reference) {
            text.replaceSubrange(match.range, with: " ")
        }
        // Then strip numeric runs (amounts).
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

    // MARK: - Date parsing internals

    private struct DateSpan { let date: Date; let range: Range<String.Index> }

    /// Month name (full + 3-letter abbrev, plus "sept") → month number.
    private static let monthByName: [String: Int] = {
        let full = ["january", "february", "march", "april", "may", "june",
                    "july", "august", "september", "october", "november", "december"]
        var map: [String: Int] = [:]
        for (i, name) in full.enumerated() {
            map[name] = i + 1
            map[String(name.prefix(3))] = i + 1
        }
        map["sept"] = 9
        return map
    }()

    /// Month names as a regex alternation, longest-first so "june" wins over "jun".
    private static let monthAlternation: String =
        monthByName.keys.sorted { $0.count > $1.count }.joined(separator: "|")

    /// A UTC, noon-anchored Gregorian calendar. Noon avoids any time-zone midnight
    /// rollover when the date is later formatted for display.
    private static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        return cal
    }()

    private static func dateMatch(in raw: String, reference: Date) -> DateSpan? {
        let refYear = calendar.component(.year, from: reference)

        // ISO 2026-04-06
        if let m = firstMatch(in: raw, "\\b(\\d{4})-(\\d{1,2})-(\\d{1,2})\\b"),
           let y = m.int(1), let mo = m.int(2), let d = m.int(3),
           let date = makeDate(year: y, month: mo, day: d) {
            return DateSpan(date: date, range: m.range)
        }
        // Month name + day [+ year] — "June 10th 2026", "Jun 10".
        let monthFirst = "\\b(\(monthAlternation))\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s+(\\d{4}))?\\b"
        if let m = firstMatch(in: raw, monthFirst, [.caseInsensitive]),
           let mo = m.string(1).flatMap({ monthByName[$0.lowercased()] }), let d = m.int(2),
           let date = makeDate(year: m.int(3) ?? refYear, month: mo, day: d) {
            return DateSpan(date: date, range: m.range)
        }
        // Day + month name [+ year] — "10 June 2026", "10th Jun".
        let dayFirst = "\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(\(monthAlternation))\\.?(?:,?\\s+(\\d{4}))?\\b"
        if let m = firstMatch(in: raw, dayFirst, [.caseInsensitive]),
           let d = m.int(1), let mo = m.string(2).flatMap({ monthByName[$0.lowercased()] }),
           let date = makeDate(year: m.int(3) ?? refYear, month: mo, day: d) {
            return DateSpan(date: date, range: m.range)
        }
        return nil
    }

    /// Builds a noon-UTC date, rejecting out-of-range or rolled-over values
    /// (e.g. "February 30").
    private static func makeDate(year: Int, month: Int, day: Int) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let comps = DateComponents(year: year, month: month, day: day, hour: 12)
        guard let date = calendar.date(from: comps),
              calendar.component(.day, from: date) == day,
              calendar.component(.month, from: date) == month else { return nil }
        return date
    }

    // MARK: - Small regex helper

    private struct Match {
        let result: NSTextCheckingResult
        let base: String
        var range: Range<String.Index> { Range(result.range, in: base)! }
        func string(_ i: Int) -> String? {
            guard i < result.numberOfRanges, let r = Range(result.range(at: i), in: base) else { return nil }
            return String(base[r])
        }
        func int(_ i: Int) -> Int? { string(i).flatMap { Int($0) } }
    }

    private static func firstMatch(in s: String, _ pattern: String,
                                   _ options: NSRegularExpression.Options = []) -> Match? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return Match(result: m, base: s)
    }
}
