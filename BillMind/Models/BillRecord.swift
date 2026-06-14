import Foundation
import SwiftData

@Model
final class BillRecord {
    var id: UUID
    var journal: Journal?
    var date: Date
    /// Money stored exactly as Decimal (no Double round-trip — currency precision).
    var amount: Decimal = 0
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

    // MARK: - Sync metadata
    //
    // The server is the source of truth; this row is a cache entry. `serverID`
    // links to the server's Bill; `rowVersion`/`updatedAt` drive last-write-wins;
    // `isDeleted` is a tombstone pending push; `syncState` marks local edits that
    // still need pushing. All default so existing inits/call sites are unchanged.
    var serverID: UUID? = nil
    var rowVersion: Int = 0
    var updatedAt: Date? = nil
    var isDeleted: Bool = false
    var syncStateRaw: String = SyncState.local.rawValue

    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .local }
        set { syncStateRaw = newValue.rawValue }
    }

    // MARK: - Computed Properties

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
        self.amount = amount
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
