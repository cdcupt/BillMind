import Foundation

public struct AIRecognitionResult: Codable, Sendable {
    public let merchant: String?
    public let date: String?
    public let totalAmount: Double?
    public let currency: String?
    public let category: String?
    public let lineItems: [RecognizedLineItem]?
    public let notes: String?

    public struct RecognizedLineItem: Codable, Sendable {
        public let description: String
        public let quantity: Int?
        public let unitPrice: Double?
        public let amount: Double

        public init(description: String, quantity: Int? = nil, unitPrice: Double? = nil, amount: Double) {
            self.description = description
            self.quantity = quantity
            self.unitPrice = unitPrice
            self.amount = amount
        }
    }

    public init(merchant: String? = nil, date: String? = nil, totalAmount: Double? = nil,
                currency: String? = nil, category: String? = nil,
                lineItems: [RecognizedLineItem]? = nil, notes: String? = nil) {
        self.merchant = merchant
        self.date = date
        self.totalAmount = totalAmount
        self.currency = currency
        self.category = category
        self.lineItems = lineItems
        self.notes = notes
    }

    public var parsedDate: Date? {
        guard let dateString = date else { return nil }
        let formatters: [DateFormatter] = {
            // Year-first formats only. Slash dates like "05/08/2026" are
            // deliberately NOT parsed here: MM/dd-vs-dd/MM is a locale guess, and
            // trying MM/dd first silently read UK dates as US ones. An unparsed
            // date lands in rawDateText and raises the date clarify instead.
            let formats = [
                "yyyy-MM-dd",
                "yyyy/MM/dd",
                "yyyy-MM-dd'T'HH:mm:ss",
            ]
            return formats.map { fmt in
                let df = DateFormatter()
                df.dateFormat = fmt
                df.locale = Locale(identifier: "en_US_POSIX")
                return df
            }
        }()
        for formatter in formatters {
            if let d = formatter.date(from: dateString) { return d }
        }
        return nil
    }

    public var parsedCategory: BillCategory? {
        guard let cat = category?.lowercased() else { return nil }
        return BillCategory(rawValue: cat)
    }

    public var parsedAmount: Decimal? {
        guard let amount = totalAmount else { return nil }
        return Decimal(amount)
    }

    // NOTE: the app-side `toBillLineItems() -> [BillLineItem]` convenience is
    // intentionally NOT ported — `BillLineItem` is a SwiftData app model. The
    // agent core maps recognition into `DraftLineItem` via `AIRecognitionMapper`.
}
