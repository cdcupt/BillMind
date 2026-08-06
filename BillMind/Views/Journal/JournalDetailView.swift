import SwiftUI
import SwiftData

struct BillNavID: Hashable {
    let id: UUID
}

struct JournalDetailView: View {
    @Bindable var journal: Journal
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: AuthSession

    private var currencySymbol: String {
        CurrencyInfo.popular.first(where: { $0.code == journal.currency })?.symbol ?? journal.currency
    }

    @State private var showMindFullscreen = false
    /// A currency-change save failure surfaced to the user, never swallowed.
    @State private var currencyError: String?

    private var mindImage: UIImage? {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("minds/\(journal.id.uuidString)", isDirectory: true)
        let path = dir.appendingPathComponent("mind.jpg").path
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return UIImage(contentsOfFile: path)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Saved Mind (if exists)
                if let mind = mindImage {
                    Button { showMindFullscreen = true } label: {
                        Image(uiImage: mind)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .shadow(color: SketchTheme.paperShadow, radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }

                // Currency widget
                currencyWidget

                // Bills grouped by date
                if journal.liveBills.isEmpty {
                    EmptyStateView(
                        animal: .cat,
                        title: "No bills yet!",
                        subtitle: "Add bills from the Record tab —\njust tell Ollie about them"
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
        }
        .navigationDestination(for: BillNavID.self) { navId in
            if let bill = journal.bills.first(where: { $0.id == navId.id }) {
                BillDetailView(bill: bill, currencySymbol: bill.displayCurrencySymbol)
            }
        }
        .fullScreenCover(isPresented: $showMindFullscreen) {
            if let mind = mindImage {
                ZoomableImageView(image: mind)
            }
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

            // The trip currency. Changeable only while the trip has no bills —
            // changing it later would silently relabel recorded money under a
            // different symbol, so once a bill exists the code is fixed.
            if journal.billCount == 0 {
                Menu {
                    ForEach(CurrencyInfo.popular) { currency in
                        Button("\(currency.code) \(currency.symbol) · \(currency.name)") {
                            changeCurrency(to: currency.code)
                        }
                    }
                } label: {
                    currencyChip("\(journal.currency) ▾")
                }
                .accessibilityIdentifier("journal-currency-menu")
                .alert("Couldn't change currency", isPresented: Binding(
                    get: { currencyError != nil },
                    set: { if !$0 { currencyError = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(currencyError ?? "")
                }
            } else {
                currencyChip(journal.currency)
            }

            Spacer()

            Text("Total: \(journal.liveBills.perCurrencyTotals)")
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

    private func currencyChip(_ label: String) -> some View {
        Text(label)
            .font(SketchTheme.captionFont())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(SketchTheme.warmWhite)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(SketchTheme.lightBrown.opacity(0.2), lineWidth: 1)
            )
    }

    private func changeCurrency(to code: String) {
        guard journal.billCount == 0, journal.currency != code else { return }
        let previous = journal.currency
        journal.currency = code
        do {
            try modelContext.save()
        } catch {
            journal.currency = previous
            currencyError = "The change couldn't be saved. Please try again. (\(error.localizedDescription))"
            return
        }
        // An already-synced trip PATCHes the change up immediately and
        // explicitly — server-side recognition validates against the trip
        // currency. It must NOT ride the deferred rename push: a stale client's
        // name-only rename would then carry its old currency and clobber a
        // server-side change, or trip the server's 0-bills rule and wedge sync.
        // On failure the local change rolls back and surfaces — never queued.
        // A not-yet-created trip simply carries the new currency on create.
        guard let serverID = journal.serverID else { return }
        Task {
            do {
                let trip = try await auth.client.updateTrip(
                    serverID, APIUpdateTripRequest(currencyCode: code))
                journal.rowVersion = trip.rowVersion
                try? modelContext.save()   // LWW bookkeeping; the currency itself is already saved
            } catch {
                journal.currency = previous
                try? modelContext.save()
                currencyError = "The server didn't accept the currency change, so it was rolled back. Check your connection and try again."
            }
        }
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
                    NavigationLink(value: BillNavID(id: bill.id)) {
                        // Per-bill symbol: a kept-foreign bill (Keep-GBP clarify)
                        // renders as £, never under the journal's symbol.
                        BillCardView(bill: bill, currencySymbol: bill.displayCurrencySymbol)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }
            }
        }
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
