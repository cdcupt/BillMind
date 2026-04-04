import SwiftUI
import SwiftData

struct MindsView: View {
    @Query(sort: \Journal.createdDate, order: .reverse) private var journals: [Journal]
    @Query private var allSettings: [AppSettings]
    private var settings: AppSettings? { allSettings.first }

    @State private var selectedJournal: Journal?
    @State private var isGenerating = false
    @State private var generatedImage: UIImage?
    @State private var errorMessage: String?
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header mascot
                    AnimalMascotView(animal: .owl, size: 64, animated: !isGenerating)

                    Text("Generate a beautiful timeline\nof your travel expenses")
                        .font(SketchTheme.bodyFont(15))
                        .foregroundStyle(SketchTheme.lightBrown)
                        .multilineTextAlignment(.center)

                    // Journal picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select a Journal")
                            .font(SketchTheme.captionFont())
                            .foregroundStyle(SketchTheme.lightBrown)

                        if journals.isEmpty {
                            Text("No journals yet — create one first")
                                .font(SketchTheme.bodyFont(14))
                                .foregroundStyle(SketchTheme.lightBrown)
                                .padding(.vertical, 12)
                        } else {
                            ForEach(journals) { journal in
                                Button {
                                    selectedJournal = journal
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
                                            Text("\(journal.billCount) bills · \(journal.currency)")
                                                .font(SketchTheme.captionFont(11))
                                                .foregroundStyle(SketchTheme.lightBrown)
                                        }
                                        Spacer()
                                        if selectedJournal?.id == journal.id {
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

                    // Generate button
                    Button {
                        generateMind()
                    } label: {
                        HStack {
                            if isGenerating {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(isGenerating ? "Generating..." : "Generate Mind")
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

                    // Generated image
                    if let image = generatedImage {
                        VStack(spacing: 12) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .shadow(color: SketchTheme.paperShadow, radius: 8, y: 4)

                            HStack(spacing: 12) {
                                Button {
                                    saveToPhotos(image)
                                } label: {
                                    HStack {
                                        Image(systemName: "square.and.arrow.down")
                                        Text("Save to Photos")
                                            .font(SketchTheme.headlineFont(14))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(SketchTheme.warmWhite)
                                    .foregroundStyle(SketchTheme.softBrown)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(SketchTheme.lightBrown, lineWidth: 1.5)
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    showShareSheet = true
                                } label: {
                                    HStack {
                                        Image(systemName: "square.and.arrow.up")
                                        Text("Share")
                                            .font(SketchTheme.headlineFont(14))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(SketchTheme.primaryGradient)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
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
            .sheet(isPresented: $showShareSheet) {
                if let image = generatedImage {
                    ShareSheet(items: [image])
                }
            }
        }
    }

    // MARK: - Generate Mind

    private func generateMind() {
        guard let journal = selectedJournal, !journal.bills.isEmpty else { return }
        guard let apiKey = settings?.apiKey, !apiKey.isEmpty else {
            errorMessage = "Please set your API key in Settings first"
            return
        }

        isGenerating = true
        errorMessage = nil
        generatedImage = nil

        let provider = settings?.selectedProvider ?? .gemini
        let model = settings?.customModel.isEmpty == false ? settings!.customModel : provider.defaultModel

        // Build bill timeline description
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
                let service = AIService()

                // Use Gemini image generation
                let imageModel = "gemini-2.5-flash-image"
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
                    let errorMsg = parseError(data)
                    throw AIError.httpError(httpResponse?.statusCode ?? 0, errorMsg)
                }

                // Parse image from response
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

    private func saveToPhotos(_ image: UIImage) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    }
}
