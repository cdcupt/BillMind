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

// MARK: - Wire DTO Decoding (contract conformance)

private let kUUID = "26E80ECF-41F2-44B3-A096-D7ABCE096A3A"

final class WireDTODecodeTests: XCTestCase {
    func testBillDecodesMoneyAsStringExactly() throws {
        let json = """
        {"id":"\(kUUID)","tripID":"\(kUUID)","merchant":"Ichiran","amount":"19.99",
         "currencyCode":"JPY","date":"2026-04-03T10:00:00Z","categoryRaw":"food",
         "source":"text","notes":null,"rowVersion":3}
        """
        let bill = try APICoders.decoder.decode(APIBill.self, from: Data(json.utf8))
        XCTAssertEqual(bill.amount, Decimal(string: "19.99"))   // exact — no float drift
        XCTAssertEqual(bill.merchant, "Ichiran")
        XCTAssertEqual(bill.rowVersion, 3)
        let expectedDate = ISO8601DateFormatter().date(from: "2026-04-03T10:00:00Z")
        XCTAssertEqual(bill.date, expectedDate)                 // ISO-8601 parsed
    }

    func testTripDecodesExchangeRateString() throws {
        let json = """
        {"id":"\(kUUID)","name":"Osaka","currencyCode":"JPY","exchangeRate":"1.5",
         "mascot":null,"rowVersion":1}
        """
        let trip = try APICoders.decoder.decode(APITrip.self, from: Data(json.utf8))
        XCTAssertEqual(trip.exchangeRate, Decimal(string: "1.5"))
    }

    func testCaptureResponseNullAmountDraft() throws {
        let json = """
        {"declined":false,"message":null,"card":{"tripID":"\(kUUID)",
         "draft":{"merchant":"Konbini","amount":null,"currencyCode":"JPY",
                  "categoryRaw":null,"date":null,"source":"photo"},
         "gaps":[{"field":"amount","reason":"unreadable","prompt":"How much?","options":[]}],
         "canSave":false}}
        """
        let res = try APICoders.decoder.decode(APICaptureResponse.self, from: Data(json.utf8))
        XCTAssertFalse(res.declined)
        XCTAssertNil(res.card?.draft.amount)            // never guessed
        XCTAssertEqual(res.card?.canSave, false)
        XCTAssertEqual(res.card?.gaps.first?.field, "amount")
    }

    func testStatsDecodesDecimalTotals() throws {
        let json = """
        {"scope":"all","total":"48230.50","billCount":17,
         "byCategory":[{"category":"food","amount":"12840.00"}]}
        """
        let stats = try APICoders.decoder.decode(APIStats.self, from: Data(json.utf8))
        XCTAssertEqual(stats.total, Decimal(string: "48230.50"))
        XCTAssertEqual(stats.byCategory.first?.amount, Decimal(string: "12840.00"))
    }

    func testConfirmRequestEncodesNilAmountAsNull() throws {
        let req = APIConfirmRequest(tripID: UUID(uuidString: kUUID)!, merchant: "X", amount: nil,
                                    currencyCode: "JPY", date: nil, categoryRaw: nil, source: "text")
        let data = try APICoders.encoder.encode(req)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertTrue(obj?.keys.contains("amount") ?? false)        // key present
        XCTAssertTrue(obj?["amount"] is NSNull)                     // ...as null
    }

    func testConfirmRequestEncodesAmountAsString() throws {
        let req = APIConfirmRequest(tripID: UUID(uuidString: kUUID)!, merchant: "X",
                                    amount: Decimal(string: "2840.50"), currencyCode: "JPY",
                                    date: nil, categoryRaw: "food", source: "text")
        let data = try APICoders.encoder.encode(req)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["amount"] as? String, "2840.5")        // decimal STRING on the wire
    }
}

// MARK: - APIClient request engine (stubbed transport)

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// In-memory TokenStore for engine tests (actor → safe under concurrency).
actor StubTokenStore: TokenStore {
    private var access: String?
    private var refresh: String?
    private(set) var updateCount = 0
    private(set) var cleared = false
    init(access: String? = nil, refresh: String? = nil) { self.access = access; self.refresh = refresh }
    func accessToken() async -> String? { access }
    func refreshToken() async -> String? { refresh }
    func update(_ tokens: APIAuthTokens) async {
        access = tokens.accessToken; refresh = tokens.refreshToken; updateCount += 1
    }
    func clear() async { access = nil; refresh = nil; cleared = true }
    func currentAccess() -> String? { access }
}

final class APIClientEngineTests: XCTestCase {
    private func makeClient(store: TokenStore? = StubTokenStore(access: "stub-token"),
                            onSignedOut: (@Sendable () async -> Void)? = nil) -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        return APIClient(baseURL: URL(string: "https://test.local")!, session: session,
                         tokenStore: store, onSignedOut: onSignedOut)
    }

    override func tearDown() { StubURLProtocol.handler = nil; super.tearDown() }

    func testDecodesTripsOn200() async throws {
        StubURLProtocol.handler = { _ in
            let body = #"[{"id":"\#(kUUID)","name":"Osaka","currencyCode":"JPY","exchangeRate":"1","mascot":null,"rowVersion":1}]"#
            return (200, Data(body.utf8))
        }
        let trips = try await makeClient().trips()
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips.first?.currencyCode, "JPY")
        XCTAssertEqual(trips.first?.exchangeRate, Decimal(1))
    }

    func testMaps404ToNotFound() async {
        StubURLProtocol.handler = { _ in (404, Data(#"{"error":true,"reason":"trip not found"}"#.utf8)) }
        do {
            _ = try await makeClient().bills(tripID: UUID(uuidString: kUUID)!)
            XCTFail("expected notFound")
        } catch {
            XCTAssertEqual(error as? APIError, .notFound)
        }
    }

    func testMaps422ToUnprocessableWithReason() async {
        StubURLProtocol.handler = { _ in (422, Data(#"{"error":true,"reason":"amount required"}"#.utf8)) }
        let req = APIConfirmRequest(tripID: UUID(uuidString: kUUID)!, merchant: nil, amount: nil,
                                    currencyCode: "JPY", date: nil, categoryRaw: nil, source: "text")
        do {
            _ = try await makeClient().confirm(req)
            XCTFail("expected unprocessable")
        } catch {
            XCTAssertEqual(error as? APIError, .unprocessable("amount required"))
        }
    }

    func testMaps401ToUnauthorized() async {
        StubURLProtocol.handler = { _ in (401, Data(#"{"error":true,"reason":"expired"}"#.utf8)) }
        do {
            _ = try await makeClient().me()
            XCTFail("expected unauthorized")
        } catch {
            XCTAssertEqual(error as? APIError, .unauthorized)
        }
    }

    func testSendsBearerToken() async throws {
        nonisolated(unsafe) var seenAuth: String?
        StubURLProtocol.handler = { req in
            seenAuth = req.value(forHTTPHeaderField: "Authorization")
            return (200, Data(#"{"id":"\#(kUUID)","displayName":null,"email":null,"aiQuotaTier":"free"}"#.utf8))
        }
        _ = try await makeClient().me()
        XCTAssertEqual(seenAuth, "Bearer stub-token")
    }
}

// MARK: - Auth: single-flight refresh + Keychain vault

final class AuthClientTests: XCTestCase {
    private func makeClient(store: TokenStore,
                            onSignedOut: (@Sendable () async -> Void)? = nil) -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return APIClient(baseURL: URL(string: "https://test.local")!,
                         session: URLSession(configuration: config),
                         tokenStore: store, onSignedOut: onSignedOut)
    }

    override func tearDown() { StubURLProtocol.handler = nil; super.tearDown() }

    func testRefreshOn401ThenRetrySucceeds() async throws {
        let store = StubTokenStore(access: "old", refresh: "refresh-1")
        nonisolated(unsafe) var refreshCount = 0
        nonisolated(unsafe) var meCount = 0
        StubURLProtocol.handler = { req in
            if (req.url?.path ?? "").contains("/auth/refresh") {
                refreshCount += 1
                return (200, Data(#"{"accessToken":"new","refreshToken":"refresh-2","userID":"\#(kUUID)"}"#.utf8))
            }
            meCount += 1
            if req.value(forHTTPHeaderField: "Authorization") == "Bearer new" {
                return (200, Data(#"{"id":"\#(kUUID)","displayName":null,"email":null,"aiQuotaTier":"free"}"#.utf8))
            }
            return (401, Data(#"{"error":true,"reason":"expired"}"#.utf8))
        }
        let user = try await makeClient(store: store).me()
        XCTAssertEqual(user.aiQuotaTier, "free")
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(meCount, 2)                       // initial 401, then retry 200
        let newAccess = await store.currentAccess()
        XCTAssertEqual(newAccess, "new")                 // store updated by refresh
    }

    func testConcurrent401sShareOneRefresh() async throws {
        let store = StubTokenStore(access: "old", refresh: "refresh-1")
        nonisolated(unsafe) var refreshCount = 0
        StubURLProtocol.handler = { req in
            if (req.url?.path ?? "").contains("/auth/refresh") {
                refreshCount += 1
                Thread.sleep(forTimeInterval: 0.3)       // widen the window so all 401s queue on one refresh
                return (200, Data(#"{"accessToken":"new","refreshToken":"r2","userID":"\#(kUUID)"}"#.utf8))
            }
            if req.value(forHTTPHeaderField: "Authorization") == "Bearer new" {
                return (200, Data(#"{"id":"\#(kUUID)","displayName":null,"email":null,"aiQuotaTier":"free"}"#.utf8))
            }
            return (401, Data(#"{"error":true,"reason":"expired"}"#.utf8))
        }
        let client = makeClient(store: store)
        async let a = client.me()
        async let b = client.me()
        async let c = client.me()
        let users = try await [a, b, c]
        XCTAssertEqual(users.count, 3)
        XCTAssertEqual(refreshCount, 1)                  // single-flight
    }

    func testRefreshFailureSignsOut() async {
        let store = StubTokenStore(access: "old", refresh: "bad")
        nonisolated(unsafe) var signedOut = false
        StubURLProtocol.handler = { _ in (401, Data(#"{"error":true,"reason":"expired"}"#.utf8)) }
        let client = makeClient(store: store, onSignedOut: { signedOut = true })
        do {
            _ = try await client.me()
            XCTFail("expected unauthorized")
        } catch {
            XCTAssertEqual(error as? APIError, .unauthorized)
        }
        XCTAssertTrue(signedOut)                          // AuthSession will clear the vault
    }

    func testKeychainVaultRoundTripIfAvailable() async throws {
        // Skip cleanly if the test host lacks Keychain entitlement (sim CI).
        let probe = "probe_\(UUID().uuidString)"
        do { try KeychainStore.set("ok", account: probe); try KeychainStore.delete(account: probe) }
        catch { throw XCTSkip("Keychain unavailable in this host: \(error)") }

        let vault = TokenVault()
        await vault.clear()
        await vault.update(APIAuthTokens(accessToken: "acc", refreshToken: "ref",
                                         userID: UUID(uuidString: kUUID)!))
        let a = await vault.accessToken()
        let r = await vault.refreshToken()
        XCTAssertEqual(a, "acc")
        XCTAssertEqual(r, "ref")
        XCTAssertEqual(vault.userID(), UUID(uuidString: kUUID))
        await vault.clear()
        let cleared = await vault.accessToken()
        XCTAssertNil(cleared)                             // no tokens linger after sign-out
    }
}
