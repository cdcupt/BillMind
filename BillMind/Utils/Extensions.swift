import SwiftUI

// MARK: - Color Hex Init

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Date Helpers

extension Date {
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    func formatted(as format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: self)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }

    var relativeLabel: String {
        if isToday { return "Today" }
        if isYesterday { return "Yesterday" }
        return formatted(as: "MMM d")
    }
}

// MARK: - Decimal Formatting

extension Decimal {
    var formatted2: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: self as NSDecimalNumber) ?? "0"
    }

    var formattedCurrency: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        return formatter.string(from: self as NSDecimalNumber) ?? "0.00"
    }
}

// MARK: - Array Safe Subscript

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Money Display

extension CurrencyInfo {
    /// The display symbol for an ISO code; the code itself when we carry no
    /// symbol for it (never blank — money must always say what it is).
    static func symbol(for code: String) -> String {
        popular.first(where: { $0.code == code })?.symbol ?? code
    }
}

extension BillRecord {
    /// The currency this bill was recorded in. Every recorded bill carries its
    /// draft currency in `originalCurrency`; a kept-foreign bill (the "Keep GBP"
    /// clarify) therefore renders under its OWN symbol, not the journal's.
    var displayCurrency: String { originalCurrency ?? journal?.currency ?? "" }

    var displayCurrencySymbol: String { CurrencyInfo.symbol(for: displayCurrency) }
}

extension Array where Element == BillRecord {
    /// Per-currency totals, largest first — `"¥3,200.00 + £45.50"`. Amounts in
    /// different currencies are NEVER added together; a single-currency set
    /// collapses to the familiar one-symbol total.
    var perCurrencyTotals: String {
        guard !isEmpty else { return "0" }
        var totals: [String: Decimal] = [:]
        for bill in self { totals[bill.displayCurrency, default: 0] += bill.amount }
        return totals.sorted { $0.value > $1.value }
            .map { CurrencyInfo.symbol(for: $0.key) + $0.value.formattedCurrency }
            .joined(separator: " + ")
    }
}

// MARK: - Wire Money (decimal string)

/// Money crosses the wire as a decimal STRING (never a JSON number — float64 is
/// unsafe for currency). These wrappers mirror the server's WireMoney: Swift
/// code sees plain `Decimal`, the JSON carries a string. See contract/openapi.yaml.
@propertyWrapper
struct DecimalString: Codable, Sendable, Equatable {
    var wrappedValue: Decimal
    init(wrappedValue: Decimal) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = Decimal(string: raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "invalid decimal string: \(raw)"))
        }
        wrappedValue = value
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(NSDecimalNumber(decimal: wrappedValue).stringValue)
    }
}

/// Optional money: a decimal string or JSON `null`.
@propertyWrapper
struct OptionalDecimalString: Codable, Sendable, Equatable {
    var wrappedValue: Decimal?
    init(wrappedValue: Decimal?) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { wrappedValue = nil; return }
        let raw = try c.decode(String.self)
        guard let value = Decimal(string: raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "invalid decimal string: \(raw)"))
        }
        wrappedValue = value
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let v = wrappedValue { try c.encode(NSDecimalNumber(decimal: v).stringValue) } else { try c.encodeNil() }
    }
}

// MARK: - Sync Cursor

/// Persists the delta-sync cursor (epoch seconds from the server's SyncDelta).
/// Absent/0 means "full pull". Device-local; cleared on sign-out / cache reset.
enum SyncCursor {
    private static let key = "billmind.sync.cursor"

    static var value: Double {
        get { UserDefaults.standard.double(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func reset() { UserDefaults.standard.removeObject(forKey: key) }
}

// MARK: - API JSON Coders

/// The coders used for all BillMind API traffic: ISO-8601 dates (matching the
/// server's default), money via the wrappers above. One place so the client
/// can never drift from the wire format.
enum APICoders {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
