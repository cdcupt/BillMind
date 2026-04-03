import SwiftUI

// MARK: - AI Provider

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case openai
    case gemini
    case doubao
    case kimi
    case claude

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .gemini: return "Google Gemini"
        case .doubao: return "Doubao"
        case .kimi: return "Kimi"
        case .claude: return "Claude"
        }
    }

    var defaultModel: String {
        switch self {
        case .openai: return "gpt-5.4"
        case .gemini: return "gemini-3-flash"
        case .doubao: return "doubao-seed-2-pro"
        case .kimi: return "kimi-k2.5"
        case .claude: return "claude-sonnet-4-6-20260401"
        }
    }

    var baseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1/chat/completions"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        case .doubao: return "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
        case .kimi: return "https://api.moonshot.cn/v1/chat/completions"
        case .claude: return "https://api.anthropic.com/v1/messages"
        }
    }

    var usesAnthropicFormat: Bool { self == .claude }

    var iconName: String {
        switch self {
        case .openai: return "brain.head.profile"
        case .gemini: return "sparkles"
        case .doubao: return "wand.and.stars"
        case .kimi: return "moon.stars"
        case .claude: return "bubble.left.and.text.bubble.right"
        }
    }

    var color: Color {
        switch self {
        case .openai: return Color(hex: "10A37F")
        case .gemini: return Color(hex: "4285F4")
        case .doubao: return Color(hex: "FF6A00")
        case .kimi: return Color(hex: "6C5CE7")
        case .claude: return Color(hex: "D97757")
        }
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
        switch self {
        case .food: return "餐饮"
        case .transport: return "交通"
        case .accommodation: return "住宿"
        case .shopping: return "购物"
        case .entertainment: return "娱乐"
        case .utilities: return "生活"
        case .medical: return "医疗"
        case .education: return "教育"
        case .subscription: return "订阅"
        case .misc: return "其他"
        }
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
    let nameCN: String

    static let popular: [CurrencyInfo] = [
        CurrencyInfo(code: "CNY", symbol: "¥", name: "Chinese Yuan", nameCN: "人民币"),
        CurrencyInfo(code: "USD", symbol: "$", name: "US Dollar", nameCN: "美元"),
        CurrencyInfo(code: "EUR", symbol: "€", name: "Euro", nameCN: "欧元"),
        CurrencyInfo(code: "JPY", symbol: "¥", name: "Japanese Yen", nameCN: "日元"),
        CurrencyInfo(code: "KRW", symbol: "₩", name: "Korean Won", nameCN: "韩元"),
        CurrencyInfo(code: "THB", symbol: "฿", name: "Thai Baht", nameCN: "泰铢"),
        CurrencyInfo(code: "GBP", symbol: "£", name: "British Pound", nameCN: "英镑"),
        CurrencyInfo(code: "HKD", symbol: "HK$", name: "Hong Kong Dollar", nameCN: "港币"),
        CurrencyInfo(code: "SGD", symbol: "S$", name: "Singapore Dollar", nameCN: "新加坡元"),
        CurrencyInfo(code: "AUD", symbol: "A$", name: "Australian Dollar", nameCN: "澳元"),
        CurrencyInfo(code: "MYR", symbol: "RM", name: "Malaysian Ringgit", nameCN: "马来西亚林吉特"),
    ]
}
