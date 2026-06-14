import SwiftUI
import SwiftData
import PhotosUI

/// The Record tab: pick a journal, then type a phrase (or pick photos) and the
/// agent turns each into an editable bill card you confirm. Text capture needs no
/// AI or API key.
struct RecordView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: AuthSession
    @EnvironmentObject private var sync: SyncCoordinator
    @Query(sort: \Journal.createdDate, order: .reverse) private var journals: [Journal]

    @State private var coordinator: RecordCoordinator?
    @State private var selectedJournalID: UUID?
    @State private var inputText = ""
    @State private var editTarget: EditTarget?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showNewJournal = false
    @State private var showTrips = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if journals.isEmpty {
                    emptyState
                } else if let coordinator {
                    session(coordinator)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .paperBackground()
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showTrips = true } label: {
                        Image(systemName: "book.closed.fill")
                            .foregroundStyle(SketchTheme.softBrown)
                    }
                    .accessibilityIdentifier("record-trips")
                }
            }
            .sheet(isPresented: $showTrips) {
                JournalsListView()
                    .environmentObject(sync)
            }
        }
        .onAppear { if coordinator == nil { setup() } }
        .onChange(of: selectedJournalID) { _, _ in rebuild() }
        .onChange(of: journals.count) { _, _ in if coordinator == nil { setup() } }
        .onChange(of: photoItems) { _, items in loadPhotos(items) }
        .sheet(item: $editTarget) { target in
            if let coordinator {
                EditDrawerView(target: target, coordinator: coordinator) { editTarget = nil }
            }
        }
        .sheet(isPresented: $showNewJournal) {
            NewJournalView { id in selectedJournalID = id }
                .environmentObject(sync)
        }
    }

    // MARK: - Session

    private func session(_ coordinator: RecordCoordinator) -> some View {
        VStack(spacing: 0) {
            journalChip(coordinator)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        introCard
                        ForEach(coordinator.cards) { card in
                            AgentCardView(card: card, coordinator: coordinator) { field in
                                editTarget = EditTarget(cardID: card.id, field: field)
                            }
                            .id(card.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: coordinator.cards.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            inputBar(coordinator)
        }
    }

    private func journalChip(_ coordinator: RecordCoordinator) -> some View {
        Menu {
            ForEach(journals) { journal in
                Button(journal.name) { selectedJournalID = journal.id }
            }
        } label: {
            HStack(spacing: 8) {
                Image(coordinator.journal.coverAnimal.imageName)
                    .resizable().scaledToFill().frame(width: 28, height: 28).clipShape(Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(coordinator.journal.name).font(SketchTheme.headlineFont(15)).foregroundStyle(SketchTheme.softBrown)
                    Text("filing bills here · \(coordinator.journal.currency)").font(SketchTheme.captionFont(11)).foregroundStyle(SketchTheme.lightBrown)
                }
                Spacer()
                Text("switch ▾").font(SketchTheme.captionFont(13)).foregroundStyle(SketchTheme.softBlue)
            }
            .padding(10)
            .background(SketchTheme.warmWhite)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(SketchTheme.lightBrown.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4])))
            .padding(.horizontal).padding(.top, 6)
        }
        .accessibilityIdentifier("record-journal")
    }

    private var introCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(AnimalType.cat.imageName).resizable().scaledToFill().frame(width: 34, height: 34).clipShape(Circle())
            Text("Tell me about a bill — like “ramen 2840” — or 📷 a receipt. I'll make a card you can edit, and ask if something's unclear. Nothing saves until you tap Save.")
                .font(SketchTheme.bodyFont(13)).foregroundStyle(SketchTheme.softBrown)
        }
        .padding(12)
        .background(SketchTheme.warmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(SketchTheme.lightBrown.opacity(0.35), lineWidth: 1.5))
    }

    private func inputBar(_ coordinator: RecordCoordinator) -> some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 16)).foregroundStyle(SketchTheme.softBrown)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(SketchTheme.lightBrown, lineWidth: 1.5))
            }
            .accessibilityIdentifier("record-photos")

            TextField("Tell Mochi about a bill…", text: $inputText)
                .textFieldStyle(.plain)
                .submitLabel(.send)
                .focused($inputFocused)
                .onSubmit { send(coordinator) }
                .accessibilityIdentifier("record-input")

            Button { send(coordinator) } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26)).foregroundStyle(SketchTheme.dustyRose)
            }
            .accessibilityIdentifier("record-send")
        }
        .padding(10)
        .background(SketchTheme.warmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(SketchTheme.lightBrown, lineWidth: 1.8))
        .padding(.horizontal).padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            EmptyStateView(animal: .cat, title: "No trips yet!", subtitle: "Create a trip first,\nthen record bills into it")
            Button { showNewJournal = true } label: {
                HandDrawnButton(title: "Create a Trip", icon: "plus", style: .primary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("record-create-journal")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func send(_ coordinator: RecordCoordinator) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        inputFocused = false        // dismiss the keyboard so the new card (and tab bar) are reachable
        coordinator.submitText(text)
    }

    private func setup() {
        guard !journals.isEmpty else { return }
        let id = selectedJournalID ?? journals.first?.id
        selectedJournalID = id
        if let journal = journals.first(where: { $0.id == id }) {
            coordinator = RecordCoordinator(journal: journal, modelContext: modelContext, recognizer: auth.client)
        }
    }

    private func rebuild() {
        guard let id = selectedJournalID, let journal = journals.first(where: { $0.id == id }) else { return }
        coordinator = RecordCoordinator(journal: journal, modelContext: modelContext, recognizer: auth.client)
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty, let coordinator else { return }
        Task {
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            await MainActor.run {
                coordinator.submitPhotos(images)
                photoItems = []
            }
        }
    }
}
