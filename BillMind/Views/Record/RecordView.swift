import SwiftUI
import SwiftData
import PhotosUI
import Speech
import AVFoundation
import os

/// The Record tab: pick a journal, then type a phrase (or pick photos) and the
/// agent turns each into an editable bill card you confirm. Text capture needs no
/// AI or API key.
struct RecordView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: AuthSession
    @EnvironmentObject private var sync: SyncCoordinator
    @Query(filter: #Predicate<Journal> { !$0.isDeleted },
           sort: \Journal.createdDate, order: .reverse) private var journals: [Journal]

    @State private var coordinator: RecordCoordinator?
    @State private var selectedJournalID: UUID?
    @State private var inputText = ""
    @State private var editTarget: EditTarget?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showNewJournal = false
    @State private var showTrips = false
    @StateObject private var voice = VoiceCapture()
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
            inputBar(coordinator)
        }
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
        HStack(spacing: 8) {
            PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 16)).foregroundStyle(SketchTheme.softBrown)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(SketchTheme.lightBrown, lineWidth: 1.5))
            }
            .accessibilityIdentifier("record-photos")

            micButton(coordinator)

            TextField(voice.isRecording ? "Listening…" : "Tell Ollie about a bill…", text: $inputText)
                .textFieldStyle(.plain)
                .submitLabel(.send)
                .focused($inputFocused)
                .disabled(voice.isRecording)
                .onSubmit { send(coordinator) }
                .accessibilityIdentifier("record-input")

            Button { send(coordinator) } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26)).foregroundStyle(SketchTheme.dustyRose)
            }
            .disabled(voice.isRecording)   // avoid submitting partial text mid-dictation
            .accessibilityIdentifier("record-send")
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

    /// Start dictation, or stop it and hand the final transcript to the AI.
    private func toggleVoice(_ coordinator: RecordCoordinator) {
        if voice.isRecording {
            voice.stop()
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
