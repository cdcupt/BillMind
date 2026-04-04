import SwiftUI
import SwiftData

struct JournalsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Journal.createdDate, order: .reverse) private var journals: [Journal]
    @State private var showNewJournal = false
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: 16) {
                    if !journals.isEmpty {
                        StatsDashboardView(journals: journals)
                            .padding(.horizontal)
                    }

                    sectionHeader

                    if journals.isEmpty {
                        EmptyStateView(
                            animal: .cat,
                            title: "No journals yet!",
                            subtitle: "Create your first journal to start tracking bills"
                        )
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(journals) { journal in
                                NavigationLink(value: journal.id) {
                                    JournalCardView(journal: journal)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }

                    newJournalButton
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                }
                .padding(.top, 8)
            }
            .paperBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("BillMind")
                        .font(SketchTheme.titleFont(28))
                        .foregroundStyle(SketchTheme.softBrown)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewJournal = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(SketchTheme.softBrown)
                    }
                }
            }
            .navigationDestination(for: UUID.self) { journalId in
                if let journal = journals.first(where: { $0.id == journalId }) {
                    JournalDetailView(journal: journal)
                }
            }
            .sheet(isPresented: $showNewJournal) {
                NewJournalView { journalId in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        navigationPath.append(journalId)
                    }
                }
            }
        }
    }

    private var sectionHeader: some View {
        HStack {
            Text("My Journals")
                .font(SketchTheme.captionFont())
                .foregroundStyle(SketchTheme.lightBrown)
            Rectangle()
                .fill(SketchTheme.lightBrown.opacity(0.3))
                .frame(height: 1)
        }
        .padding(.horizontal)
    }

    private var newJournalButton: some View {
        Button {
            showNewJournal = true
        } label: {
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 24))
                    Text("New Journal")
                        .font(SketchTheme.captionFont())
                }
                .foregroundStyle(SketchTheme.lightBrown)
                Spacer()
            }
            .padding(.vertical, 20)
            .background(SketchTheme.warmWhite.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8, 4]))
                    .foregroundStyle(SketchTheme.lightBrown.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Journal Card

struct JournalCardView: View {
    let journal: Journal

    private var currencySymbol: String {
        CurrencyInfo.popular.first(where: { $0.code == journal.currency })?.symbol ?? journal.currency
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(journal.coverAnimal.imageName)
                .resizable().scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 2) {
                Text(journal.name)
                    .font(SketchTheme.headlineFont(18))
                    .foregroundStyle(SketchTheme.softBrown)
                Text("\(journal.createdDate.formatted(as: "MMM d, yyyy")) · \(journal.currency)")
                    .font(SketchTheme.captionFont(12))
                    .foregroundStyle(SketchTheme.lightBrown)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(currencySymbol)\(journal.totalAmount.formatted2)")
                    .font(SketchTheme.headlineFont(18))
                    .foregroundStyle(SketchTheme.dustyRose)
                Text("\(journal.billCount) bills")
                    .font(SketchTheme.captionFont(12))
                    .foregroundStyle(SketchTheme.lightBrown)
            }
        }
        .sketchCard()
    }
}
