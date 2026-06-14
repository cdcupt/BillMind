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
