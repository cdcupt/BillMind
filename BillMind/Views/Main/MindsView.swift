import SwiftUI
import SwiftData

struct MindsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Journal.createdDate, order: .reverse) private var journals: [Journal]
    @Query private var allSettings: [AppSettings]
    private var settings: AppSettings? { allSettings.first }

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
    @State private var showConsentSheet = false

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
            .sheet(isPresented: $showConsentSheet) {
                AIDataConsentView(provider: settings?.selectedProvider ?? .gemini) {
                    settings?.hasConsentedToAIDataSharing = true
                    try? modelContext.save()
                    generateMind()
                } onDecline: {
                    // User declined — no action
                }
            }
        }
    }

    // MARK: - Journal Picker

    private var journalPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select a Journal")
                .font(SketchTheme.captionFont())
                .foregroundStyle(SketchTheme.lightBrown)

            if journals.isEmpty {
                Text("No journals yet")
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

    private func generateMind() {
        guard let journal = selectedJournal, !journal.bills.isEmpty else { return }

        let isDemoMode = settings?.demoMode ?? false
        let apiKey = settings?.apiKey ?? ""

        if !isDemoMode {
            guard settings?.hasConsentedToAIDataSharing == true else {
                showConsentSheet = true
                return
            }
            guard !apiKey.isEmpty else {
                errorMessage = "Please set your API key in Settings first"
                return
            }
            guard settings?.selectedProvider == .gemini else {
                errorMessage = "Minds requires Google Gemini. Please switch provider in Settings."
                return
            }
        }

        isGenerating = true
        errorMessage = nil
        savedMessage = nil

        // Demo mode: generate a placeholder infographic
        if isDemoMode {
            Task {
                try? await Task.sleep(for: .seconds(1))
                await MainActor.run {
                    generatedImage = DemoData.generatePlaceholderMind(journal: journal)
                    isGenerating = false
                }
            }
            return
        }

        let currencySymbol = CurrencyInfo.popular.first(where: { $0.code == journal.currency })?.symbol ?? journal.currency
        let billsSorted = journal.bills.sorted { $0.date < $1.date }
        var timeline = "Journal: \(journal.name)\nCurrency: \(journal.currency)\n\nBill Timeline:\n"
        for bill in billsSorted {
            let dateStr = bill.date.formatted(as: "MMM d")
            let merchant = bill.merchant ?? bill.category.englishName
            timeline += "- \(dateStr): \(merchant) — \(currencySymbol)\(bill.amount.formatted2) (\(bill.category.englishName))\n"
        }
        timeline += "\nTotal: \(currencySymbol)\(journal.totalAmount.formattedCurrency)"

        let prompt = """
        Create a beautiful, artistic sketch-style infographic image for a travel expense journal.

        The image should be:
        - Hand-drawn/sketch style with warm colors (cream, teal, dusty rose, sage green)
        - A vertical timeline layout showing expenses chronologically
        - Each expense shown as a cute illustrated card on the timeline
        - Include small cute icons for each category (food=bowl, transport=car, hotel=bed, shopping=bag, etc.)
        - The journal title "\(journal.name)" at the top in a decorative hand-lettered style
        - Total amount at the bottom in a highlighted circle
        - Decorative elements: small stars, dots, doodle borders
        - Warm, cozy, journal/planner aesthetic
        - NO real text that needs to be readable — use decorative/abstract text shapes
        - The overall feel should be like a page from a beautiful travel journal

        Here is the expense data to visualize:
        \(timeline)
        """

        Task {
            do {
                let imageModel = settings?.imageModel.isEmpty == false ? settings!.imageModel : "gemini-3.1-flash-image-preview"
                let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(imageModel):generateContent")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(apiKey, forHTTPHeaderField: "X-goog-api-key")
                request.timeoutInterval = 120

                let body: [String: Any] = [
                    "contents": [["parts": [["text": prompt]]]],
                    "generationConfig": ["responseModalities": ["TEXT", "IMAGE"]]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await URLSession.shared.data(for: request)
                let httpResponse = response as? HTTPURLResponse

                guard (200...299).contains(httpResponse?.statusCode ?? 0) else {
                    let msg = parseError(data)
                    throw AIError.httpError(httpResponse?.statusCode ?? 0, msg)
                }

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let content = candidates.first?["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]] else {
                    throw AIError.invalidResponse("No candidates")
                }

                var foundImage: UIImage?
                for part in parts {
                    if let inlineData = part["inlineData"] as? [String: Any],
                       let base64 = inlineData["data"] as? String,
                       let imageData = Data(base64Encoded: base64),
                       let uiImage = UIImage(data: imageData) {
                        foundImage = uiImage
                        break
                    }
                }

                await MainActor.run {
                    if let img = foundImage {
                        generatedImage = img
                    } else {
                        errorMessage = "AI didn't return an image. Try again."
                    }
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }

    private func parseError(_ data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let msg = error["message"] as? String else {
            return "Unknown error"
        }
        return msg
    }
}
