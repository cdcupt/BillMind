import Foundation
import SwiftData

@Model
final class Journal {
    var id: UUID
    var name: String
    var createdDate: Date
    var coverAnimalRaw: String
    var currency: String
    var notes: String?

    // MARK: - Sync metadata (maps to the server Trip; see BillRecord for semantics)
    var serverID: UUID? = nil
    var rowVersion: Int = 0
    var updatedAt: Date? = nil
    var isDeleted: Bool = false
    var syncStateRaw: String = SyncState.local.rawValue

    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .local }
        set { syncStateRaw = newValue.rawValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \BillRecord.journal)
    var bills: [BillRecord] = []

    var coverAnimal: AnimalType {
        get { AnimalType(rawValue: coverAnimalRaw) ?? .cat }
        set { coverAnimalRaw = newValue.rawValue }
    }

    /// Bills not pending a delete — the set shown in the UI and counted. A bill
    /// marked `isDeleted` is a tombstone awaiting sync; it must not appear or count.
    var liveBills: [BillRecord] {
        bills.filter { !$0.isDeleted }
    }

    var totalAmount: Decimal {
        liveBills.reduce(Decimal.zero) { $0 + $1.amount }
    }

    var billCount: Int { liveBills.count }

    var sortedBills: [BillRecord] {
        liveBills.sorted { $0.date > $1.date }
    }

    var billsByDate: [(date: Date, bills: [BillRecord])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: liveBills) { bill in
            calendar.startOfDay(for: bill.date)
        }
        return grouped.sorted { $0.key > $1.key }.map { (date: $0.key, bills: $0.value.sorted { $0.date > $1.date }) }
    }

    init(
        name: String,
        currency: String = "CNY",
        coverAnimal: AnimalType = .cat,
        notes: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.createdDate = Date()
        self.coverAnimalRaw = coverAnimal.rawValue
        self.currency = currency
        self.notes = notes
    }
}
