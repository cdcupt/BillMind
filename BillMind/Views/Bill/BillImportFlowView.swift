import SwiftUI
import SwiftData
import PhotosUI

struct BillImportFlowView: View {
    let journal: Journal
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    enum Step { case pickPhotos, recognizing, review }

    @State private var currentStep: Step = .pickPhotos
    @State private var selectedImages: [UIImage] = []
    @State private var draftBills: [DraftBill] = []
    @State private var processingIndex = 0
    @State private var errorMessage: String?

    // Settings
    @Query private var allSettings: [AppSettings]
    private var settings: AppSettings? { allSettings.first }

    var body: some View {
        NavigationStack {
            Group {
                switch currentStep {
                case .pickPhotos:
                    photoPickerStep
                case .recognizing:
                    recognizingStep
                case .review:
                    reviewStep
                }
            }
            .paperBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(SketchTheme.dustyRose)
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(stepTitle)
                            .font(SketchTheme.headlineFont(18))
                            .foregroundStyle(SketchTheme.softBrown)
                        Text(stepSubtitle)
                            .font(SketchTheme.captionFont(11))
                            .foregroundStyle(SketchTheme.lightBrown)
                    }
                }
            }
        }
    }

    private var stepTitle: String {
        switch currentStep {
        case .pickPhotos: return "Add Bills"
        case .recognizing: return "Recognizing"
        case .review: return "Review"
        }
    }

    private var stepSubtitle: String {
        switch currentStep {
        case .pickPhotos: return "Step 1 of 3"
        case .recognizing: return "Step 2 of 3"
        case .review: return "Step 3 of 3"
        }
    }

    // MARK: - Step 1: Photo Picker

    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false

    private var photoPickerStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Step indicator
                StepIndicator(current: 1, total: 3)

                // Camera & Gallery buttons
                HStack(spacing: 12) {
                    Button { showCamera = true } label: {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Camera")
                                .font(SketchTheme.headlineFont(16))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(SketchTheme.primaryGradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    PhotosPicker(selection: $photoPickerItems, maxSelectionCount: 10, matching: .images) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                            Text("Gallery")
                                .font(SketchTheme.headlineFont(16))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(SketchTheme.warmWhite)
                        .foregroundStyle(SketchTheme.softBrown)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(SketchTheme.lightBrown, lineWidth: 1.5)
                        )
                    }
                }

                // Selected photos grid
                if !selectedImages.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Selected (\(selectedImages.count))")
                                .font(SketchTheme.captionFont())
                                .foregroundStyle(SketchTheme.lightBrown)
                            Spacer()
                            Button("Clear") {
                                selectedImages.removeAll()
                            }
                            .font(SketchTheme.captionFont(12))
                            .foregroundStyle(SketchTheme.mutedRed)
                        }

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(selectedImages.indices, id: \.self) { index in
                                Image(uiImage: selectedImages[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(alignment: .topTrailing) {
                                        Button {
                                            selectedImages.remove(at: index)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.white, SketchTheme.mutedRed)
                                                .font(.system(size: 20))
                                        }
                                        .padding(4)
                                    }
                            }
                        }
                    }
                    .sketchCard()

                    // Start recognition button
                    Button {
                        startRecognition()
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Start Recognition")
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
                } else {
                    EmptyStateView(
                        animal: .owl,
                        title: "No photos selected",
                        subtitle: "Take a photo or pick from gallery to scan bills"
                    )
                }
            }
            .padding()
        }
        .sheet(isPresented: $showCamera) {
            CameraPickerView { image in
                selectedImages.append(image)
            }
        }
        .onChange(of: photoPickerItems) { _, items in
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        selectedImages.append(image)
                    }
                }
                photoPickerItems.removeAll()
            }
        }
    }

    // MARK: - Step 2: Recognizing

    private var recognizingStep: some View {
        ScrollView {
        VStack(spacing: 20) {
            StepIndicator(current: 2, total: 3)

            AnimalMascotView(animal: .owl, size: 72, animated: true)

            Text("Hoot is reading your bills...")
                .font(SketchTheme.headlineFont(18))
                .foregroundStyle(SketchTheme.lightBrown)

            // Progress
            VStack(spacing: 12) {
                ForEach(selectedImages.indices, id: \.self) { index in
                    HStack(spacing: 12) {
                        Image(uiImage: selectedImages[index])
                            .resizable().scaledToFill()
                            .frame(width: 50, height: 66)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Photo \(index + 1)")
                                .font(SketchTheme.headlineFont(14))
                                .foregroundStyle(SketchTheme.softBrown)

                            if index < processingIndex {
                                // Completed
                                if let draft = draftBills[safe: countCompleted(before: index)] {
                                    Text(draft.merchant.isEmpty ? "Recognized" : draft.merchant)
                                        .font(SketchTheme.captionFont(12))
                                        .foregroundStyle(SketchTheme.sageGreen)
                                }
                            } else if index == processingIndex {
                                Text("Analyzing...")
                                    .font(SketchTheme.captionFont(12))
                                    .foregroundStyle(SketchTheme.warmOrange)
                            } else {
                                Text("Waiting")
                                    .font(SketchTheme.captionFont(12))
                                    .foregroundStyle(SketchTheme.lightBrown)
                            }

                            ProgressView(value: progressFor(index: index))
                                .tint(index < processingIndex ? SketchTheme.sageGreen :
                                      index == processingIndex ? SketchTheme.warmOrange :
                                      SketchTheme.lightBrown.opacity(0.3))
                        }
                    }
                    .sketchCard(cornerRadius: 14)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(SketchTheme.captionFont(12))
                    .foregroundStyle(SketchTheme.mutedRed)
                    .padding()
            }

            Spacer(minLength: 40)

            Text("Using: \(settings?.selectedProvider.displayName ?? "Gemini")")
                .font(SketchTheme.captionFont())
                .foregroundStyle(SketchTheme.lightBrown)
        }
        .padding()
        }
        .padding()
    }

    private func countCompleted(before index: Int) -> Int {
        min(index, draftBills.count - 1)
    }

    private func progressFor(index: Int) -> Double {
        if index < processingIndex { return 1.0 }
        if index == processingIndex { return 0.5 }
        return 0.0
    }

    // MARK: - Step 3: Review

    private var reviewStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                StepIndicator(current: 3, total: 3)

                AnimalMascotView(animal: .rabbit, size: 48)
                Text("\(draftBills.count) bill(s) recognized!")
                    .font(SketchTheme.headlineFont(18))
                    .foregroundStyle(SketchTheme.sageGreen)

                // Editable draft bills
                ForEach($draftBills) { $draft in
                    DraftBillCard(draft: $draft) {
                        retryRecognition(for: draft.id)
                    }
                }

                // Save all button
                Button {
                    saveAllBills()
                } label: {
                    HStack {
                        Image(systemName: "checkmark")
                        Text("Save All Bills")
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
                .disabled(draftBills.isEmpty)
            }
            .padding()
        }
    }

    // MARK: - Actions

    private func startRecognition() {
        currentStep = .recognizing
        processingIndex = 0
        draftBills.removeAll()
        errorMessage = nil

        let provider = settings?.selectedProvider ?? .gemini
        let model = (settings?.customModel.isEmpty ?? true) ? provider.defaultModel : (settings?.customModel ?? provider.defaultModel)
        Task {
            let service = AIService()
            for (index, image) in selectedImages.enumerated() {
                processingIndex = index
                do {
                    let key = await getAPIKey()
                    guard !key.isEmpty else { throw AIError.noAPIKey }
                    let result = try await service.recognizeBill(
                        images: [image],
                        provider: provider,
                        model: model,
                        apiKey: key
                    )
                    let draft = DraftBill(
                        sourceImage: image,
                        merchant: result.merchant ?? "",
                        amount: result.parsedAmount?.formatted2 ?? "",
                        date: result.parsedDate ?? Date(),
                        category: result.parsedCategory ?? .misc,
                        currency: result.currency ?? journal.currency,
                        note: result.notes ?? "",
                        lineItems: result.toBillLineItems()
                    )
                    draftBills.append(draft)
                } catch {
                    // Create a draft with error, user can fill manually or retry
                    let draft = DraftBill(
                        sourceImage: image,
                        merchant: "",
                        amount: "",
                        date: Date(),
                        category: .misc,
                        currency: journal.currency,
                        note: "Recognition failed: \(error.localizedDescription)",
                        lineItems: [],
                        failed: true
                    )
                    draftBills.append(draft)
                    errorMessage = "Photo \(index + 1): \(error.localizedDescription)"
                }
            }
            processingIndex = selectedImages.count
            currentStep = .review
        }
    }

    @MainActor
    private func getAPIKey() -> String {
        return settings?.apiKey ?? ""
    }

    private func retryRecognition(for draftId: UUID) {
        guard let index = draftBills.firstIndex(where: { $0.id == draftId }) else { return }
        let image = draftBills[index].sourceImage

        let provider = settings?.selectedProvider ?? .gemini
        let model = (settings?.customModel.isEmpty ?? true) ? provider.defaultModel : (settings?.customModel ?? provider.defaultModel)

        draftBills[index].failed = false
        draftBills[index].note = "Retrying..."

        Task {
            let service = AIService()
            let key = await getAPIKey()
            do {
                let result = try await service.recognizeBill(
                    images: [image],
                    provider: provider,
                    model: model,
                    apiKey: key
                )
                await MainActor.run {
                    draftBills[index].merchant = result.merchant ?? ""
                    draftBills[index].amount = result.parsedAmount?.formatted2 ?? ""
                    draftBills[index].date = result.parsedDate ?? Date()
                    draftBills[index].category = result.parsedCategory ?? .misc
                    draftBills[index].currency = result.currency ?? journal.currency
                    draftBills[index].note = result.notes ?? ""
                    draftBills[index].lineItems = result.toBillLineItems()
                    draftBills[index].failed = false
                }
            } catch {
                await MainActor.run {
                    draftBills[index].note = "Retry failed: \(error.localizedDescription)"
                    draftBills[index].failed = true
                }
            }
        }
    }

    private func saveAllBills() {
        for draft in draftBills {
            guard let amount = Decimal(string: draft.amount), amount > 0 else { continue }

            let bill = BillRecord(
                date: draft.date,
                amount: amount,
                originalCurrency: draft.currency,
                category: draft.category,
                merchant: draft.merchant.isEmpty ? nil : draft.merchant,
                note: draft.note.isEmpty ? nil : draft.note,
                status: .confirmed
            )
            bill.lineItems = draft.lineItems
            bill.aiProvider = settings?.selectedProvider
            bill.journal = journal

            // Save image
            if let data = draft.sourceImage.jpegData(compressionQuality: 0.7) {
                let filename = UUID().uuidString + ".jpg"
                let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let fileURL = dir.appendingPathComponent(filename)
                try? data.write(to: fileURL)
                bill.imagePaths = [filename]
            }

            modelContext.insert(bill)
        }
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Draft Bill Model

struct DraftBill: Identifiable {
    let id = UUID()
    var sourceImage: UIImage
    var merchant: String
    var amount: String
    var date: Date
    var category: BillCategory
    var currency: String
    var note: String
    var lineItems: [BillLineItem]
    var failed: Bool = false
}

// MARK: - Draft Bill Card

struct DraftBillCard: View {
    @Binding var draft: DraftBill
    var onRetry: (() -> Void)? = nil
    @State private var showZoom = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Image + merchant + amount
            HStack(alignment: .top, spacing: 12) {
                Button { showZoom = true } label: {
                    Image(uiImage: draft.sourceImage)
                        .resizable().scaledToFill()
                        .frame(width: 60, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    TextField("Merchant", text: $draft.merchant)
                        .font(SketchTheme.headlineFont(16))
                        .textFieldStyle(.plain)
                    TextField("0.00", text: $draft.amount)
                        .font(SketchTheme.amountFont(28))
                        .foregroundStyle(SketchTheme.dustyRose)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.plain)
                }

                Spacer()
            }

            // Category picker (compact)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(BillCategory.allCases) { cat in
                        Button {
                            draft.category = cat
                        } label: {
                            HStack(spacing: 4) {
                                Image(cat.icon)
                                    .resizable().scaledToFill()
                                    .frame(width: 16, height: 16)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                Text(cat.englishName)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(draft.category == cat ? cat.color.opacity(0.15) : SketchTheme.cream)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(draft.category == cat ? cat.color.opacity(0.4) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(SketchTheme.softBrown)
                    }
                }
            }

            // Date
            DatePicker("", selection: $draft.date, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(SketchTheme.dustyRose)

            // Note (editable)
            TextField("Add a note...", text: $draft.note, axis: .vertical)
                .font(SketchTheme.bodyFont(13))
                .foregroundStyle(SketchTheme.softBrown)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .padding(8)
                .background(SketchTheme.cream)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Line items summary
            if !draft.lineItems.isEmpty {
                Text("\(draft.lineItems.count) line items")
                    .font(SketchTheme.captionFont(11))
                    .foregroundStyle(SketchTheme.lightBrown)
            }

            // Retry button for failed recognition
            if draft.failed, let onRetry = onRetry {
                Button {
                    onRetry()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry Recognition")
                            .font(SketchTheme.headlineFont(14))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(SketchTheme.warmOrange.opacity(0.15))
                    .foregroundStyle(SketchTheme.warmOrange)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .sketchCard()
        .fullScreenCover(isPresented: $showZoom) {
            ZoomableImageView(image: draft.sourceImage)
        }
    }
}

// MARK: - Step Indicator

struct StepIndicator: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...total, id: \.self) { step in
                Circle()
                    .fill(step <= current ? SketchTheme.dustyRose : SketchTheme.lightBrown.opacity(0.3))
                    .frame(width: 10, height: 10)
            }
        }
    }
}

// MARK: - Camera Picker

struct CameraPickerView: UIViewControllerRepresentable {
    var onImagePicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        #if targetEnvironment(simulator)
        picker.sourceType = .photoLibrary
        #else
        picker.sourceType = .camera
        #endif
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView
        init(_ parent: CameraPickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
