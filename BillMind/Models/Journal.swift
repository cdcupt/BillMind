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

    @Relationship(deleteRule: .cascade, inverse: \BillRecord.journal)
    var bills: [BillRecord] = []

    var coverAnimal: AnimalType {
        get { AnimalType(rawValue: coverAnimalRaw) ?? .cat }
        set { coverAnimalRaw = newValue.rawValue }
    }

    var totalAmount: Decimal {
        bills.reduce(Decimal.zero) { $0 + $1.amount }
    }

    var billCount: Int { bills.count }

    var sortedBills: [BillRecord] {
        bills.sorted { $0.date > $1.date }
    }

    var billsByDate: [(date: Date, bills: [BillRecord])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: bills) { bill in
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
