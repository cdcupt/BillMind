import SwiftUI
import SwiftData
import PhotosUI
import Speech
import AVFoundation
import os

/// One photo staged in the compose tray: a thumbnail held above the input bar with
/// its own editable caption, waiting to be sent as ONE bill. Identity is the `id`;
/// the caption mutates as the user types/dictates into the active chip.
struct StagedChip: Identifiable, Equatable {
    let id = UUID()
    let image: UIImage
    var caption: String = ""

    static func == (lhs: StagedChip, rhs: StagedChip) -> Bool {
        lhs.id == rhs.id && lhs.caption == rhs.caption && lhs.image === rhs.image
    }
}

/// The Record tab: pick a journal, then type a phrase (or pick photos) and the
/// agent turns each into an editable bill card you confirm. Text capture needs no
/// AI or API key.
struct RecordView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: AuthSession
    @EnvironmentObject private var sync: SyncCoordinator
    @Query(filter: #Predicate<Journal> { !$0.isTombstoned },
           sort: \Journal.createdDate, order: .reverse) private var journals: [Journal]

    @State private var coordinator: RecordCoordinator?
    @State private var selectedJournalID: UUID?
    @State private var inputText = ""
    @State private var editTarget: EditTarget?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showNewJournal = false
    @State private var showTrips = false
    /// Compose: photos picked are STAGED as chips (not submitted) so the field below
    /// becomes that photo's caption. Send dispatches one composed request per chip.
    @State private var stagedChips: [StagedChip] = []
    /// The chip the caption field is bound to (terra ring). Tapping a chip activates it.
    @State private var activeChipID: UUID?
    /// A gentle "touch the flagged groups first" note when "Save all" is blocked by
    /// still-open fuse/duplicate groups. Cleared once the user resolves them.
    @State private var blockedNote: String?
    @StateObject private var voice = VoiceCapture()
    @FocusState private var inputFocused: Bool
    /// True while the first-launch welcome sheet is presented over this tab. The
    /// root is dimmed behind it, so we suppress the large empty-state mascot, which
    /// would otherwise peek above the sheet's grab handle and read as a clipped
    /// image. Driven by the actual presentation (via the environment), not a
    /// persisted flag, so the debug-forced and synced-journal paths behave too.
    @Environment(\.welcomeNoticePresented) private var welcomeNoticePresented

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
        // The session's validator captures the journal currency at build time; a
        // currency change (offered only on 0-bill trips) must rebuild it or this
        // tab keeps validating — and clarifying — against the old currency.
        .onChange(of: coordinator?.journal.currency) { _, _ in rebuild() }
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
                    if coordinator.batchPhase == .reviewing {
                        reviewSurface(coordinator)
                    } else {
                        addingScroll(coordinator)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: coordinator.cards.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            // The untangle round-trip: a calm "Ollie is tidying…" overlay reusing the
            // thinking-state grammar, replacing the input bar while it runs.
            if coordinator.batchPhase == .untangling {
                untanglingBar
            } else {
                if let decline = coordinator.declineMessage {
                    noticeBanner(decline, icon: "hand.raised.fill", tone: SketchTheme.softBlue) {
                        coordinator.declineMessage = nil
                    }
                }
                if let error = coordinator.errorMessage {
                    noticeBanner(error, icon: "exclamationmark.triangle.fill", tone: SketchTheme.mutedRed) {
                        coordinator.errorMessage = nil
                    }
                }
                // A calm "I kept these separate" note when the untangle hop couldn't run
                // (trip unsynced / server failed). Same dismissable banner; cards still saved.
                if let degrade = coordinator.degradeMessage {
                    noticeBanner(degrade, icon: "tray.full.fill", tone: SketchTheme.softBlue) {
                        coordinator.degradeMessage = nil
                    }
                }
                // Sticky "Done adding · Review N" — only while a multi-card pile is held.
                if coordinator.showsDoneAddingBar {
                    doneAddingBar(coordinator)
                }
                // One "Save all" instead of the input bar once a reviewed batch is in.
                if coordinator.batchPhase == .reviewing {
                    saveAllBar(coordinator)
                } else {
                    inputBar(coordinator)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: coordinator.batchPhase)
        // Resolving a group clears the "touch these first" note so it never lingers
        // after the user acts; they re-tap Save all to write the now-clean batch.
        .onChange(of: coordinator.groups.count) { _, _ in blockedNote = nil }
    }

    // MARK: - Adding scroll (staged cards)

    private func addingScroll(_ coordinator: RecordCoordinator) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            introCard
            ForEach(coordinator.cards) { card in
                AgentCardView(card: card, coordinator: coordinator) { field in
                    editTarget = EditTarget(cardID: card.id, field: field)
                }
                .id(card.id)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Review surface (groups + plain cards)

    /// When the held batch is reviewing, the same vertical scroll shows Ollie's
    /// proposed fuses and flagged duplicates as tethered groups, with the unclaimed
    /// held cards rendered as ordinary review rows — no new screen.
    private func reviewSurface(_ coordinator: RecordCoordinator) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            reviewHeader(coordinator)
            ForEach(coordinator.groups) { group in
                groupRow(group, coordinator: coordinator).id(group.id)
            }
            // Render EVERY non-terminal unclaimed card — not just `.review` ones —
            // so a card still being clarified/validated/retried stays visible here and
            // shows its own fix-it UI. (Savable count below is still `.review`-only.)
            ForEach(coordinator.reviewSurfaceCards) { card in
                AgentCardView(card: card, coordinator: coordinator) { field in
                    editTarget = EditTarget(cardID: card.id, field: field)
                }
                .id(card.id)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func groupRow(_ group: UntangleGroup, coordinator: RecordCoordinator) -> some View {
        switch group {
        case let .fuseProposed(groupID, resolved, sourceCardIDs, amountTrace, reason, _):
            FuseProposalView(
                groupID: groupID,
                resolved: resolved,
                sourceCards: sourceCardIDs.compactMap { coordinator.session.card($0) },
                amountTrace: amountTrace,
                reason: reason,
                coordinator: coordinator)
        case let .flaggedDuplicate(groupID, memberCardIDs, survivorID, tier, reason):
            DuplicateGroupView(
                groupID: groupID,
                members: memberCardIDs.compactMap { coordinator.session.card($0) },
                survivorID: survivorID,
                tier: tier,
                reason: reason,
                coordinator: coordinator)
        }
    }

    private func reviewHeader(_ coordinator: RecordCoordinator) -> some View {
        let n = coordinator.groups.count
        let text = n == 0
            ? "All set — nothing looked doubled up."
            : "I tidied these up — \(n) to look at."
        return OllieNoteBar(text: text)
            .padding(12)
            .background(SketchTheme.warmWhite)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(SketchTheme.lightBrown.opacity(0.35), lineWidth: 1.5))
    }

    // MARK: - Sticky bars

    private func doneAddingBar(_ coordinator: RecordCoordinator) -> some View {
        HStack(spacing: 10) {
            Image(AnimalType.owl.imageName)
                .resizable().scaledToFill().frame(width: 30, height: 30).clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("Done adding?").font(SketchTheme.headlineFont(15)).foregroundStyle(SketchTheme.softBrown)
                Text("I’ll tidy these up.").font(SketchTheme.captionFont(11)).foregroundStyle(SketchTheme.lightBrown)
            }
            Spacer()
            Button { coordinator.markDoneAdding() } label: {
                Label("Review \(coordinator.cards.count)", systemImage: "wand.and.stars")
            }
            .buttonStyle(HandDrawnButtonStyle(filled: true))
            .accessibilityIdentifier("record-done-adding")
        }
        .padding(10)
        .background(SketchTheme.warmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(SketchTheme.warmOrange.opacity(0.5), style: StrokeStyle(lineWidth: 1.6, dash: [4])))
        .padding(.horizontal).padding(.bottom, 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var untanglingBar: some View {
        HStack(spacing: 10) {
            Image(AnimalType.owl.imageName)
                .resizable().scaledToFill().frame(width: 30, height: 30).clipShape(Circle())
            Text("Ollie’s tidying these up…").font(SketchTheme.bodyFont(14)).foregroundStyle(SketchTheme.softBrown)
            Spacer()
            ProgressView().tint(SketchTheme.dustyRose)
        }
        .padding(12)
        .background(SketchTheme.warmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(SketchTheme.warmOrange.opacity(0.5), lineWidth: 1.8))
        .padding(.horizontal).padding(.bottom, 8)
        .accessibilityIdentifier("record-untangling")
    }

    /// "Save all to trip · N bills". On tap, `confirmAll` writes one bill per plain
    /// review card; if any group is still open (its members blocked), it gently
    /// asks the user to touch those first — each group keeps a safe default, so
    /// nothing is saved over an unresolved decision.
    private func saveAllBar(_ coordinator: RecordCoordinator) -> some View {
        let savableCount = coordinator.plainReviewCards.count
        let openGroups = coordinator.groups.count
        // Held cards on the surface that aren't yet savable (still being clarified /
        // validated / retried). We surface this so the bar never reads a bare,
        // misleading "0 bills" while the user still has bills to finish above.
        let unfinished = max(0, coordinator.reviewSurfaceCards.count - savableCount)
        return VStack(spacing: 6) {
            if let blockedNote {
                Text(blockedNote)
                    .font(SketchTheme.captionFont(12)).foregroundStyle(SketchTheme.mutedRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("record-save-blocked")
            } else if openGroups > 0 {
                Text("\(openGroups) group\(openGroups == 1 ? "" : "s") to confirm · pre-set to the safe choice")
                    .font(SketchTheme.captionFont(12)).foregroundStyle(SketchTheme.lightBrown)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if unfinished > 0 {
                Text("Finish \(unfinished) above to save \(unfinished == 1 ? "it" : "them")")
                    .font(SketchTheme.captionFont(12)).foregroundStyle(SketchTheme.lightBrown)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("record-save-unfinished")
            }
            // Nothing savable yet but cards still need finishing: keep the button
            // present (so the surface reads as a real review) but disabled, rather
            // than inviting a no-op "Save · 0 bills" tap.
            let nothingSavableYet = savableCount == 0 && unfinished > 0
            Button { saveAll(coordinator) } label: {
                Label("Save all to trip · \(savableCount) bill\(savableCount == 1 ? "" : "s")",
                      systemImage: "tray.and.arrow.down.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(HandDrawnButtonStyle(filled: true))
            .disabled(nothingSavableYet)
            .opacity(nothingSavableYet ? 0.5 : 1)
            .accessibilityIdentifier("record-save-all")
        }
        .padding(.horizontal).padding(.bottom, 8)
    }

    /// A calm, dismissable banner — used for moderation declines and errors.
    private func noticeBanner(_ text: String, icon: String, tone: Color,
                              onDismiss: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tone)
            Text(text).font(SketchTheme.bodyFont(13)).foregroundStyle(SketchTheme.softBrown)
            Spacer(minLength: 4)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(SketchTheme.lightBrown)
            }
            .accessibilityIdentifier("record-notice-dismiss")
        }
        .padding(10)
        .background(SketchTheme.warmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tone.opacity(0.4), lineWidth: 1.5))
        .padding(.horizontal)
        .padding(.bottom, 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
                    Text(journalChipSubtitle(coordinator.journal)).font(SketchTheme.captionFont(11)).foregroundStyle(SketchTheme.lightBrown)
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

    /// The chip's status line doubles as save feedback: the count reads straight
    /// off the journal's live bills, so it ticks up the moment a card records —
    /// visible proof a save landed (a saved card leaves the input immediately).
    private func journalChipSubtitle(_ journal: Journal) -> String {
        switch journal.billCount {
        case 0: return "filing bills here · \(journal.currency)"
        case 1: return "1 bill in trip · \(journal.currency)"
        case let n: return "\(n) bills in trip · \(journal.currency)"
        }
    }

    private var introCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(AnimalType.owl.imageName).resizable().scaledToFill().frame(width: 34, height: 34).clipShape(Circle())
            Text("Tell me about a bill — like “ramen 2840” — or 📷 a receipt. I'll make a card you can edit, and ask if something's unclear. Nothing saves until you tap Save.")
                .font(SketchTheme.bodyFont(13)).foregroundStyle(SketchTheme.softBrown)
        }
        .padding(12)
        .background(SketchTheme.warmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(SketchTheme.lightBrown.opacity(0.35), lineWidth: 1.5))
    }

    private func inputBar(_ coordinator: RecordCoordinator) -> some View {
        VStack(spacing: 8) {
            if !stagedChips.isEmpty {
                stagedTray
            }
            HStack(spacing: 8) {
                PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 16)).foregroundStyle(SketchTheme.softBrown)
                        .frame(width: 34, height: 34)
                        .overlay(Circle().stroke(SketchTheme.lightBrown, lineWidth: 1.5))
                }
                .accessibilityIdentifier("record-photos")

                micButton(coordinator)

                TextField(captionPlaceholder, text: $inputText)
                    .textFieldStyle(.plain)
                    .submitLabel(.send)
                    .focused($inputFocused)
                    .disabled(voice.isRecording)
                    .onSubmit { send(coordinator) }
                    // Keep the active chip's caption in lock-step with the field so a
                    // re-render (e.g. tray re-layout) never reads a stale note.
                    .onChange(of: inputText) { _, text in
                        guard let id = activeChipID,
                              let i = stagedChips.firstIndex(where: { $0.id == id }) else { return }
                        if stagedChips[i].caption != text { stagedChips[i].caption = text }
                    }
                    .accessibilityIdentifier("record-input")

                Button { send(coordinator) } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26)).foregroundStyle(SketchTheme.dustyRose)
                }
                .disabled(voice.isRecording)   // avoid submitting partial text mid-dictation
                .accessibilityIdentifier("record-send")
            }
        }
        .padding(10)
        .background(SketchTheme.warmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .stroke(voice.isRecording ? SketchTheme.mutedRed : SketchTheme.lightBrown, lineWidth: 1.8))
        .padding(.horizontal).padding(.bottom, 8)
        // Mirror the live transcription into the field as the user speaks.
        .onChange(of: voice.transcript) { _, text in
            if voice.isRecording { inputText = text }
        }
        .onChange(of: voice.errorMessage) { _, message in
            if let message { coordinator.errorMessage = message; voice.errorMessage = nil }
        }
        .animation(.easeInOut(duration: 0.2), value: voice.isRecording)
        .animation(.easeInOut(duration: 0.2), value: stagedChips)
    }

    /// The field's placeholder reflects the compose state: a note prompt while a photo
    /// is staged, the listening hint mid-dictation, else the default bill prompt.
    private var captionPlaceholder: String {
        if voice.isRecording { return "Listening…" }
        if !stagedChips.isEmpty { return "Add a note for this photo…" }
        return "Tell Ollie about a bill…"
    }

    /// The horizontal tray of staged photo chips above the bar. The active chip is
    /// ringed in terra and the field binds to its caption; ✕ un-stages a chip.
    private var stagedTray: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(stagedChips.count > 1 ? "Tap a photo to note it" : "Pinned to this photo")
                .font(SketchTheme.captionFont(11))
                .foregroundStyle(SketchTheme.dustyRose)
                .accessibilityIdentifier("record-staged-hint")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(stagedChips) { chip in
                        chipView(chip)
                    }
                }
                .padding(.horizontal, 2).padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("record-staged-tray")
    }

    private func chipView(_ chip: StagedChip) -> some View {
        let isActive = chip.id == activeChipID
        let preview = chip.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        return Button {
            activateChip(chip.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: chip.image)
                        .resizable().scaledToFill()
                        .frame(width: 56, height: 66)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    Button { removeChip(chip.id) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(SketchTheme.mutedRed)
                            .background(Circle().fill(SketchTheme.warmWhite).padding(2))
                    }
                    .offset(x: 6, y: -6)
                    .accessibilityIdentifier("record-chip-remove")
                }
                Text(preview.isEmpty ? "no note yet" : preview)
                    .font(SketchTheme.captionFont(10))
                    .foregroundStyle(preview.isEmpty ? SketchTheme.lightBrown : SketchTheme.sageGreen)
                    .lineLimit(1)
                    .frame(width: 64, alignment: .leading)
            }
            .padding(6)
            .background(SketchTheme.warmWhite)
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13)
                .stroke(isActive ? SketchTheme.dustyRose : SketchTheme.lightBrown.opacity(0.4),
                        lineWidth: isActive ? 2 : 1.4))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("record-chip")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    /// Tap to start dictation, tap again to stop — the final transcript is
    /// submitted through the same AI pipeline as typed text.
    private func micButton(_ coordinator: RecordCoordinator) -> some View {
        Button { toggleVoice(coordinator) } label: {
            Image(systemName: voice.isRecording ? "stop.fill" : "mic.fill")
                .font(.system(size: 15))
                .foregroundStyle(voice.isRecording ? .white : SketchTheme.softBrown)
                .frame(width: 34, height: 34)
                .background(Circle().fill(voice.isRecording ? SketchTheme.mutedRed : Color.clear))
                .overlay(Circle().stroke(voice.isRecording ? SketchTheme.mutedRed : SketchTheme.lightBrown, lineWidth: 1.5))
                .scaleEffect(voice.isRecording ? 1.08 : 1)
        }
        .accessibilityIdentifier("record-mic")
        .accessibilityLabel(voice.isRecording ? "Stop listening" : "Record by voice")
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            // Hide the mascot while the first-launch welcome sheet is up: dimmed
            // behind a medium sheet, its head peeks over the grab handle and reads
            // as a clipped/broken image. It returns once the notice is dismissed.
            if welcomeNoticePresented {
                Text("No trips yet!")
                    .font(SketchTheme.headlineFont(22))
                    .foregroundStyle(SketchTheme.softBrown)
            } else {
                EmptyStateView(animal: .cat, title: "No trips yet!", subtitle: "Create a trip first,\nthen record bills into it")
            }
            Button { showNewJournal = true } label: {
                HandDrawnButton(title: "Create a Trip", icon: "plus", style: .primary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("record-create-journal")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    /// Send. If chips are staged, each is dispatched as ONE composed request (photo +
    /// its caption) → one bill per chip, then the tray and field clear. With nothing
    /// staged, the text-only path (`submitText`) is byte-for-byte unchanged.
    private func send(_ coordinator: RecordCoordinator) {
        if !stagedChips.isEmpty {
            sendComposed(coordinator)
            return
        }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        inputFocused = false        // dismiss the keyboard so the new card (and tab bar) are reachable
        coordinator.submitText(text)
    }

    /// Dispatch every staged chip as a composed photo + caption (one request → one bill
    /// each). A chip with an empty caption sends as photo-only (unchanged from today's
    /// instant photo capture).
    ///
    /// `submitComposed` can REJECT a send (unsynced trip → `serverID == nil`, or the
    /// session limit was reached) and surface a retryable `errorMessage`. We must NOT
    /// clear a chip that wasn't accepted, or the photo + its caption are lost while the
    /// user is told to try again. So we keep only the chips that `submitComposed`
    /// accepted; any rejected chip stays staged (with its caption preserved) and the
    /// active selection re-binds to a surviving chip so the user can retry. When the trip
    /// is unsynced every chip is rejected and nothing is lost.
    private func sendComposed(_ coordinator: RecordCoordinator) {
        commitFieldToActiveChip()       // fold the in-progress note into its chip first
        let previousActiveID = activeChipID
        let surviving = stagedChips.filter { chip in
            !coordinator.submitComposed(image: chip.image, caption: chip.caption)
        }
        stagedChips = surviving
        if surviving.isEmpty {
            activeChipID = nil
            inputText = ""
            inputFocused = false
        } else {
            // Keep the previously active chip selected if it was rejected; otherwise
            // re-bind to the first surviving chip so its caption stays editable.
            activeChipID = surviving.contains { $0.id == previousActiveID } ? previousActiveID : surviving.first?.id
            inputText = surviving.first(where: { $0.id == activeChipID })?.caption ?? ""
        }
    }

    /// Make `id` the active chip and bind the field to its caption.
    private func activateChip(_ id: UUID) {
        guard id != activeChipID else { return }
        commitFieldToActiveChip()
        activeChipID = id
        inputText = stagedChips.first { $0.id == id }?.caption ?? ""
        inputFocused = true
    }

    /// Remove a staged chip (its ✕). If it was active, the field re-binds to the next
    /// remaining chip (or clears when the tray empties).
    private func removeChip(_ id: UUID) {
        if id == activeChipID {
            stagedChips.removeAll { $0.id == id }
            activeChipID = stagedChips.first?.id
            inputText = stagedChips.first(where: { $0.id == activeChipID })?.caption ?? ""
        } else {
            // Preserve the active chip's unsaved field edits across the removal.
            commitFieldToActiveChip()
            stagedChips.removeAll { $0.id == id }
        }
    }

    /// Fold the live field text into the active chip's caption so a chip switch / send /
    /// stage never drops what the user just typed.
    private func commitFieldToActiveChip() {
        guard let id = activeChipID,
              let index = stagedChips.firstIndex(where: { $0.id == id }) else { return }
        stagedChips[index].caption = inputText
    }

    /// Save the whole reviewed batch. `confirmAll` returns the ids it could NOT save
    /// — members still claimed by an open group, or a row missing an amount. If any
    /// came back blocked, we don't toast or destroy anything: we leave the rows in
    /// review (each group keeps its safe default) and surface a calm "touch these
    /// first" note. An empty result means every plain card was written.
    private func saveAll(_ coordinator: RecordCoordinator) {
        let blocked = coordinator.confirmAll(acknowledging: true)
        if blocked.isEmpty {
            blockedNote = nil
        } else if !coordinator.groups.isEmpty {
            let k = coordinator.groups.count
            blockedNote = "Take a look at the \(k) I flagged first."
        } else {
            blockedNote = "A card still needs an amount — tap it to add one."
        }
    }

    /// Start dictation, or stop it. With a chip staged, the transcript dictates the
    /// active chip's CAPTION — it stays as the editable note (no auto-submit, so a
    /// misheard amount can be fixed before send). With nothing staged, the final
    /// transcript flows straight into the AI as a text bill (unchanged).
    private func toggleVoice(_ coordinator: RecordCoordinator) {
        if voice.isRecording {
            voice.stop()
            return
        }
        // Compose: dictate INTO the active chip's caption; don't wipe what's there.
        if !stagedChips.isEmpty {
            inputFocused = false
            voice.start { _ in }     // transcript mirrors into the field via onChange; kept on stop
            return
        }
        inputFocused = false
        inputText = ""
        voice.start { transcript in
            let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            inputText = ""
            guard !text.isEmpty else { return }
            coordinator.submitText(text)
        }
    }

    private func setup() {
        guard !journals.isEmpty else { return }
        let id = selectedJournalID ?? journals.first?.id
        selectedJournalID = id
        if let journal = journals.first(where: { $0.id == id }) {
            coordinator = RecordCoordinator(journal: journal, modelContext: modelContext, recognizer: auth.client, sync: sync)
        }
    }

    private func rebuild() {
        guard let id = selectedJournalID, let journal = journals.first(where: { $0.id == id }) else { return }
        coordinator = RecordCoordinator(journal: journal, modelContext: modelContext, recognizer: auth.client, sync: sync)
    }

    /// Picking photos no longer submits — it STAGES each as a chip so the field below
    /// becomes that photo's caption. The first newly-staged chip becomes active so the
    /// caption field binds to it right away.
    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            await MainActor.run {
                let newChips = images.map { StagedChip(image: $0) }
                guard !newChips.isEmpty else { photoItems = []; return }
                // Persist the active chip's in-progress caption before re-binding the field.
                commitFieldToActiveChip()
                stagedChips.append(contentsOf: newChips)
                activeChipID = newChips.first?.id
                inputText = ""               // a fresh chip starts with an empty note
                inputFocused = true
                photoItems = []
            }
        }
    }
}

// MARK: - Voice capture

/// Streams microphone audio through Apple's Speech framework to dictate an
/// expense. Voice is just another way *in*: the final transcript is handed to
/// the same Gemini capture pipeline as typed text, so dictation gets multi-bill
/// extraction and every field for free. Speech-to-text runs on-device when the
/// model is available, otherwise Apple's server recognition.
@MainActor
final class VoiceCapture: ObservableObject {
    @Published var isRecording = false
    @Published var transcript = ""
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var onFinish: ((String) -> Void)?

    // Re-entrancy + lifecycle guards. `startEpoch` invalidates an in-flight
    // permission request when a newer start() or a stop() arrives (otherwise a
    // double-tap during the permission window would install two taps and crash).
    // `tapInstalled`/`sessionActive` make teardown exact regardless of how far
    // setup got. `sessionID` lets the recognition handler ignore stale callbacks.
    // `isFinishing` makes finish() idempotent.
    private var startEpoch = 0
    private var sessionID = 0
    private var tapInstalled = false
    private var sessionActive = false
    private var isFinishing = false

    private static let log = Logger(subsystem: "com.billmind.app", category: "VoiceCapture")

    /// Ask for permission, then begin listening. `onFinish` fires once with the
    /// final transcript when recording stops (or the recognizer finalizes).
    func start(onFinish: @escaping (String) -> Void) {
        guard !isRecording else { return }
        startEpoch &+= 1
        let epoch = startEpoch
        self.onFinish = onFinish
        transcript = ""
        errorMessage = nil

        // The permission callbacks fire on a background queue. We MUST NOT touch
        // this @MainActor instance from there, so we bridge them through async
        // helpers that capture no isolated state, then resume here on the
        // MainActor (this Task inherits MainActor isolation from `start`).
        Task { [weak self] in
            let speechGranted = await Self.requestSpeechAuthorization()
            let micGranted = await Self.requestMicPermission()
            // A newer start() or a stop() bumped the epoch → this attempt is stale.
            guard let self, self.startEpoch == epoch, !self.isRecording else { return }
            guard speechGranted else {
                self.fail("Allow Speech Recognition in Settings to add bills by voice.")
                return
            }
            guard micGranted else {
                self.fail("Allow Microphone access in Settings to add bills by voice.")
                return
            }
            self.beginSession()
        }
    }

    /// Stop listening and submit whatever was heard so far.
    func stop() {
        startEpoch &+= 1   // invalidate any permission request still in flight
        finish(submit: true)
    }

    // MARK: - Permissions
    //
    // `nonisolated static` so the completion closures capture only the
    // continuation (Sendable) — never `self` — which keeps them off the
    // MainActor and avoids the executor-isolation trap the SDK triggers by
    // calling them on a background queue.

    private nonisolated static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private nonisolated static func requestMicPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Session

    private func beginSession() {
        // The Simulator has no audio-input HAL: merely touching `audioEngine.inputNode`
        // spins up AURemoteIO, whose RPC times out and calls abort() (SIGABRT, deep in
        // AudioToolbox — uncatchable). Voice capture only works on a real device.
        #if targetEnvironment(simulator)
        fail("Voice input needs a real device — the Simulator has no microphone.")
        return
        #else
        guard let recognizer, recognizer.isAvailable else {
            fail("Speech recognition isn't available right now.")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement)   // .duckOthers is invalid with .record
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            sessionActive = true

            // Bail before touching the engine if this device has no input.
            guard session.isInputAvailable else {
                fail("No microphone input is available on this device.")
                return
            }

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            // Defensive: an invalid (0 Hz / 0-channel) format would make installTap throw.
            guard format.sampleRate > 0, format.channelCount > 0 else {
                fail("No microphone input is available on this device.")
                return
            }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            // The tap runs on the realtime audio thread. Capture `request`
            // directly (not `self`) so we never read MainActor state off-main.
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
                request.append(buffer)
            }
            tapInstalled = true

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            // Tag this session; the handler ignores callbacks from a finished one.
            sessionID &+= 1
            let generation = sessionID
            // The recognition handler is also invoked off-main. Pull plain values
            // out first, then hop to the MainActor to mutate state.
            task = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal ?? false
                let failed = error != nil
                Task { @MainActor in
                    guard let self, self.sessionID == generation else { return }
                    if let text { self.transcript = text }
                    if isFinal || failed { self.finish(submit: true) }
                }
            }
        } catch {
            Self.log.error("beginSession failed: \(error.localizedDescription, privacy: .public)")
            fail("Couldn't start recording — try again.")
        }
        #endif
    }

    /// Tear down exactly what was set up — driven by explicit flags, not a guess —
    /// and deliver the transcript at most once. Idempotent and re-entrancy-safe.
    private func finish(submit: Bool) {
        guard !isFinishing else { return }
        isFinishing = true
        defer { isFinishing = false }

        sessionID &+= 1   // invalidate any in-flight recognition callbacks
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if audioEngine.isRunning { audioEngine.stop() }
        request?.endAudio()
        let endingTask = task
        task = nil          // nil before cancel so a late callback sees no work
        endingTask?.cancel()
        request = nil
        if sessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            sessionActive = false
        }
        isRecording = false

        let finalText = transcript
        let callback = onFinish
        onFinish = nil
        if submit { callback?(finalText) }
    }

    private func fail(_ message: String) {
        errorMessage = message
        finish(submit: false)
    }
}

// MARK: - Preview

#if DEBUG
/// A self-contained render of the compose input bar with a staged chip + caption —
/// the visual proof of the compose tray. Mirrors `RecordView.stagedTray` / `inputBar`
/// composition (terra-ringed active chip, caption preview, ✕, note placeholder) at a
/// fixed width so a `#Preview` and the snapshot test exercise the exact styling.
struct ComposeBarPreview: View {
    /// Stub thumbnails so the preview/snapshot need no photo library.
    static func swatch(_ color: UIColor, label: String) -> UIImage {
        let size = CGSize(width: 120, height: 150)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            color.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.white,
                .font: UIFont.systemFont(ofSize: 14, weight: .semibold)]
            (label as NSString).draw(at: CGPoint(x: 12, y: 64), withAttributes: attrs)
        }
    }

    var chips: [StagedChip] = [
        StagedChip(image: swatch(.brown, label: "receipt"), caption: "the total was ¥240, lunch"),
        StagedChip(image: swatch(.gray, label: "taxi"), caption: ""),
    ]
    var activeID: UUID? { chips.first?.id }

    var body: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(chips.count > 1 ? "Tap a photo to note it" : "Pinned to this photo")
                    .font(SketchTheme.captionFont(11)).foregroundStyle(SketchTheme.dustyRose)
                HStack(spacing: 10) {
                    ForEach(chips) { chip in
                        let isActive = chip.id == activeID
                        let preview = chip.caption.trimmingCharacters(in: .whitespacesAndNewlines)
                        VStack(alignment: .leading, spacing: 4) {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: chip.image).resizable().scaledToFill()
                                    .frame(width: 56, height: 66)
                                    .clipShape(RoundedRectangle(cornerRadius: 9))
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16)).foregroundStyle(SketchTheme.mutedRed)
                                    .background(Circle().fill(SketchTheme.warmWhite).padding(2))
                                    .offset(x: 6, y: -6)
                            }
                            Text(preview.isEmpty ? "no note yet" : preview)
                                .font(SketchTheme.captionFont(10))
                                .foregroundStyle(preview.isEmpty ? SketchTheme.lightBrown : SketchTheme.sageGreen)
                                .lineLimit(1).frame(width: 64, alignment: .leading)
                        }
                        .padding(6).background(SketchTheme.warmWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13)
                            .stroke(isActive ? SketchTheme.dustyRose : SketchTheme.lightBrown.opacity(0.4),
                                    lineWidth: isActive ? 2 : 1.4))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 16)).foregroundStyle(SketchTheme.softBrown)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(SketchTheme.lightBrown, lineWidth: 1.5))
                Image(systemName: "mic.fill")
                    .font(.system(size: 15)).foregroundStyle(SketchTheme.softBrown)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(SketchTheme.lightBrown, lineWidth: 1.5))
                Text("the total was ¥240, lunch")
                    .font(SketchTheme.bodyFont(14)).foregroundStyle(SketchTheme.softBrown)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26)).foregroundStyle(SketchTheme.dustyRose)
            }
        }
        .padding(10).background(SketchTheme.warmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(SketchTheme.lightBrown, lineWidth: 1.8))
        .padding(.horizontal)
    }
}

#Preview("Compose bar — staged chip + caption") {
    VStack {
        Spacer()
        ComposeBarPreview()
    }
    .padding(.vertical, 40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(SketchTheme.cream)
}

/// A standalone host that renders the untangle review surface from a seeded
/// `.reviewing` coordinator (one fuse proposal + one duplicate group + one plain
/// card) — the visual proof of what the coordinator reviews. Mirrors the review
/// composition in `RecordView.session` without needing its private members.
private struct UntangleReviewPreviewHost: View {
    let coordinator: RecordCoordinator
    @State private var editTarget: EditTarget?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    OllieNoteBar(text: "I tidied these up — \(coordinator.groups.count) to look at.")
                        .padding(12)
                        .background(SketchTheme.warmWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(SketchTheme.lightBrown.opacity(0.35), lineWidth: 1.5))
                    ForEach(coordinator.groups) { group in
                        switch group {
                        case let .fuseProposed(groupID, resolved, sourceCardIDs, amountTrace, reason, _):
                            FuseProposalView(
                                groupID: groupID, resolved: resolved,
                                sourceCards: sourceCardIDs.compactMap { coordinator.session.card($0) },
                                amountTrace: amountTrace, reason: reason, coordinator: coordinator)
                        case let .flaggedDuplicate(groupID, memberCardIDs, survivorID, tier, reason):
                            DuplicateGroupView(
                                groupID: groupID,
                                members: memberCardIDs.compactMap { coordinator.session.card($0) },
                                survivorID: survivorID, tier: tier, reason: reason, coordinator: coordinator)
                        }
                    }
                    ForEach(coordinator.plainReviewCards) { card in
                        AgentCardView(card: card, coordinator: coordinator) { _ in }
                    }
                }
                .padding(.horizontal).padding(.top, 8)
            }
            VStack(spacing: 6) {
                Text("\(coordinator.groups.count) groups to confirm · pre-set to the safe choice")
                    .font(SketchTheme.captionFont(12)).foregroundStyle(SketchTheme.lightBrown)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {} label: {
                    let n = coordinator.plainReviewCards.count
                    Label("Save all to trip · \(n) bill\(n == 1 ? "" : "s")",
                          systemImage: "tray.and.arrow.down.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(HandDrawnButtonStyle(filled: true))
            }
            .padding(.horizontal).padding(.bottom, 8)
        }
        .paperBackground()
    }
}

#Preview("Untangle review") {
    let container: ModelContainer
    do {
        container = try ModelContainer(
            for: Schema(BillMindSchemaV2.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    } catch {
        fatalError("preview: \(error)")
    }
    let coordinator = RecordCoordinator.previewReviewing(modelContext: container.mainContext)
    return UntangleReviewPreviewHost(coordinator: coordinator)
}
#endif
