import SwiftUI
import SwiftData

struct StatsDashboardView: View {
    let journals: [Journal]

    private var totalBills: Int {
        journals.reduce(0) { $0 + $1.billCount }
    }

    private var totalAmount: Decimal {
        journals.reduce(Decimal.zero) { $0 + $1.totalAmount }
    }

    private var currencyCount: Int {
        Set(journals.map(\.currency)).count
    }

    private var categoryBreakdown: [(category: BillCategory, total: Decimal)] {
        var totals: [BillCategory: Decimal] = [:]
        for journal in journals {
            for bill in journal.bills {
                totals[bill.category, default: 0] += bill.amount
            }
        }
        return totals.sorted { $0.value > $1.value }
            .map { (category: $0.key, total: $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("This Month")
                    .font(SketchTheme.captionFont())
                    .foregroundStyle(SketchTheme.lightBrown)
                Spacer()
                AnimalMascotView(animal: .bear, size: 22)
            }

            Text(totalAmount.formattedCurrency)
                .font(SketchTheme.amountFont(38))
                .foregroundStyle(SketchTheme.softBrown)

            HStack(spacing: 12) {
                StatChip(label: "Journals", value: "\(journals.count)")
                StatChip(label: "Bills", value: "\(totalBills)")
                StatChip(label: "Currencies", value: "\(currencyCount)")
            }

            if !categoryBreakdown.isEmpty {
                MiniBarChart(data: categoryBreakdown)
            }
        }
        .sketchCard()
    }
}

private struct StatChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(SketchTheme.captionFont(12))
                .foregroundStyle(SketchTheme.lightBrown)
            Text(value)
                .font(SketchTheme.headlineFont(18))
                .foregroundStyle(SketchTheme.softBrown)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(SketchTheme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(SketchTheme.lightBrown.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct MiniBarChart: View {
    let data: [(category: BillCategory, total: Decimal)]

    private var maxValue: Decimal {
        data.map(\.total).max() ?? 1
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(data.prefix(6), id: \.category) { item in
                    let height = maxValue > 0
                        ? CGFloat(NSDecimalNumber(decimal: item.total / maxValue).doubleValue) * 50
                        : 6
                    RoundedRectangle(cornerRadius: 4)
                        .fill(item.category.color.opacity(0.8))
                        .frame(height: max(6, height))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 50)

            HStack(spacing: 6) {
                ForEach(data.prefix(6), id: \.category) { item in
                    Text(item.category.englishName)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(SketchTheme.lightBrown)
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                }
            }
        }
        .padding(.top, 8)
    }
}
