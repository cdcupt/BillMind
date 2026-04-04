import SwiftUI

// MARK: - AI Provider

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case gemini
    case openai
    case doubao

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .openai: return "OpenAI"
        case .doubao: return "Doubao"
        }
    }

    var defaultModel: String {
        switch self {
        case .gemini: return "gemini-3-flash-preview"
        case .openai: return "gpt-5.4"
        case .doubao: return "doubao-seed-2-pro"
        }
    }

    var baseURL: String {
        switch self {
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .openai: return "https://api.openai.com/v1/chat/completions"
        case .doubao: return "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
        }
    }

    /// Whether this provider uses the native Gemini API format instead of OpenAI-compatible
    var usesGeminiFormat: Bool { self == .gemini }

    var iconName: String {
        switch self {
        case .gemini: return "sparkles"
        case .openai: return "brain.head.profile"
        case .doubao: return "wand.and.stars"
        }
    }

    var color: Color {
        switch self {
        case .gemini: return Color(hex: "4285F4")
        case .openai: return Color(hex: "10A37F")
        case .doubao: return Color(hex: "FF6A00")
        }
    }

    var defaultImageModel: String {
        switch self {
        case .gemini: return "gemini-3.1-flash-image-preview"
        case .openai: return "gpt-5-image-mini"
        case .doubao: return ""
        }
    }

    var availableImageModels: [String] {
        switch self {
        case .gemini: return [
            "gemini-3.1-flash-image-preview",
            "gemini-3-pro-image-preview",
            "gemini-2.5-flash-image",
        ]
        case .openai: return [
            "gpt-5-image-mini",
            "gpt-5-image",
        ]
        case .doubao: return [
            "Not supported",
        ]
        }
    }

    var availableModels: [String] {
        switch self {
        case .gemini: return [
            "gemini-3-flash-preview",
            "gemini-3.1-pro-preview",
            "gemini-2.5-flash",
            "gemini-2.5-pro",
            "gemini-3.1-flash-lite-preview",
        ]
        case .openai: return [
            "gpt-5.4",
            "gpt-5.4-nano",
            "gpt-5",
        ]
        case .doubao: return [
            "doubao-seed-2-pro",
            "doubao-seed-2-lite",
        ]
        }
    }

    /// Short display name for picker selected value
    static func shortName(for model: String) -> String {
        let names: [String: String] = [
            "gemini-3-flash-preview": "Gemini 3 Flash",
            "gemini-3.1-pro-preview": "Gemini 3.1 Pro",
            "gemini-2.5-flash": "Gemini 2.5 Flash",
            "gemini-2.5-pro": "Gemini 2.5 Pro",
            "gemini-3.1-flash-lite-preview": "Gemini 3.1 Lite",
            "gemini-3.1-flash-image-preview": "Gemini 3.1 Image",
            "gemini-3-pro-image-preview": "Gemini 3 Pro Image",
            "gemini-2.5-flash-image": "Gemini 2.5 Image",
            "gpt-5.4": "GPT-5.4",
            "gpt-5.4-nano": "GPT-5.4 Nano",
            "gpt-5": "GPT-5",
            "gpt-5-image-mini": "GPT-5 Image Mini",
            "gpt-5-image": "GPT-5 Image",
            "doubao-seed-2-pro": "Seed 2 Pro",
            "doubao-seed-2-lite": "Seed 2 Lite",
        ]
        return names[model] ?? model
    }

    /// Price range per 1M tokens
    static func priceLabel(for model: String) -> String {
        let prices: [String: String] = [
            // Gemini recognition
            "gemini-3-flash-preview": "$0.5~$3",
            "gemini-3.1-pro-preview": "$2~$12",
            "gemini-2.5-flash": "$0.3~$2.5",
            "gemini-2.5-pro": "$1.25~$10",
            "gemini-3.1-flash-lite-preview": "$0.25~$1.5",
            // Gemini image gen
            "gemini-3.1-flash-image-preview": "$0.04/img",
            "gemini-3-pro-image-preview": "$0.13/img",
            "gemini-2.5-flash-image": "$0.04/img",
            // OpenAI
            "gpt-5.4": "$2.5~$12",
            "gpt-5.4-nano": "$0.2~$1.25",
            "gpt-5": "$10~$10",
            "gpt-5-image-mini": "$0.02/img",
            "gpt-5-image": "$0.04/img",
            // Doubao
            "doubao-seed-2-pro": "$0.47~$2.37",
            "doubao-seed-2-lite": "$0.15~$0.6",
        ]
        return prices[model] ?? ""
    }
}

// MARK: - Bill Category

enum BillCategory: String, Codable, CaseIterable, Identifiable {
    case food
    case transport
    case accommodation
    case shopping
    case entertainment
    case utilities
    case medical
    case education
    case subscription
    case misc

    var id: String { rawValue }

    var displayName: String {
        englishName
    }

    var englishName: String {
        switch self {
        case .food: return "Food"
        case .transport: return "Transport"
        case .accommodation: return "Hotel"
        case .shopping: return "Shopping"
        case .entertainment: return "Fun"
        case .utilities: return "Utilities"
        case .medical: return "Medical"
        case .education: return "Education"
        case .subscription: return "Subscription"
        case .misc: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .food: return "cat_food"
        case .transport: return "cat_transport"
        case .accommodation: return "cat_hotel"
        case .shopping: return "cat_shopping"
        case .entertainment: return "cat_entertainment"
        case .utilities: return "cat_utilities"
        case .medical: return "cat_medical"
        case .education: return "cat_education"
        case .subscription: return "cat_subscription"
        case .misc: return "cat_misc"
        }
    }

    var sfSymbol: String {
        switch self {
        case .food: return "fork.knife"
        case .transport: return "car.fill"
        case .accommodation: return "bed.double.fill"
        case .shopping: return "bag.fill"
        case .entertainment: return "sparkles"
        case .utilities: return "bolt.fill"
        case .medical: return "cross.case.fill"
        case .education: return "book.fill"
        case .subscription: return "arrow.triangle.2.circlepath"
        case .misc: return "square.grid.2x2.fill"
        }
    }

    var color: Color {
        switch self {
        case .food: return Color(hex: "E86A17")
        case .transport: return Color(hex: "3366CC")
        case .accommodation: return Color(hex: "8B5CF6")
        case .shopping: return Color(hex: "E03370")
        case .entertainment: return Color(hex: "D4A017")
        case .utilities: return Color(hex: "059669")
        case .medical: return Color(hex: "DC2626")
        case .education: return Color(hex: "2563EB")
        case .subscription: return Color(hex: "7C3AED")
        case .misc: return Color(hex: "6B7280")
        }
    }
}

// MARK: - Bill Status

enum BillStatus: String, Codable {
    case draft
    case confirmed
}

// MARK: - Animal Type

enum AnimalType: String, Codable, CaseIterable, Identifiable {
    case cat
    case owl
    case bear
    case rabbit
    case fox

    var id: String { rawValue }

    var imageName: String {
        switch self {
        case .cat: return "mascot_cat"
        case .owl: return "mascot_owl"
        case .bear: return "mascot_bear"
        case .rabbit: return "mascot_rabbit"
        case .fox: return "mascot_fox"
        }
    }

    var displayName: String {
        switch self {
        case .cat: return "Momo"
        case .owl: return "Hoot"
        case .bear: return "Kuma"
        case .rabbit: return "Bun"
        case .fox: return "Rusty"
        }
    }

    var context: String {
        switch self {
        case .cat: return "Empty states & welcome"
        case .owl: return "AI processing & thinking"
        case .bear: return "Statistics & numbers"
        case .rabbit: return "Success & confirmation"
        case .fox: return "Settings & configuration"
        }
    }
}

// MARK: - Popular Currencies

struct CurrencyInfo: Identifiable, Codable, Hashable {
    var id: String { code }
    let code: String
    let symbol: String
    let name: String

    static let popular: [CurrencyInfo] = [
        CurrencyInfo(code: "CNY", symbol: "¥", name: "Chinese Yuan"),
        CurrencyInfo(code: "USD", symbol: "$", name: "US Dollar"),
        CurrencyInfo(code: "EUR", symbol: "€", name: "Euro"),
        CurrencyInfo(code: "JPY", symbol: "¥", name: "Japanese Yen"),
        CurrencyInfo(code: "KRW", symbol: "₩", name: "Korean Won"),
        CurrencyInfo(code: "THB", symbol: "฿", name: "Thai Baht"),
        CurrencyInfo(code: "GBP", symbol: "£", name: "British Pound"),
        CurrencyInfo(code: "HKD", symbol: "HK$", name: "Hong Kong Dollar"),
        CurrencyInfo(code: "SGD", symbol: "S$", name: "Singapore Dollar"),
        CurrencyInfo(code: "AUD", symbol: "A$", name: "Australian Dollar"),
        CurrencyInfo(code: "MYR", symbol: "RM", name: "Malaysian Ringgit"),
    ]
}
