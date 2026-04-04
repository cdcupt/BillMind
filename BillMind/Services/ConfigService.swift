import Foundation

/// Configuration file format for BillMind settings
struct BillMindConfig: Codable {
    var version: String = "1.0"
    var provider: String
    var model: String
    var imageModel: String?
    var apiKey: String
    var defaultCurrency: String
    var maxPhotosPerBatch: Int

    static func from(settings: AppSettings) -> BillMindConfig {
        BillMindConfig(
            provider: settings.selectedProviderRaw,
            model: settings.customModel,
            imageModel: settings.imageModel,
            apiKey: settings.apiKey,
            defaultCurrency: settings.defaultCurrency,
            maxPhotosPerBatch: settings.maxPhotosPerBatch
        )
    }

    func apply(to settings: AppSettings) {
        if let provider = AIProvider(rawValue: provider) {
            settings.selectedProvider = provider
        }
        settings.customModel = model
        settings.imageModel = imageModel ?? provider == "gemini" ? "gemini-3.1-flash-image-preview" : ""
        settings.apiKey = apiKey
        settings.defaultCurrency = defaultCurrency
        settings.maxPhotosPerBatch = maxPhotosPerBatch
    }

    // MARK: - File Operations

    static func export(settings: AppSettings) throws -> URL {
        let config = BillMindConfig.from(settings: settings)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)

        let dir = FileManager.default.temporaryDirectory
        let fileURL = dir.appendingPathComponent("BillMind_config.json")
        try data.write(to: fileURL)
        return fileURL
    }

    static func load(from url: URL) throws -> BillMindConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(BillMindConfig.self, from: data)
    }
}
