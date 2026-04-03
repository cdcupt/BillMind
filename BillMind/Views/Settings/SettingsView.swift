import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var settings: AppSettings?
    @State private var selectedProvider: AIProvider = .openai
    @State private var customModel = ""
    @State private var defaultCurrency = "CNY"
    @State private var enableOCRFallback = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // AI Provider Section
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
                            settingsRow("Model") {
                                Text(customModel.isEmpty ? selectedProvider.defaultModel : customModel)
                                    .font(SketchTheme.captionFont())
                                    .foregroundStyle(SketchTheme.dustyRose)
                            }
                            settingsRow("API Key") {
                                Text("Not set")
                                    .font(SketchTheme.captionFont())
                                    .foregroundStyle(SketchTheme.lightBrown)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(SketchTheme.lightBrown)
                            }
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

                    // Recognition Section
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("Recognition")
                        settingsCard {
                            settingsRow("OCR Fallback") {
                                Toggle("", isOn: $enableOCRFallback)
                                    .tint(SketchTheme.sageGreen)
                                    .labelsHidden()
                            }
                            settingsRow("Max Photos/Batch") {
                                Text("10")
                                    .font(SketchTheme.captionFont())
                                    .foregroundStyle(SketchTheme.dustyRose)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(SketchTheme.lightBrown)
                            }
                        }
                    }

                    // Data Export Section
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("Data Export")
                        settingsCard {
                            settingsRow("Export as CSV") {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(SketchTheme.lightBrown)
                            }
                            settingsRow("Export as PDF") {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(SketchTheme.lightBrown)
                            }
                        }
                    }

                    // Configuration Section
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("Configuration")
                        settingsCard {
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
                        Text("Backup & restore your AI provider settings, API keys, currency preferences, and app configuration.")
                            .font(.system(size: 12, design: .serif))
                            .foregroundStyle(SketchTheme.lightBrown)
                            .padding(.horizontal, 4)
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
                            .resizable().scaledToFit()
                            .frame(width: 24, height: 24)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(SketchTheme.dustyRose)
                }
            }
            .onAppear { loadSettings() }
            .onChange(of: selectedProvider) { _, _ in saveSettings() }
            .onChange(of: enableOCRFallback) { _, _ in saveSettings() }
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
        customModel = s.customModel
        defaultCurrency = s.defaultCurrency
        enableOCRFallback = s.enableOCRFallback
    }

    private func saveSettings() {
        guard let settings else { return }
        settings.selectedProvider = selectedProvider
        settings.customModel = customModel
        settings.defaultCurrency = defaultCurrency
        settings.enableOCRFallback = enableOCRFallback
        try? modelContext.save()
    }
}
