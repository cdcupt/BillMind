import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var settings: AppSettings?
    @State private var selectedProvider: AIProvider = .gemini
    @State private var customModel = ""
    @State private var imageModel = ""
    @State private var apiKey = ""
    @State private var showAPIKeyEditor = false
    @State private var defaultCurrency = "CNY"
    @State private var showExportShare = false
    @State private var exportFileURL: URL?
    @State private var showImportPicker = false
    @State private var importMessage: String?
    @State private var isTesting = false
    @State private var testResult: Bool?
    @State private var testErrorMessage: String?
    @State private var showConsentSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Demo Mode Section
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("Demo Mode")
                        settingsCard {
                            settingsRow("Demo Mode") {
                                Toggle("", isOn: Binding(
                                    get: { settings?.demoMode ?? false },
                                    set: {
                                        settings?.demoMode = $0
                                        try? modelContext.save()
                                    }
                                ))
                                .tint(SketchTheme.sageGreen)
                                .labelsHidden()
                            }
                        }
                        Text("Try all features without an API key. Uses sample bill data and a placeholder Mind image.")
                            .font(.system(size: 12, design: .serif))
                            .foregroundStyle(SketchTheme.lightBrown)
                            .padding(.horizontal, 4)
                    }

                    // AI Provider Section (merged with Connection)
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("AI Provider")
                        settingsCard {
                            settingsRow("Provider") {
                                Picker("", selection: $selectedProvider) {
                                    ForEach(AIProvider.allCases) { provider in
                                        Text(provider.displayName).tag(provider)
                                    }
                                }
                                .tint(SketchTheme.dustyRose)
                            }
                            settingsRow("Recognition") {
                                Menu {
                                    ForEach(selectedProvider.availableModels, id: \.self) { model in
                                        Button {
                                            customModel = model
                                            saveSettings()
                                        } label: {
                                            let name = AIProvider.shortName(for: model)
                                            let price = AIProvider.priceLabel(for: model)
                                            Text(price.isEmpty ? name : "\(name) — \(price)")
                                        }
                                    }
                                } label: {
                                    Text(AIProvider.shortName(for: customModel))
                                        .font(SketchTheme.captionFont())
                                        .foregroundStyle(SketchTheme.dustyRose)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 10))
                                        .foregroundStyle(SketchTheme.lightBrown)
                                }
                            }
                            settingsRow("Image Gen") {
                                Menu {
                                    ForEach(selectedProvider.availableImageModels, id: \.self) { model in
                                        Button {
                                            imageModel = model
                                            saveSettings()
                                        } label: {
                                            let name = AIProvider.shortName(for: model)
                                            let price = AIProvider.priceLabel(for: model)
                                            Text(price.isEmpty ? name : "\(name) — \(price)")
                                        }
                                    }
                                } label: {
                                    Text(AIProvider.shortName(for: imageModel))
                                        .font(SketchTheme.captionFont())
                                        .foregroundStyle(SketchTheme.sageGreen)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 10))
                                        .foregroundStyle(SketchTheme.lightBrown)
                                }
                            }
                            Button {
                                showAPIKeyEditor = true
                            } label: {
                                settingsRow("API Key") {
                                    Text(apiKey.isEmpty ? "Not set" : "••••\(apiKey.suffix(4))")
                                        .font(SketchTheme.captionFont())
                                        .foregroundStyle(apiKey.isEmpty ? SketchTheme.lightBrown : SketchTheme.dustyRose)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(SketchTheme.lightBrown)
                                }
                            }
                            .buttonStyle(.plain)

                            // Test Connection (inline)
                            Button {
                                testConnection()
                            } label: {
                                settingsRow("Test Connection") {
                                    if isTesting {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else if let result = testResult {
                                        Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundStyle(result ? SketchTheme.sageGreen : SketchTheme.mutedRed)
                                        Text(result ? "OK" : "Failed")
                                            .font(SketchTheme.captionFont())
                                            .foregroundStyle(result ? SketchTheme.sageGreen : SketchTheme.mutedRed)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 14))
                                            .foregroundStyle(SketchTheme.dustyRose)
                                        Text("Tap to test")
                                            .font(SketchTheme.captionFont())
                                            .foregroundStyle(SketchTheme.dustyRose)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(apiKey.isEmpty)
                        }

                        if let errorMsg = testErrorMessage {
                            Text(errorMsg)
                                .font(.system(size: 12, design: .serif))
                                .foregroundStyle(SketchTheme.mutedRed)
                                .padding(.horizontal, 4)
                        }

                        // Provider badges
                        HStack(spacing: 6) {
                            ForEach(AIProvider.allCases) { provider in
                                Text(provider.displayName)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(provider.color.opacity(0.15))
                                    .foregroundStyle(provider.color)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }

                    // Currency Section
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("Currency")
                        settingsCard {
                            settingsRow("Home Currency") {
                                Text("\(defaultCurrency)")
                                    .font(SketchTheme.captionFont())
                                    .foregroundStyle(SketchTheme.dustyRose)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(SketchTheme.lightBrown)
                            }
                            settingsRow("Auto-convert") {
                                Toggle("", isOn: .constant(true))
                                    .tint(SketchTheme.sageGreen)
                                    .labelsHidden()
                            }
                            settingsRow("Last Updated") {
                                Text("—")
                                    .font(SketchTheme.captionFont())
                                    .foregroundStyle(SketchTheme.lightBrown)
                            }
                        }
                    }

                    // Configuration Section
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("Configuration")
                        settingsCard {
                            Button { showImportPicker = true } label: {
                                settingsRow("Import Config") {
                                    HStack(spacing: 4) {
                                        Image(systemName: "square.and.arrow.down")
                                        Text("JSON")
                                            .font(SketchTheme.captionFont())
                                            .foregroundStyle(SketchTheme.sageGreen)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(SketchTheme.lightBrown)
                                }
                            }
                            .buttonStyle(.plain)

                            Button { exportConfig() } label: {
                                settingsRow("Export Config") {
                                    HStack(spacing: 4) {
                                        Image(systemName: "square.and.arrow.up")
                                        Text("JSON")
                                            .font(SketchTheme.captionFont())
                                            .foregroundStyle(SketchTheme.softBlue)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(SketchTheme.lightBrown)
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        if let msg = importMessage {
                            Text(msg)
                                .font(.system(size: 12, design: .serif))
                                .foregroundStyle(msg.contains("Success") ? SketchTheme.sageGreen : SketchTheme.mutedRed)
                                .padding(.horizontal, 4)
                        }

                        Text("Backup & restore your AI provider settings, API keys, currency preferences, and app configuration.")
                            .font(.system(size: 12, design: .serif))
                            .foregroundStyle(SketchTheme.lightBrown)
                            .padding(.horizontal, 4)
                    }

                    // Privacy Section
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("Privacy")
                        settingsCard {
                            settingsRow("AI Data Sharing") {
                                Toggle("", isOn: Binding(
                                    get: { settings?.hasConsentedToAIDataSharing ?? false },
                                    set: {
                                        if $0 {
                                            showConsentSheet = true
                                        } else {
                                            settings?.hasConsentedToAIDataSharing = false
                                            try? modelContext.save()
                                        }
                                    }
                                ))
                                .tint(SketchTheme.sageGreen)
                                .labelsHidden()
                            }
                        }
                        Text(settings?.hasConsentedToAIDataSharing == true
                            ? "You have consented to share data with your AI provider for bill recognition and timeline generation."
                            : "AI features require consent to share receipt images and bill data with your chosen AI provider.")
                            .font(.system(size: 12, design: .serif))
                            .foregroundStyle(SketchTheme.lightBrown)
                            .padding(.horizontal, 4)

                        Link(destination: URL(string: "https://cdcupt.github.io/BillMind/docs/privacy-policy.html")!) {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.shield")
                                Text("Privacy Policy")
                                    .font(.system(size: 12, design: .serif))
                            }
                            .foregroundStyle(SketchTheme.dustyRose)
                            .padding(.horizontal, 4)
                        }
                    }

                    // About
                    VStack(spacing: 4) {
                        Text("BillMind v1.0.0")
                            .font(SketchTheme.captionFont())
                            .foregroundStyle(SketchTheme.lightBrown)
                        Text("Bill with AI Mind")
                            .font(.system(size: 12, design: .serif))
                            .foregroundStyle(SketchTheme.lightBrown.opacity(0.7))
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                .padding()
            }
            .paperBackground()
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Text("Settings")
                            .font(SketchTheme.headlineFont(20))
                            .foregroundStyle(SketchTheme.softBrown)
                        Image("mascot_fox")
                            .resizable().scaledToFill()
                            .frame(width: 24, height: 24)
                            .clipShape(Circle())
                    }
                }
            }
            .onAppear { loadSettings() }
            .onChange(of: selectedProvider) { _, newProvider in
                customModel = newProvider.defaultModel
                imageModel = newProvider.defaultImageModel
                testResult = nil
                testErrorMessage = nil
                saveSettings()
            }
            .onChange(of: apiKey) { _, _ in testResult = nil; testErrorMessage = nil }
            .sheet(isPresented: $showAPIKeyEditor) {
                APIKeyEditorView(apiKey: $apiKey, provider: selectedProvider) {
                    saveSettings()
                }
            }
            .sheet(isPresented: $showExportShare) {
                if let url = exportFileURL {
                    ShareSheet(items: [url])
                }
            }
            .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [.json]) { result in
                importConfig(result: result)
            }
            .sheet(isPresented: $showConsentSheet) {
                AIDataConsentView(provider: selectedProvider) {
                    settings?.hasConsentedToAIDataSharing = true
                    try? modelContext.save()
                } onDecline: {
                    // No action needed — toggle stays off
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(SketchTheme.headlineFont(18))
            .foregroundStyle(SketchTheme.lightBrown)
    }

    @ViewBuilder
    private func settingsCard(@ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(SketchTheme.warmWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(SketchTheme.lightBrown.opacity(0.3), lineWidth: 1.5)
        )
        .shadow(color: SketchTheme.paperShadow, radius: 4, y: 2)
    }

    @ViewBuilder
    private func settingsRow<Content: View>(_ label: String, @ViewBuilder trailing: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(SketchTheme.bodyFont(15))
                .foregroundStyle(SketchTheme.softBrown)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func loadSettings() {
        let s = AppSettings.getOrCreate(context: modelContext)
        settings = s
        selectedProvider = s.selectedProvider
        customModel = s.customModel.isEmpty ? s.selectedProvider.defaultModel : s.customModel
        imageModel = s.imageModel.isEmpty ? s.selectedProvider.defaultImageModel : s.imageModel
        apiKey = s.apiKey
        defaultCurrency = s.defaultCurrency
    }

    private func exportConfig() {
        guard let settings else { return }
        saveSettings()
        do {
            exportFileURL = try BillMindConfig.export(settings: settings)
            showExportShare = true
        } catch {
            importMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importConfig(result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            let config = try BillMindConfig.load(from: url)
            guard let settings else { return }
            config.apply(to: settings)
            try? modelContext.save()

            // Reload UI state
            selectedProvider = settings.selectedProvider
            customModel = settings.customModel
            apiKey = settings.apiKey
            defaultCurrency = settings.defaultCurrency
            testResult = nil
            testErrorMessage = nil
            importMessage = "Success! Configuration imported."
        } catch {
            importMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func testConnection() {
        guard !apiKey.isEmpty else { return }
        isTesting = true
        testResult = nil
        testErrorMessage = nil

        Task {
            do {
                let model = customModel.isEmpty ? selectedProvider.defaultModel : customModel
                let url: URL
                var request: URLRequest

                if selectedProvider.usesGeminiFormat {
                    url = URL(string: "\(selectedProvider.baseURL)/models/\(model):generateContent")!
                    request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(apiKey, forHTTPHeaderField: "X-goog-api-key")
                    let body: [String: Any] = [
                        "contents": [["parts": [["text": "Say OK"]]]]
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                } else {
                    url = URL(string: selectedProvider.baseURL)!
                    request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    let body: [String: Any] = [
                        "model": model,
                        "messages": [["role": "user", "content": "Say OK"]],
                        "max_tokens": 5
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                }
                request.timeoutInterval = 30

                let (data, response) = try await URLSession.shared.data(for: request)
                let httpResponse = response as? HTTPURLResponse

                await MainActor.run {
                    if let status = httpResponse?.statusCode, (200...299).contains(status) {
                        testResult = true
                        testErrorMessage = nil
                    } else {
                        testResult = false
                        let status = httpResponse?.statusCode ?? 0
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let error = json["error"] as? [String: Any],
                           let msg = error["message"] as? String {
                            testErrorMessage = "HTTP \(status): \(msg)"
                        } else {
                            testErrorMessage = "HTTP \(status)"
                        }
                    }
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = false
                    testErrorMessage = error.localizedDescription
                    isTesting = false
                }
            }
        }
    }

    private func saveSettings() {
        guard let settings else { return }
        settings.selectedProvider = selectedProvider
        settings.customModel = customModel
        settings.imageModel = imageModel
        settings.apiKey = apiKey
        settings.defaultCurrency = defaultCurrency
        try? modelContext.save()
    }
}

// MARK: - API Key Editor

struct APIKeyEditorView: View {
    @Binding var apiKey: String
    let provider: AIProvider
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editingKey = ""
    @State private var showKey = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: provider.iconName)
                        .font(.system(size: 40))
                        .foregroundStyle(provider.color)
                    Text(provider.displayName)
                        .font(SketchTheme.headlineFont(20))
                        .foregroundStyle(SketchTheme.softBrown)
                    Text("Enter your API key for \(provider.displayName)")
                        .font(SketchTheme.bodyFont(14))
                        .foregroundStyle(SketchTheme.lightBrown)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("API Key")
                            .font(SketchTheme.captionFont())
                            .foregroundStyle(SketchTheme.lightBrown)
                        Spacer()
                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .font(.system(size: 14))
                                .foregroundStyle(SketchTheme.lightBrown)
                        }
                    }
                    ZStack {
                        if showKey {
                            TextField("Enter your API key", text: $editingKey)
                                .font(.system(size: 16, design: .monospaced))
                                .textFieldStyle(.plain)
                        } else {
                            SecureField("Enter your API key", text: $editingKey)
                                .font(.system(size: 16, design: .monospaced))
                                .textFieldStyle(.plain)
                        }
                    }
                    .padding(12)
                    .background(SketchTheme.cream)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(SketchTheme.lightBrown.opacity(0.3), lineWidth: 1)
                    )
                }
                .sketchCard()

                Button {
                    apiKey = editingKey
                    onSave()
                    dismiss()
                } label: {
                    Text("Save")
                        .font(SketchTheme.headlineFont(18))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(SketchTheme.primaryGradient)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(editingKey.isEmpty)
                .opacity(editingKey.isEmpty ? 0.5 : 1)

                Spacer()
            }
            .padding()
            .paperBackground()
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(SketchTheme.dustyRose)
                }
            }
            .onAppear { editingKey = apiKey }
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - AI Data Sharing Consent

struct AIDataConsentView: View {
    let provider: AIProvider
    var onConsent: () -> Void
    var onDecline: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    AnimalMascotView(animal: .owl, size: 72)

                    Text("AI Data Sharing")
                        .font(SketchTheme.headlineFont(22))
                        .foregroundStyle(SketchTheme.softBrown)

                    Text("BillMind uses AI to recognize bills from photos and generate timeline images. Before using these features, please review what data is shared.")
                        .font(SketchTheme.bodyFont(15))
                        .foregroundStyle(SketchTheme.lightBrown)
                        .multilineTextAlignment(.center)

                    // What data is sent
                    consentSection(
                        icon: "doc.text.image",
                        title: "What data is sent",
                        items: [
                            "Photos of receipts and invoices you select",
                            "Bill details (merchant names, dates, amounts, categories) for timeline generation",
                        ]
                    )

                    // Who receives the data
                    consentSection(
                        icon: "server.rack",
                        title: "Who receives the data",
                        items: [
                            "Your chosen AI provider: \(provider.displayName)",
                            "Data is sent directly from your device to the provider's API",
                            "BillMind does not operate any servers and does not collect your data",
                        ]
                    )

                    // How data is used
                    consentSection(
                        icon: "shield.lefthalf.filled",
                        title: "How your data is protected",
                        items: [
                            "Your API key is stored only on your device",
                            "All financial data stays on your device",
                            "You can revoke consent anytime in Settings",
                            "You can use the app without AI (manual bill entry)",
                        ]
                    )

                    // Privacy policy link
                    Link(destination: URL(string: "https://cdcupt.github.io/BillMind/docs/privacy-policy.html")!) {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield")
                            Text("Read Full Privacy Policy")
                                .font(SketchTheme.bodyFont(14))
                        }
                        .foregroundStyle(SketchTheme.dustyRose)
                    }

                    // Consent button
                    Button {
                        onConsent()
                        dismiss()
                    } label: {
                        Text("I Agree — Enable AI Features")
                            .font(SketchTheme.headlineFont(18))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(SketchTheme.primaryGradient)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: SketchTheme.dustyRose.opacity(0.3), radius: 6, y: 3)
                    }
                    .buttonStyle(.plain)

                    // Decline button
                    Button {
                        onDecline()
                        dismiss()
                    } label: {
                        Text("Not Now")
                            .font(SketchTheme.bodyFont(15))
                            .foregroundStyle(SketchTheme.lightBrown)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .paperBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDecline()
                        dismiss()
                    }
                    .foregroundStyle(SketchTheme.dustyRose)
                }
            }
        }
    }

    @ViewBuilder
    private func consentSection(icon: String, title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(SketchTheme.dustyRose)
                Text(title)
                    .font(SketchTheme.headlineFont(16))
                    .foregroundStyle(SketchTheme.softBrown)
            }

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(SketchTheme.lightBrown)
                    Text(item)
                        .font(SketchTheme.bodyFont(14))
                        .foregroundStyle(SketchTheme.softBrown)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sketchCard()
    }
}
