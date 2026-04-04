import Foundation
import SwiftData

@Model
final class AppSettings {
    var selectedProviderRaw: String
    var customModel: String
    var apiKey: String
    var defaultCurrency: String
    var enableOCRFallback: Bool
    var maxPhotosPerBatch: Int

    var selectedProvider: AIProvider {
        get { AIProvider(rawValue: selectedProviderRaw) ?? .gemini }
        set { selectedProviderRaw = newValue.rawValue }
    }

    init() {
        self.selectedProviderRaw = AIProvider.gemini.rawValue
        self.customModel = ""
        self.apiKey = ""
        self.defaultCurrency = "CNY"
        self.enableOCRFallback = true
        self.maxPhotosPerBatch = 10
    }

    static func getOrCreate(context: ModelContext) -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let settings = AppSettings()
        context.insert(settings)
        try? context.save()
        return settings
    }
}
