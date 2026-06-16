import SwiftUI
import SwiftData

struct MindsView: View {
    @EnvironmentObject private var auth: AuthSession
    @Query(sort: \Journal.createdDate, order: .reverse) private var journals: [Journal]

    @State private var selectedJournalId: UUID?

    private var selectedJournal: Journal? {
        guard let id = selectedJournalId else { return nil }
        return journals.first(where: { $0.id == id })
    }
    @State private var isGenerating = false
    @State private var generatedImage: UIImage?
    @State private var errorMessage: String?
    @State private var showShareSheet = false
    @State private var savedMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    AnimalMascotView(animal: .owl, size: 64, animated: !isGenerating)

                    Text("Generate a beautiful timeline\nof your travel expenses")
                        .font(SketchTheme.bodyFont(15))
                        .foregroundStyle(SketchTheme.lightBrown)
                        .multilineTextAlignment(.center)

                    // Journal picker
                    journalPicker

                    // Generate / Regenerate button
                    Button { generateMind() } label: {
                        HStack {
                            if isGenerating {
                                ProgressView().tint(.white).scaleEffect(0.8)
                            } else {
                                Image(systemName: generatedImage == nil ? "sparkles" : "arrow.clockwise")
                            }
                            Text(isGenerating ? "Generating..." : generatedImage == nil ? "Generate Mind" : "Regenerate")
                                .font(SketchTheme.headlineFont(18))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(SketchTheme.primaryGradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: SketchTheme.dustyRose.opacity(0.3), radius: 6, y: 3)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedJournal == nil || selectedJournal?.billCount == 0 || isGenerating)
                    .opacity(selectedJournal == nil || selectedJournal?.billCount == 0 ? 0.5 : 1)

                    if let error = errorMessage {
                        Text(error)
                            .font(SketchTheme.captionFont(12))
                            .foregroundStyle(SketchTheme.mutedRed)
                    }

                    if let msg = savedMessage {
                        Text(msg)
                            .font(SketchTheme.captionFont(12))
                            .foregroundStyle(SketchTheme.sageGreen)
                    }

                    // Generated image + actions
                    if let image = generatedImage {
                        generatedImageView(image)
                    }

                    // Saved minds gallery
                    if let journal = selectedJournal {
                        savedMindsGallery(for: journal)
                    }
                }
                .padding()
            }
            .paperBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Text("Minds")
                            .font(SketchTheme.titleFont(24))
                            .foregroundStyle(SketchTheme.softBrown)
                        AnimalMascotView(animal: .owl, size: 24)
                    }
                }
            }
            .onAppear {
                if selectedJournalId == nil, let first = journals.first {
                    selectedJournalId = first.id
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let image = generatedImage {
                    ShareSheet(items: [image])
                }
            }
        }
    }

    // MARK: - Journal Picker

    private var journalPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select a Trip")
                .font(SketchTheme.captionFont())
                .foregroundStyle(SketchTheme.lightBrown)

            if journals.isEmpty {
                Text("No trips yet")
                    .font(SketchTheme.bodyFont(14))
                    .foregroundStyle(SketchTheme.lightBrown)
            } else {
                ForEach(journals) { journal in
                    Button {
                        selectedJournalId = journal.id
                        generatedImage = nil
                        savedMessage = nil
                    } label: {
                        HStack(spacing: 10) {
                            Image(journal.coverAnimal.imageName)
                                .resizable().scaledToFill()
                                .frame(width: 36, height: 36)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(journal.name)
                                    .font(SketchTheme.headlineFont(15))
                                    .foregroundStyle(SketchTheme.softBrown)
                                HStack(spacing: 4) {
                                    Text("\(journal.billCount) bills · \(journal.currency)")
                                        .font(SketchTheme.captionFont(11))
                                        .foregroundStyle(SketchTheme.lightBrown)
                                    if !savedMindPaths(for: journal).isEmpty {
                                        Text("· \(savedMindPaths(for: journal).count) minds")
                                            .font(SketchTheme.captionFont(11))
                                            .foregroundStyle(SketchTheme.sageGreen)
                                    }
                                }
                            }
                            Spacer()
                            if selectedJournalId == journal.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(SketchTheme.sageGreen)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sketchCard()
    }

    // MARK: - Generated Image View

    @ViewBuilder
    private func generatedImageView(_ image: UIImage) -> some View {
        VStack(spacing: 12) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: SketchTheme.paperShadow, radius: 8, y: 4)

            // Action buttons
            HStack(spacing: 10) {
                Button { saveToJournal(image) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                        Text("Save")
                            .font(SketchTheme.headlineFont(13))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(SketchTheme.sageGreen.opacity(0.15))
                    .foregroundStyle(SketchTheme.sageGreen)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Button { saveToPhotos(image) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "photo")
                        Text("Photos")
                            .font(SketchTheme.headlineFont(13))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(SketchTheme.warmWhite)
                    .foregroundStyle(SketchTheme.softBrown)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(SketchTheme.lightBrown.opacity(0.5), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Button { showShareSheet = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                            .font(SketchTheme.headlineFont(13))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(SketchTheme.primaryGradient)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Saved Minds Gallery

    @ViewBuilder
    private func savedMindsGallery(for journal: Journal) -> some View {
        if let path = savedMindPaths(for: journal).first, let image = loadImage(path) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Saved Mind")
                    .font(SketchTheme.headlineFont(16))
                    .foregroundStyle(SketchTheme.softBrown)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: SketchTheme.paperShadow, radius: 4, y: 2)
                    .contextMenu {
                        Button {
                            showShareSheet = true
                            generatedImage = image
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            saveToPhotos(image)
                        } label: {
                            Label("Save to Photos", systemImage: "photo")
                        }
                        Button(role: .destructive) {
                            deleteMind(path: path, journal: journal)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            .sketchCard()
        }
    }

    // MARK: - Mind Storage

    private func mindDirectory(for journal: Journal) -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("minds/\(journal.id.uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func savedMindPaths(for journal: Journal) -> [String] {
        let path = mindDirectory(for: journal).appendingPathComponent("mind.jpg").path
        if FileManager.default.fileExists(atPath: path) {
            return [path]
        }
        return []
    }

    private func loadImage(_ path: String) -> UIImage? {
        UIImage(contentsOfFile: path)
    }

    private func saveToJournal(_ image: UIImage) {
        guard let journal = selectedJournal else { return }
        let dir = mindDirectory(for: journal)
        let fileURL = dir.appendingPathComponent("mind.jpg")
        // Overwrite previous mind
        if let data = image.jpegData(compressionQuality: 0.9) {
            try? data.write(to: fileURL)
            savedMessage = "Mind saved!"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedMessage = nil }
        }
    }

    private func deleteMind(path: String, journal: Journal) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private func saveToPhotos(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        savedMessage = "Saved to Photos!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedMessage = nil }
    }

    // MARK: - Generate Mind

    /// Server-side generation: the BillMind server builds the timeline and calls
    /// Gemini image-gen with its own key, so the client never needs an API key.
    /// (The AI is the product — every smart feature runs through the server.)
    private func generateMind() {
        guard let journal = selectedJournal, !journal.liveBills.isEmpty else { return }
        guard let tripID = journal.serverID else {
            errorMessage = "This trip is still syncing — try again in a moment."
            return
        }

        isGenerating = true
        errorMessage = nil
        savedMessage = nil

        Task {
            do {
                let response = try await auth.client.generateMind(tripID: tripID)
                guard let data = Data(base64Encoded: response.imageBase64),
                      let image = UIImage(data: data) else {
                    await MainActor.run {
                        errorMessage = "Couldn't read the generated image. Try again."
                        isGenerating = false
                    }
                    return
                }
                await MainActor.run {
                    generatedImage = image
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? "Couldn't generate a Mind right now. Please try again."
                    isGenerating = false
                }
            }
        }
    }
}
