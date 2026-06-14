import Foundation

/// Money on the wire is a **decimal string**, never a JSON number — JSON numbers
/// are float64 and unsafe for currency on some clients. These property wrappers
/// keep the Swift side as plain `Decimal` while encoding/decoding as a string,
/// so the contract (contract/openapi.yaml) is honoured with zero churn at call
/// sites: `dto.amount` is still a `Decimal` everywhere in the server.
///
/// Note: the wrappers assume the key is present (responses always emit it;
/// optional money is emitted as JSON `null`). All BillMind clients send the key.
@propertyWrapper
struct DecimalString: Codable, Sendable, Equatable {
    var wrappedValue: Decimal
    init(wrappedValue: Decimal) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = Decimal(string: raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "invalid decimal string: \(raw)"))
        }
        wrappedValue = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(NSDecimalNumber(decimal: wrappedValue).stringValue)
    }
}

/// Optional money: a decimal string or JSON `null`.
@propertyWrapper
struct OptionalDecimalString: Codable, Sendable, Equatable {
    var wrappedValue: Decimal?
    init(wrappedValue: Decimal?) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            wrappedValue = nil
            return
        }
        let raw = try container.decode(String.self)
        guard let value = Decimal(string: raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "invalid decimal string: \(raw)"))
        }
        wrappedValue = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value = wrappedValue {
            try container.encode(NSDecimalNumber(decimal: value).stringValue)
        } else {
            try container.encodeNil()
        }
    }
}
