import XCTest
import SwiftUI
@testable import BillMind

// MARK: - Enum Tests

final class AIProviderTests: XCTestCase {
    func testProviderCount() {
        XCTAssertEqual(AIProvider.allCases.count, 3)
    }

    func testProviderOrder() {
        XCTAssertEqual(AIProvider.allCases.first, .gemini)
    }

    func testDefaultModels() {
        XCTAssertEqual(AIProvider.gemini.defaultModel, "gemini-3-flash-preview")
        XCTAssertEqual(AIProvider.openai.defaultModel, "gpt-5.4")
        XCTAssertEqual(AIProvider.doubao.defaultModel, "doubao-seed-2-pro")
    }

    func testDefaultImageModels() {
        XCTAssertEqual(AIProvider.gemini.defaultImageModel, "gemini-3.1-flash-image-preview")
        XCTAssertEqual(AIProvider.openai.defaultImageModel, "gpt-5-image-mini")
    }

    func testAvailableModels() {
        XCTAssertGreaterThanOrEqual(AIProvider.gemini.availableModels.count, 3)
        XCTAssertTrue(AIProvider.gemini.availableModels.contains("gemini-3-flash-preview"))
        XCTAssertGreaterThanOrEqual(AIProvider.openai.availableModels.count, 2)
        XCTAssertGreaterThanOrEqual(AIProvider.doubao.availableModels.count, 1)
    }

    func testAvailableImageModels() {
        XCTAssertGreaterThanOrEqual(AIProvider.gemini.availableImageModels.count, 2)
        XCTAssertTrue(AIProvider.gemini.availableImageModels.contains("gemini-3.1-flash-image-preview"))
    }

    func testGeminiUsesGeminiFormat() {
        XCTAssertTrue(AIProvider.gemini.usesGeminiFormat)
        XCTAssertFalse(AIProvider.openai.usesGeminiFormat)
        XCTAssertFalse(AIProvider.doubao.usesGeminiFormat)
    }

    func testBaseURLNotEmpty() {
        for provider in AIProvider.allCases {
            XCTAssertFalse(provider.baseURL.isEmpty, "\(provider) has empty baseURL")
        }
    }

    func testDisplayNameNotEmpty() {
        for provider in AIProvider.allCases {
            XCTAssertFalse(provider.displayName.isEmpty, "\(provider) has empty displayName")
        }
    }

    func testPriceLabels() {
        XCTAssertFalse(AIProvider.priceLabel(for: "gemini-3-flash-preview").isEmpty)
        XCTAssertFalse(AIProvider.priceLabel(for: "gpt-5.4").isEmpty)
        XCTAssertTrue(AIProvider.priceLabel(for: "nonexistent-model").isEmpty)
    }

    func testShortNames() {
        XCTAssertEqual(AIProvider.shortName(for: "gemini-3-flash-preview"), "Gemini 3 Flash")
        XCTAssertEqual(AIProvider.shortName(for: "gpt-5.4"), "GPT-5.4")
        XCTAssertEqual(AIProvider.shortName(for: "unknown"), "unknown")
    }
}

// MARK: - Category Tests

final class BillCategoryTests: XCTestCase {
    func testCategoryCount() {
        XCTAssertEqual(BillCategory.allCases.count, 10)
    }

    func testAllCategoriesHaveEnglishName() {
        for category in BillCategory.allCases {
            XCTAssertFalse(category.englishName.isEmpty, "\(category) has empty englishName")
        }
    }

    func testDisplayNameEqualsEnglishName() {
        for category in BillCategory.allCases {
            XCTAssertEqual(category.displayName, category.englishName)
        }
    }

    func testAllCategoriesHaveIcon() {
        for category in BillCategory.allCases {
            XCTAssertFalse(category.icon.isEmpty, "\(category) has empty icon")
            XCTAssertTrue(category.icon.hasPrefix("cat_"), "\(category) icon should start with cat_")
        }
    }

    func testAllCategoriesHaveSfSymbol() {
        for category in BillCategory.allCases {
            XCTAssertFalse(category.sfSymbol.isEmpty, "\(category) has empty sfSymbol")
        }
    }

    func testNoChinese() {
        let chineseRange = Unicode.Scalar(0x4E00)!...Unicode.Scalar(0x9FFF)!
        for category in BillCategory.allCases {
            for scalar in category.displayName.unicodeScalars {
                XCTAssertFalse(chineseRange.contains(scalar), "\(category) displayName contains Chinese")
            }
            for scalar in category.englishName.unicodeScalars {
                XCTAssertFalse(chineseRange.contains(scalar), "\(category) englishName contains Chinese")
            }
        }
    }
}

// MARK: - Currency Tests

final class CurrencyTests: XCTestCase {
    func testPopularCurrencyCount() {
        XCTAssertEqual(CurrencyInfo.popular.count, 11)
    }

    func testFirstCurrencyIsCNY() {
        XCTAssertEqual(CurrencyInfo.popular.first?.code, "CNY")
    }

    func testAllCurrenciesHaveSymbol() {
        for currency in CurrencyInfo.popular {
            XCTAssertFalse(currency.symbol.isEmpty, "\(currency.code) has empty symbol")
        }
    }

    func testAllCurrenciesHaveName() {
        for currency in CurrencyInfo.popular {
            XCTAssertFalse(currency.name.isEmpty, "\(currency.code) has empty name")
        }
    }

    func testUniqueCurrencyCodes() {
        let codes = CurrencyInfo.popular.map(\.code)
        XCTAssertEqual(codes.count, Set(codes).count, "Duplicate currency codes found")
    }
}

// MARK: - Animal Type Tests

final class AnimalTypeTests: XCTestCase {
    func testAnimalCount() {
        XCTAssertEqual(AnimalType.allCases.count, 5)
    }

    func testAllAnimalsHaveImageName() {
        for animal in AnimalType.allCases {
            XCTAssertTrue(animal.imageName.hasPrefix("mascot_"), "\(animal) imageName should start with mascot_")
        }
    }

    func testAllAnimalsHaveDisplayName() {
        for animal in AnimalType.allCases {
            XCTAssertFalse(animal.displayName.isEmpty, "\(animal) has empty displayName")
        }
    }
}

// MARK: - Bill Line Item Tests

final class BillLineItemTests: XCTestCase {
    func testCreation() {
        let item = BillLineItem(itemDescription: "Ramen", quantity: 2, unitPrice: 15, amount: 30)
        XCTAssertEqual(item.itemDescription, "Ramen")
        XCTAssertEqual(item.quantity, 2)
        XCTAssertEqual(item.unitPrice, 15)
        XCTAssertEqual(item.amount, 30)
    }

    func testDefaultValues() {
        let item = BillLineItem(itemDescription: "Test")
        XCTAssertEqual(item.quantity, 1)
        XCTAssertEqual(item.unitPrice, 0)
        XCTAssertEqual(item.amount, 0)
    }

    func testCodable() throws {
        let item = BillLineItem(itemDescription: "Coffee", quantity: 1, unitPrice: 5, amount: 5)
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(BillLineItem.self, from: data)
        XCTAssertEqual(decoded.itemDescription, "Coffee")
        XCTAssertEqual(decoded.amount, 5)
    }
}

// MARK: - AI Recognition Result Tests

final class AIRecognitionResultTests: XCTestCase {
    func testDateParsingISO() {
        let result = AIRecognitionResult(
            merchant: "Test", date: "2026-04-03", totalAmount: 100.0,
            currency: "CNY", category: "food", lineItems: nil, notes: nil
        )
        XCTAssertNotNil(result.parsedDate)
        XCTAssertEqual(result.parsedCategory, .food)
        XCTAssertEqual(result.parsedAmount, 100)
    }

    func testDateParsingSlash() {
        let result = AIRecognitionResult(
            merchant: nil, date: "2026/04/03", totalAmount: nil,
            currency: nil, category: nil, lineItems: nil, notes: nil
        )
        XCTAssertNotNil(result.parsedDate)
    }

    func testDateParsingUSFormat() {
        let result = AIRecognitionResult(
            merchant: nil, date: "04/03/2026", totalAmount: nil,
            currency: nil, category: nil, lineItems: nil, notes: nil
        )
        XCTAssertNotNil(result.parsedDate)
    }

    func testNullFields() {
        let result = AIRecognitionResult(
            merchant: nil, date: nil, totalAmount: nil,
            currency: nil, category: nil, lineItems: nil, notes: nil
        )
        XCTAssertNil(result.parsedDate)
        XCTAssertNil(result.parsedCategory)
        XCTAssertNil(result.parsedAmount)
    }

    func testCategoryParsing() {
        for category in BillCategory.allCases {
            let result = AIRecognitionResult(
                merchant: nil, date: nil, totalAmount: nil,
                currency: nil, category: category.rawValue, lineItems: nil, notes: nil
            )
            XCTAssertEqual(result.parsedCategory, category, "Failed to parse category: \(category.rawValue)")
        }
    }

    func testLineItemConversion() {
        let result = AIRecognitionResult(
            merchant: "Store", date: nil, totalAmount: 50,
            currency: "USD", category: "shopping",
            lineItems: [
                AIRecognitionResult.RecognizedLineItem(description: "Item A", quantity: 2, unitPrice: 10, amount: 20),
                AIRecognitionResult.RecognizedLineItem(description: "Item B", quantity: nil, unitPrice: nil, amount: 30),
            ],
            notes: nil
        )
        let items = result.toBillLineItems()
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].itemDescription, "Item A")
        XCTAssertEqual(items[0].quantity, 2)
        XCTAssertEqual(items[1].itemDescription, "Item B")
        XCTAssertEqual(items[1].quantity, 1)
    }
}

// MARK: - Config Tests

final class ConfigTests: XCTestCase {
    func testConfigCodable() throws {
        let config = BillMindConfig(
            provider: "gemini",
            model: "gemini-3-flash-preview",
            imageModel: "gemini-3.1-flash-image-preview",
            apiKey: "test-key",
            defaultCurrency: "USD",
            maxPhotosPerBatch: 5
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(BillMindConfig.self, from: data)
        XCTAssertEqual(decoded.provider, "gemini")
        XCTAssertEqual(decoded.model, "gemini-3-flash-preview")
        XCTAssertEqual(decoded.imageModel, "gemini-3.1-flash-image-preview")
        XCTAssertEqual(decoded.apiKey, "test-key")
        XCTAssertEqual(decoded.defaultCurrency, "USD")
        XCTAssertEqual(decoded.maxPhotosPerBatch, 5)
    }

    func testConfigImageModelOptional() throws {
        let json = """
        {"provider":"gemini","model":"gemini-3-flash-preview","apiKey":"key","defaultCurrency":"CNY","maxPhotosPerBatch":10,"version":"1.0"}
        """
        let config = try JSONDecoder().decode(BillMindConfig.self, from: json.data(using: .utf8)!)
        XCTAssertNil(config.imageModel)
    }
}

// MARK: - Extension Tests

final class ExtensionTests: XCTestCase {
    func testColorHexInit() {
        // Should not crash
        let _ = Color(hex: "FF0000")
        let _ = Color(hex: "#00FF00")
        let _ = Color(hex: "0000FF")
    }

    func testDecimalFormatted() {
        let amount: Decimal = 1234.56
        XCTAssertFalse(amount.formatted2.isEmpty)
        XCTAssertFalse(amount.formattedCurrency.isEmpty)
    }

    func testArraySafeSubscript() {
        let arr = [1, 2, 3]
        XCTAssertEqual(arr[safe: 0], 1)
        XCTAssertEqual(arr[safe: 2], 3)
        XCTAssertNil(arr[safe: 5])
        XCTAssertNil(arr[safe: -1])
    }

    func testDateRelativeLabel() {
        XCTAssertEqual(Date().relativeLabel, "Today")
    }
}

// MARK: - AppSettings Tests

final class AppSettingsTests: XCTestCase {
    func testDefaultConsentIsFalse() {
        let settings = AppSettings()
        XCTAssertFalse(settings.hasConsentedToAIDataSharing)
    }

    func testDefaultDemoModeIsFalse() {
        let settings = AppSettings()
        XCTAssertFalse(settings.demoMode)
    }

    func testDefaultProvider() {
        let settings = AppSettings()
        XCTAssertEqual(settings.selectedProvider, .gemini)
    }
}
