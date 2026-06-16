import SwiftUI
import SwiftData
import PhotosUI
import Speech
import AVFoundation

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

            micButton(coordinator)

            TextField(voice.isRecording ? "Listening…" : "Tell Mochi about a bill…", text: $inputText)
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

    /// Ask for permission, then begin listening. `onFinish` fires once with the
    /// final transcript when recording stops (or the recognizer finalizes).
    func start(onFinish: @escaping (String) -> Void) {
        self.onFinish = onFinish
        transcript = ""
        errorMessage = nil

        SFSpeechRecognizer.requestAuthorization { speechAuth in
            AVAudioApplication.requestRecordPermission { micGranted in
                DispatchQueue.main.async {
                    guard speechAuth == .authorized else {
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
        }
    }

    /// Stop listening and submit whatever was heard so far.
    func stop() {
        finish(submit: true)
    }

    // MARK: - Private

    private func beginSession() {
        guard let recognizer, recognizer.isAvailable else {
            fail("Speech recognition isn't available right now.")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                DispatchQueue.main.async {
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        if result.isFinal { self.finish(submit: true) }
                    } else if error != nil {
                        // endAudio() during stop() surfaces here — submit what we have.
                        self.finish(submit: true)
                    }
                }
            }
        } catch {
            fail("Couldn't start recording — try again.")
        }
    }

    private func finish(submit: Bool) {
        let wasActive = isRecording || task != nil
        if wasActive {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            request?.endAudio()
            task?.cancel()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        request = nil
        task = nil
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
