import Foundation

struct AIRecognitionResult: Codable {
    let merchant: String?
    let date: String?
    let totalAmount: Double?
    let currency: String?
    let category: String?
    let lineItems: [RecognizedLineItem]?
    let notes: String?

    struct RecognizedLineItem: Codable {
        let description: String
        let quantity: Int?
        let unitPrice: Double?
        let amount: Double
    }

    var parsedDate: Date? {
        guard let dateString = date else { return nil }
        let formatters: [DateFormatter] = {
            let formats = [
                "yyyy-MM-dd",
                "yyyy/MM/dd",
                "MM/dd/yyyy",
                "dd/MM/yyyy",
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

    var parsedCategory: BillCategory? {
        guard let cat = category?.lowercased() else { return nil }
        return BillCategory(rawValue: cat)
    }

    var parsedAmount: Decimal? {
        guard let amount = totalAmount else { return nil }
        return Decimal(amount)
    }

    // NOTE: the app-side `toBillLineItems() -> [BillLineItem]` convenience is
    // intentionally NOT ported — `BillLineItem` is a SwiftData app model. The
    // agent core maps recognition into `DraftLineItem` via `AIRecognitionMapper`.
}
