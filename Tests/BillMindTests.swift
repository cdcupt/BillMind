import XCTest
@testable import BillMind

final class BillMindTests: XCTestCase {
    func testBillCategoryHasAllCases() {
        XCTAssertEqual(BillCategory.allCases.count, 10)
    }

    func testAIProviderDefaults() {
        XCTAssertEqual(AIProvider.gemini.defaultModel, "gemini-2.5-flash")
        XCTAssertEqual(AIProvider.openai.defaultModel, "gpt-5.4")
        XCTAssertEqual(AIProvider.doubao.defaultModel, "doubao-seed-2-pro")
        XCTAssertEqual(AIProvider.allCases.count, 3)
        XCTAssertEqual(AIProvider.allCases.first, .gemini)
    }

    func testCurrencyInfoPopular() {
        XCTAssertEqual(CurrencyInfo.popular.count, 11)
        XCTAssertEqual(CurrencyInfo.popular.first?.code, "CNY")
    }

    func testBillLineItemCreation() {
        let item = BillLineItem(itemDescription: "Ramen", quantity: 2, unitPrice: 15, amount: 30)
        XCTAssertEqual(item.itemDescription, "Ramen")
        XCTAssertEqual(item.quantity, 2)
        XCTAssertEqual(item.amount, 30)
    }

    func testAIRecognitionResultDateParsing() {
        let result = AIRecognitionResult(
            merchant: "Test",
            date: "2026-04-03",
            totalAmount: 100.0,
            currency: "CNY",
            category: "food",
            lineItems: nil,
            notes: nil
        )
        XCTAssertNotNil(result.parsedDate)
        XCTAssertEqual(result.parsedCategory, .food)
        XCTAssertEqual(result.parsedAmount, 100)
    }
}
