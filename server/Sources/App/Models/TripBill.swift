import Fluent
import Foundation

/// A trip (formerly "journal"). Owned by one user in v1; `row_version` +
/// soft-delete tombstone drive last-write-wins sync.
final class Trip: Model, @unchecked Sendable {
    static let schema = "trips"

    @ID(key: .id) var id: UUID?
    @Parent(key: "owner_user_id") var owner: User
    @Field(key: "name") var name: String
    @Field(key: "currency_code") var currencyCode: String
    @Field(key: "exchange_rate") var exchangeRate: Decimal
    @OptionalField(key: "mascot") var mascot: String?
    @Field(key: "row_version") var rowVersion: Int
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?
    @Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?

    init() {}
    init(id: UUID? = nil, ownerID: User.IDValue, name: String, currencyCode: String,
         exchangeRate: Decimal = 1, mascot: String? = nil, rowVersion: Int = 1) {
        self.id = id
        self.$owner.id = ownerID
        self.name = name
        self.currencyCode = currencyCode
        self.exchangeRate = exchangeRate
        self.mascot = mascot
        self.rowVersion = rowVersion
    }
}

/// A single bill. Money is `Decimal` (NUMERIC at rest — never float). The bill
/// is the conflict unit for sync (per-bill LWW).
final class Bill: Model, @unchecked Sendable {
    static let schema = "bills"

    @ID(key: .id) var id: UUID?
    @Parent(key: "trip_id") var trip: Trip
    @OptionalField(key: "merchant") var merchant: String?
    @Field(key: "amount") var amount: Decimal
    @Field(key: "currency_code") var currencyCode: String
    @Field(key: "date") var date: Date
    @OptionalField(key: "category_raw") var categoryRaw: String?
    @Field(key: "source") var source: String              // photo | voice | text | manual
    @OptionalField(key: "notes") var notes: String?
    @Parent(key: "created_by_user_id") var createdBy: User
    @Field(key: "row_version") var rowVersion: Int
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?
    @Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?

    init() {}
    init(id: UUID? = nil, tripID: Trip.IDValue, merchant: String?, amount: Decimal,
         currencyCode: String, date: Date, categoryRaw: String?, source: String,
         notes: String? = nil, createdByID: User.IDValue, rowVersion: Int = 1) {
        self.id = id
        self.$trip.id = tripID
        self.merchant = merchant
        self.amount = amount
        self.currencyCode = currencyCode
        self.date = date
        self.categoryRaw = categoryRaw
        self.source = source
        self.notes = notes
        self.$createdBy.id = createdByID
        self.rowVersion = rowVersion
    }
}

/// A line item within a bill.
final class LineItem: Model, @unchecked Sendable {
    static let schema = "line_items"

    @ID(key: .id) var id: UUID?
    @Parent(key: "bill_id") var bill: Bill
    @Field(key: "label") var label: String
    @Field(key: "amount") var amount: Decimal
    @OptionalField(key: "quantity") var quantity: Int?
    @OptionalField(key: "unit_price") var unitPrice: Decimal?
    @Field(key: "sort_index") var sortIndex: Int

    init() {}
    init(id: UUID? = nil, billID: Bill.IDValue, label: String, amount: Decimal,
         quantity: Int? = nil, unitPrice: Decimal? = nil, sortIndex: Int = 0) {
        self.id = id
        self.$bill.id = billID
        self.label = label
        self.amount = amount
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.sortIndex = sortIndex
    }
}

/// A receipt image: only metadata + the blob-store pointer live in Postgres;
/// the encrypted bytes live in the blob store at `object_key`.
final class BillImage: Model, @unchecked Sendable {
    static let schema = "bill_images"

    @ID(key: .id) var id: UUID?
    @Parent(key: "bill_id") var bill: Bill
    @Field(key: "object_key") var objectKey: String
    @Field(key: "mime") var mime: String
    @Field(key: "byte_size") var byteSize: Int
    @Field(key: "sha256") var sha256: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}
    init(id: UUID? = nil, billID: Bill.IDValue, objectKey: String, mime: String,
         byteSize: Int, sha256: String) {
        self.id = id
        self.$bill.id = billID
        self.objectKey = objectKey
        self.mime = mime
        self.byteSize = byteSize
        self.sha256 = sha256
    }
}
