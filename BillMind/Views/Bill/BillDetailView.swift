import SwiftUI

struct BillDetailView: View {
    let bill: BillRecord
    let currencySymbol: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Text(bill.category.icon)
                        .font(.system(size: 48))
                    Text(bill.merchant ?? bill.category.displayName)
                        .font(SketchTheme.titleFont(24))
                        .foregroundStyle(SketchTheme.softBrown)
                    Text("\(currencySymbol)\(bill.amount.formattedCurrency)")
                        .font(SketchTheme.amountFont(42))
                        .foregroundStyle(bill.category.color)
                    StatusBadge(status: bill.status)
                }
                .frame(maxWidth: .infinity)
                .sketchCard()

                // Details
                VStack(spacing: 12) {
                    DetailRow(label: "Category", value: "\(bill.category.icon) \(bill.category.displayName)")
                    DetailRow(label: "Date", value: bill.date.formatted(as: "yyyy-MM-dd HH:mm"))
                    if let currency = bill.originalCurrency {
                        DetailRow(label: "Currency", value: currency)
                    }
                    if let note = bill.note, !note.isEmpty {
                        DetailRow(label: "Note", value: note)
                    }
                    if let provider = bill.aiProvider {
                        DetailRow(label: "Recognized by", value: provider.displayName)
                    }
                }
                .sketchCard()

                // Line Items
                if !bill.lineItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Line Items")
                            .font(SketchTheme.captionFont())
                            .foregroundStyle(SketchTheme.lightBrown)
                        ForEach(bill.lineItems) { item in
                            HStack {
                                Text(item.itemDescription)
                                    .font(SketchTheme.bodyFont(14))
                                    .foregroundStyle(SketchTheme.softBrown)
                                if item.quantity > 1 {
                                    Text("×\(item.quantity)")
                                        .font(SketchTheme.captionFont(12))
                                        .foregroundStyle(SketchTheme.lightBrown)
                                }
                                Spacer()
                                Text("\(currencySymbol)\(item.amount.formatted2)")
                                    .font(SketchTheme.headlineFont(14))
                                    .foregroundStyle(SketchTheme.softBrown)
                            }
                            .padding(.vertical, 4)
                            if item.id != bill.lineItems.last?.id {
                                Divider()
                            }
                        }
                    }
                    .sketchCard()
                }
            }
            .padding()
        }
        .paperBackground()
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Bill Detail")
                    .font(SketchTheme.headlineFont(20))
                    .foregroundStyle(SketchTheme.softBrown)
            }
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(SketchTheme.captionFont())
                .foregroundStyle(SketchTheme.lightBrown)
            Spacer()
            Text(value)
                .font(SketchTheme.bodyFont(14))
                .foregroundStyle(SketchTheme.softBrown)
        }
    }
}
