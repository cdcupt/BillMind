import Foundation
import SwiftData

@Model
final class BillRecord {
    var id: UUID
    var journal: Journal?
    var date: Date
    var amountDouble: Double
    var originalCurrency: String?
    var categoryRaw: String
    var merchant: String?
    var note: String?
    var imagePathsData: Data?
    var lineItemsData: Data?
    var aiProviderRaw: String?
    var aiRawResponse: String?
    var recognitionConfidence: Double?
    var statusRaw: String
    var createdDate: Date

    // MARK: - Computed Properties

    var amount: Decimal {
        get { Decimal(amountDouble) }
        set { amountDouble = NSDecimalNumber(decimal: newValue).doubleValue }
    }

    var category: BillCategory {
        get { BillCategory(rawValue: categoryRaw) ?? .misc }
        set { categoryRaw = newValue.rawValue }
    }

    var status: BillStatus {
        get { BillStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var aiProvider: AIProvider? {
        get { aiProviderRaw.flatMap { AIProvider(rawValue: $0) } }
        set { aiProviderRaw = newValue?.rawValue }
    }

    var imagePaths: [String] {
        get {
            guard let data = imagePathsData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            imagePathsData = try? JSONEncoder().encode(newValue)
        }
    }

    var lineItems: [BillLineItem] {
        get {
            guard let data = lineItemsData else { return [] }
            return (try? JSONDecoder().decode([BillLineItem].self, from: data)) ?? []
        }
        set {
            lineItemsData = try? JSONEncoder().encode(newValue)
        }
    }

    init(
        date: Date = Date(),
        amount: Decimal = 0,
        originalCurrency: String? = nil,
        category: BillCategory = .misc,
        merchant: String? = nil,
        note: String? = nil,
        status: BillStatus = .draft
    ) {
        self.id = UUID()
        self.date = date
        self.amountDouble = NSDecimalNumber(decimal: amount).doubleValue
        self.originalCurrency = originalCurrency
        self.categoryRaw = category.rawValue
        self.merchant = merchant
        self.note = note
        self.statusRaw = status.rawValue
        self.createdDate = Date()
    }
}

// MARK: - Bill Line Item

struct BillLineItem: Codable, Identifiable, Hashable {
    let id: UUID
    var itemDescription: String
    var quantity: Int
    var unitPrice: Decimal
    var amount: Decimal

    init(
        itemDescription: String,
        quantity: Int = 1,
        unitPrice: Decimal = 0,
        amount: Decimal = 0
    ) {
        self.id = UUID()
        self.itemDescription = itemDescription
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.amount = amount
    }
}
