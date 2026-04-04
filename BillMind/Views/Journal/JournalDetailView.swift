import SwiftUI
import SwiftData

struct JournalDetailView: View {
    @Bindable var journal: Journal
    @Environment(\.modelContext) private var modelContext
    @State private var showAddBill = false
    @State private var showImportFlow = false

    private var currencySymbol: String {
        CurrencyInfo.popular.first(where: { $0.code == journal.currency })?.symbol ?? journal.currency
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Currency widget
                currencyWidget

                // Bills grouped by date
                if journal.bills.isEmpty {
                    EmptyStateView(
                        animal: .cat,
                        title: "No bills yet!",
                        subtitle: "Tap the camera button to scan bills\nor add one manually"
                    )
                } else {
                    billsList
                }
            }
            .padding(.top, 8)
        }
        .paperBackground()
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Text(journal.name)
                        .font(SketchTheme.headlineFont(20))
                        .foregroundStyle(SketchTheme.softBrown)
                    Image(journal.coverAnimal.imageName)
                        .resizable().scaledToFill()
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showAddBill = true
                    } label: {
                        Label("Add Manually", systemImage: "pencil")
                    }
                    Button {
                        showImportFlow = true
                    } label: {
                        Label("Scan Bills", systemImage: "camera")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SketchTheme.softBrown)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            fabButton
        }
        .sheet(isPresented: $showAddBill) {
            AddBillManualView(journal: journal)
        }
        .sheet(isPresented: $showImportFlow) {
            // Placeholder for BillImportFlowView (Phase 2)
            Text("Bill Import Flow — Coming in Phase 2")
                .font(SketchTheme.headlineFont())
                .foregroundStyle(SketchTheme.lightBrown)
                .padding()
        }
    }

    // MARK: - Currency Widget

    private var currencyWidget: some View {
        HStack(spacing: 8) {
            Text("\(journal.billCount) bills")
                .font(SketchTheme.captionFont())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(SketchTheme.warmWhite)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(SketchTheme.lightBrown.opacity(0.2), lineWidth: 1)
                )

            Spacer()

            Text("Total: \(currencySymbol)\(journal.totalAmount.formatted2)")
                .font(SketchTheme.headlineFont(16))
                .foregroundStyle(SketchTheme.dustyRose)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(SketchTheme.warmWhite)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(SketchTheme.dustyRose.opacity(0.2), lineWidth: 1)
                )
        }
        .padding(.horizontal)
        .foregroundStyle(SketchTheme.softBrown)
    }

    // MARK: - Bills List

    private var billsList: some View {
        LazyVStack(spacing: 8) {
            ForEach(journal.billsByDate, id: \.date) { group in
                // Date section header
                HStack {
                    Text(group.date.relativeLabel)
                        .font(SketchTheme.captionFont())
                        .foregroundStyle(SketchTheme.lightBrown)
                    Rectangle()
                        .fill(SketchTheme.lightBrown.opacity(0.2))
                        .frame(height: 1)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                ForEach(group.bills) { bill in
                    BillCardView(bill: bill, currencySymbol: currencySymbol)
                        .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - FAB

    private var fabButton: some View {
        Button {
            showImportFlow = true
        } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(SketchTheme.primaryGradient)
                .clipShape(Circle())
                .shadow(color: SketchTheme.dustyRose.opacity(0.3), radius: 8, y: 4)
        }
        .padding(.trailing, 24)
        .padding(.bottom, 24)
    }
}

// MARK: - Bill Card

struct BillCardView: View {
    let bill: BillRecord
    let currencySymbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(bill.category.icon)
                .resizable().scaledToFill()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(bill.merchant ?? bill.category.displayName)
                    .font(SketchTheme.headlineFont(16))
                    .foregroundStyle(SketchTheme.softBrown)
                HStack(spacing: 6) {
                    Text(bill.date.formatted(as: "h:mm a"))
                        .font(SketchTheme.captionFont(11))
                        .foregroundStyle(SketchTheme.lightBrown)
                    StatusBadge(status: bill.status)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(currencySymbol)\(bill.amount.formatted2)")
                    .font(SketchTheme.headlineFont(18))
                    .foregroundStyle(bill.category.color)
                if let note = bill.note, !note.isEmpty {
                    Text(note)
                        .font(SketchTheme.captionFont(11))
                        .foregroundStyle(SketchTheme.lightBrown)
                        .lineLimit(1)
                }
            }
        }
        .sketchCard(cornerRadius: 16)
    }
}

struct StatusBadge: View {
    let status: BillStatus

    var body: some View {
        Text(status == .confirmed ? "Confirmed" : "AI Draft")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(status == .confirmed ? SketchTheme.sageGreen.opacity(0.2) : SketchTheme.warmOrange.opacity(0.2))
            .foregroundStyle(status == .confirmed ? Color(hex: "5A7A50") : Color(hex: "8A6A30"))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
