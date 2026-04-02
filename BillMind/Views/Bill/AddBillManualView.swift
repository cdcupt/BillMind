import SwiftUI
import SwiftData

struct AddBillManualView: View {
    let journal: Journal
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var merchant = ""
    @State private var amountText = ""
    @State private var selectedCategory: BillCategory = .food
    @State private var date = Date()
    @State private var note = ""
    @State private var originalCurrency: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Amount
                    VStack(spacing: 4) {
                        Text("Amount")
                            .font(SketchTheme.captionFont())
                            .foregroundStyle(SketchTheme.lightBrown)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(currencySymbol)
                                .font(SketchTheme.amountFont(28))
                                .foregroundStyle(SketchTheme.lightBrown)
                            TextField("0.00", text: $amountText)
                                .font(SketchTheme.amountFont(42))
                                .foregroundStyle(SketchTheme.softBrown)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.center)
                                .textFieldStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .sketchCard()

                    // Category picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Category")
                            .font(SketchTheme.captionFont())
                            .foregroundStyle(SketchTheme.lightBrown)
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                        ], spacing: 10) {
                            ForEach(BillCategory.allCases) { category in
                                Button {
                                    selectedCategory = category
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(category.icon)
                                            .font(.system(size: 22))
                                        Text(category.displayName)
                                            .font(.system(size: 10, weight: .medium, design: .rounded))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        selectedCategory == category
                                            ? category.color.opacity(0.15)
                                            : SketchTheme.cream
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(
                                                selectedCategory == category
                                                    ? category.color.opacity(0.5)
                                                    : SketchTheme.lightBrown.opacity(0.2),
                                                lineWidth: 1
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(SketchTheme.softBrown)
                            }
                        }
                    }
                    .sketchCard()

                    // Merchant
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Merchant")
                            .font(SketchTheme.captionFont())
                            .foregroundStyle(SketchTheme.lightBrown)
                        TextField("Store or company name", text: $merchant)
                            .font(SketchTheme.bodyFont())
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(SketchTheme.cream)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(SketchTheme.lightBrown.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .sketchCard()

                    // Date
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Date & Time")
                            .font(SketchTheme.captionFont())
                            .foregroundStyle(SketchTheme.lightBrown)
                        DatePicker("", selection: $date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .tint(SketchTheme.dustyRose)
                    }
                    .sketchCard()

                    // Note
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Note (optional)")
                            .font(SketchTheme.captionFont())
                            .foregroundStyle(SketchTheme.lightBrown)
                        TextField("Additional details...", text: $note, axis: .vertical)
                            .font(SketchTheme.bodyFont(14))
                            .textFieldStyle(.plain)
                            .lineLimit(2...4)
                            .padding(12)
                            .background(SketchTheme.cream)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(SketchTheme.lightBrown.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .sketchCard()

                    // Save button
                    Button {
                        saveBill()
                    } label: {
                        HandDrawnButton(title: "Save Bill", icon: "✓", style: .primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isValid)
                    .opacity(isValid ? 1 : 0.5)
                }
                .padding()
            }
            .paperBackground()
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Add Bill")
                        .font(SketchTheme.headlineFont(20))
                        .foregroundStyle(SketchTheme.softBrown)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(SketchTheme.dustyRose)
                }
            }
            .onAppear {
                originalCurrency = journal.currency
            }
        }
    }

    private var currencySymbol: String {
        CurrencyInfo.popular.first(where: { $0.code == originalCurrency })?.symbol
            ?? CurrencyInfo.popular.first(where: { $0.code == journal.currency })?.symbol
            ?? journal.currency
    }

    private var isValid: Bool {
        guard let amount = Decimal(string: amountText), amount > 0 else { return false }
        return true
    }

    private func saveBill() {
        guard let amount = Decimal(string: amountText) else { return }
        let bill = BillRecord(
            date: date,
            amount: amount,
            originalCurrency: originalCurrency,
            category: selectedCategory,
            merchant: merchant.isEmpty ? nil : merchant,
            note: note.isEmpty ? nil : note,
            status: .confirmed
        )
        bill.journal = journal
        modelContext.insert(bill)
        try? modelContext.save()
        dismiss()
    }
}
