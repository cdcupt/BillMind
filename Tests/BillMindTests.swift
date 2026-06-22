import XCTest
import SwiftUI
import SwiftData
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

// MARK: - Image Downscale Tests (bounds the photo-upload payload — the 413 fix)

final class ImageDownscaleTests: XCTestCase {
    private func solidImage(_ size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1   // pixel size == point size, matching the helper
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testDownscaleBoundsLongestEdgeAndPreservesAspect() {
        let big = solidImage(CGSize(width: 4000, height: 3000))
        let small = big.downscaled(maxEdge: 2048)

        // Longest edge is bounded by maxEdge.
        XCTAssertLessThanOrEqual(max(small.size.width, small.size.height), 2048)

        // Aspect ratio preserved (4000/3000) within a small epsilon (rounding).
        let expectedRatio = 4000.0 / 3000.0
        let actualRatio = small.size.width / small.size.height
        XCTAssertEqual(actualRatio, expectedRatio, accuracy: 0.01)

        // An already-small image is returned unchanged.
        let alreadySmall = solidImage(CGSize(width: 800, height: 600))
        let unchanged = alreadySmall.downscaled(maxEdge: 2048)
        XCTAssertEqual(unchanged.size, CGSize(width: 800, height: 600))
    }
}

// MARK: - AppSettings Tests

final class AppSettingsTests: XCTestCase {
    func testDefaultConsentIsFalse() {
        let settings = AppSettings()
        XCTAssertFalse(settings.hasConsentedToAIDataSharing)
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

// MARK: - AuthSession state machine

@MainActor
final class AuthSessionTests: XCTestCase {
    private func keychainAvailable() -> Bool {
        let probe = "probe_\(UUID().uuidString)"
        do { try KeychainStore.set("ok", account: probe); try KeychainStore.delete(account: probe); return true }
        catch { return false }
    }

    private func stubSession(_ handler: @escaping (URLRequest) -> (Int, Data)) -> URLSession {
        StubURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override func tearDown() { StubURLProtocol.handler = nil; super.tearDown() }

    func testSignInThenSignOutDrivesStateAndVault() async throws {
        try XCTSkipUnless(keychainAvailable(), "Keychain unavailable in this host")
        let session = stubSession { _ in
            (200, Data(#"{"accessToken":"a","refreshToken":"r","userID":"\#(kUUID)"}"#.utf8))
        }
        let vault = TokenVault()
        await vault.clear()
        let auth = AuthSession(baseURL: URL(string: "https://test.local")!, session: session, vault: vault)

        await auth.signIn(provider: "apple", idToken: "stub-identity-token")
        XCTAssertEqual(auth.state, .signedIn(UUID(uuidString: kUUID)!))
        XCTAssertNil(auth.errorMessage)
        let access = await vault.accessToken()
        XCTAssertEqual(access, "a")

        await auth.signOut()
        XCTAssertEqual(auth.state, .signedOut)
        let cleared = await vault.accessToken()
        XCTAssertNil(cleared)
    }

    func testSignInFailureSetsErrorNotSignedIn() async throws {
        try XCTSkipUnless(keychainAvailable(), "Keychain unavailable in this host")
        let session = stubSession { _ in (401, Data(#"{"error":true,"reason":"bad token"}"#.utf8)) }
        let vault = TokenVault()
        await vault.clear()
        let auth = AuthSession(baseURL: URL(string: "https://test.local")!, session: session, vault: vault)

        await auth.signIn(provider: "apple", idToken: "bad")
        if case .signedIn = auth.state { XCTFail("should not be signed in") }
        XCTAssertNotNil(auth.errorMessage)
    }

    func testBootstrapSignedOutWhenNoToken() async throws {
        try XCTSkipUnless(keychainAvailable(), "Keychain unavailable in this host")
        let vault = TokenVault()
        await vault.clear()
        let auth = AuthSession(vault: vault)
        auth.bootstrap()
        XCTAssertEqual(auth.state, .signedOut)
    }

    func testDeleteAccountClearsSessionOnSuccess() async throws {
        try XCTSkipUnless(keychainAvailable(), "Keychain unavailable in this host")
        let session = stubSession { _ in (204, Data()) }   // DELETE /v1/account → 204
        let vault = TokenVault()
        await vault.update(APIAuthTokens(accessToken: "a", refreshToken: "r",
                                         userID: UUID(uuidString: kUUID)!))
        let auth = AuthSession(baseURL: URL(string: "https://test.local")!, session: session, vault: vault)

        let ok = await auth.deleteAccount()
        XCTAssertTrue(ok)
        XCTAssertEqual(auth.state, .signedOut)
        let access = await vault.accessToken()
        XCTAssertNil(access)                                // tokens wiped after deletion
    }
}

// MARK: - SwiftData cache schema V2 (sync metadata)

final class SchemaV2Tests: XCTestCase {
    @MainActor
    func testV2InsertHasSyncDefaultsAndPersists() throws {
        let schema = Schema(BillMindSchemaV2.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema,
                                           migrationPlan: BillMindMigrationPlan.self,
                                           configurations: [config])
        let ctx = container.mainContext

        let journal = Journal(name: "Osaka", currency: "JPY")
        let bill = BillRecord(amount: Decimal(string: "19.99")!, category: .food, merchant: "Ichiran")
        bill.journal = journal
        ctx.insert(journal)
        ctx.insert(bill)
        try ctx.save()

        // New rows start as local, unsynced, not deleted.
        XCTAssertNil(bill.serverID)
        XCTAssertEqual(bill.rowVersion, 0)
        XCTAssertFalse(bill.isDeleted)
        XCTAssertEqual(bill.syncState, .local)
        XCTAssertNil(journal.serverID)
        XCTAssertEqual(journal.syncState, .local)
        XCTAssertEqual(bill.amount, Decimal(string: "19.99"))   // exact: money is now a stored Decimal

        // Sync metadata round-trips.
        bill.serverID = UUID(uuidString: kUUID)
        bill.rowVersion = 3
        bill.updatedAt = Date(timeIntervalSince1970: 1_775_210_400)
        bill.syncState = .synced
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<BillRecord>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.serverID, UUID(uuidString: kUUID))
        XCTAssertEqual(fetched.first?.rowVersion, 3)
        XCTAssertEqual(fetched.first?.syncState, .synced)
    }

    func testSyncCursorRoundTrip() {
        SyncCursor.reset()
        XCTAssertEqual(SyncCursor.value, 0)            // absent → full pull
        SyncCursor.value = 1_775_210_400
        XCTAssertEqual(SyncCursor.value, 1_775_210_400, accuracy: 0.001)
        SyncCursor.reset()
        XCTAssertEqual(SyncCursor.value, 0)
    }
}

// MARK: - SyncEngine (delta pull/push + conflicts)

actor MockSyncAPI: SyncAPI {
    private let delta: APISyncDelta
    private let pushResult: APISyncPushResult
    private(set) var pushedBills: [APIBillUpsert] = []
    private(set) var createdTripNames: [String] = []
    private(set) var renamedTrips: [(id: UUID, name: String)] = []
    private(set) var deletedTripIDs: [UUID] = []
    private(set) var pullCount = 0
    private(set) var pushCount = 0

    init(delta: APISyncDelta,
         pushResult: APISyncPushResult = APISyncPushResult(appliedBills: 0, conflicts: [])) {
        self.delta = delta
        self.pushResult = pushResult
    }

    func createTrip(_ req: APICreateTripRequest) async throws -> APITrip {
        createdTripNames.append(req.name)
        return APITrip(id: UUID(), name: req.name, currencyCode: req.currencyCode,
                       exchangeRate: 1, mascot: req.mascot, rowVersion: 1)
    }

    func updateTrip(_ id: UUID, _ req: APIUpdateTripRequest) async throws -> APITrip {
        renamedTrips.append((id: id, name: req.name))
        return APITrip(id: id, name: req.name, currencyCode: "JPY",
                       exchangeRate: 1, mascot: nil, rowVersion: 2)
    }

    func deleteTrip(_ id: UUID) async throws { deletedTripIDs.append(id) }

    func syncPull(since cursor: Double) async throws -> APISyncDelta { pullCount += 1; return delta }
    func syncPush(_ push: APISyncPush) async throws -> APISyncPushResult {
        pushCount += 1
        pushedBills = push.bills ?? []
        return pushResult
    }
}

final class SyncEngineTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(BillMindSchemaV2.models)
        return try ModelContainer(for: schema,
                                  configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    private func tripSync(_ id: UUID, name: String = "Osaka", deleted: Bool = false) -> APITripSync {
        APITripSync(id: id, name: name, currencyCode: "JPY", exchangeRate: 1, mascot: nil,
                    rowVersion: 1, updatedAt: Date(timeIntervalSince1970: 1_700_000_000), deleted: deleted)
    }

    private func billSync(_ id: UUID, trip: UUID, merchant: String?, amount: Decimal,
                          rowVersion: Int = 1, deleted: Bool = false) -> APIBillSync {
        APIBillSync(id: id, tripID: trip, merchant: merchant, amount: amount, currencyCode: "JPY",
                    date: Date(timeIntervalSince1970: 1_700_000_000), categoryRaw: "food", source: "text",
                    notes: nil, rowVersion: rowVersion, updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    deleted: deleted)
    }

    override func tearDown() { SyncCursor.reset(); super.tearDown() }

    func testFullPullHydratesFromEmpty() async throws {
        SyncCursor.reset()
        let container = try makeContainer()
        let tripID = UUID(), billID = UUID()
        let delta = APISyncDelta(trips: [tripSync(tripID)],
                                 bills: [billSync(billID, trip: tripID, merchant: "Ichiran", amount: Decimal(string: "2840")!)],
                                 cursor: 100)
        let outcome = try await SyncEngine(container: container, api: MockSyncAPI(delta: delta)).sync()
        XCTAssertEqual(outcome.pulledTrips, 1)
        XCTAssertEqual(outcome.pulledBills, 1)

        let ctx = ModelContext(container)
        let journals = try ctx.fetch(FetchDescriptor<Journal>())
        let bills = try ctx.fetch(FetchDescriptor<BillRecord>())
        XCTAssertEqual(journals.first?.serverID, tripID)
        XCTAssertEqual(journals.first?.syncState, .synced)
        XCTAssertEqual(bills.first?.serverID, billID)
        XCTAssertEqual(bills.first?.journal?.serverID, tripID)   // linked to its trip
        XCTAssertEqual(SyncCursor.value, 100)
    }

    func testTombstoneDeletesLocalRow() async throws {
        SyncCursor.reset()
        let container = try makeContainer()
        let tripID = UUID(), billID = UUID()
        let seed = ModelContext(container)
        let j = Journal(name: "Osaka", currency: "JPY"); j.serverID = tripID; j.syncState = .synced
        let b = BillRecord(amount: 100, category: .food); b.serverID = billID; b.journal = j; b.syncState = .synced
        seed.insert(j); seed.insert(b); try seed.save()

        let delta = APISyncDelta(trips: [], bills: [billSync(billID, trip: tripID, merchant: nil, amount: 100, rowVersion: 2, deleted: true)], cursor: 200)
        try await SyncEngine(container: container, api: MockSyncAPI(delta: delta)).sync()

        let ctx = ModelContext(container)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<BillRecord>()).count, 0)   // tombstone removed it
    }

    func testPushUploadsDirtyBillsAndMarksSynced() async throws {
        SyncCursor.reset()
        let container = try makeContainer()
        let tripID = UUID()
        let seed = ModelContext(container)
        let j = Journal(name: "Osaka", currency: "JPY"); j.serverID = tripID; j.syncState = .synced
        let b = BillRecord(amount: 50, category: .food, merchant: "Konbini"); b.journal = j; b.syncState = .local
        seed.insert(j); seed.insert(b); try seed.save()
        let localBillID = b.id

        let mock = MockSyncAPI(delta: APISyncDelta(trips: [], bills: [], cursor: 10),
                               pushResult: APISyncPushResult(appliedBills: 1, conflicts: []))
        let outcome = try await SyncEngine(container: container, api: mock).sync()
        XCTAssertEqual(outcome.pushedBills, 1)

        let pushed = await mock.pushedBills
        XCTAssertEqual(pushed.count, 1)
        XCTAssertEqual(pushed.first?.id, localBillID)             // local id is the upsert id
        XCTAssertEqual(pushed.first?.tripID, tripID)

        let ctx = ModelContext(container)
        let bill = try ctx.fetch(FetchDescriptor<BillRecord>()).first
        XCTAssertEqual(bill?.serverID, localBillID)
        XCTAssertEqual(bill?.syncState, .synced)
    }

    func testConflictOverwritesLocalFromPull() async throws {
        SyncCursor.reset()
        let container = try makeContainer()
        let tripID = UUID(), billID = UUID()
        let seed = ModelContext(container)
        let j = Journal(name: "Osaka", currency: "JPY"); j.serverID = tripID; j.syncState = .synced
        let b = BillRecord(amount: 50, category: .food, merchant: "LocalMerchant")
        b.serverID = billID; b.rowVersion = 1; b.journal = j; b.syncState = .local
        seed.insert(j); seed.insert(b); try seed.save()

        // Push reports a conflict for this bill; the pull carries the server's newer version.
        let delta = APISyncDelta(trips: [],
                                 bills: [billSync(billID, trip: tripID, merchant: "ServerMerchant", amount: 99, rowVersion: 5)],
                                 cursor: 300)
        let mock = MockSyncAPI(delta: delta, pushResult: APISyncPushResult(appliedBills: 0, conflicts: [billID]))
        let outcome = try await SyncEngine(container: container, api: mock).sync()
        XCTAssertEqual(outcome.conflicts, 1)

        let ctx = ModelContext(container)
        let bill = try ctx.fetch(FetchDescriptor<BillRecord>()).first
        XCTAssertEqual(bill?.merchant, "ServerMerchant")         // local overwritten by server
        XCTAssertEqual(bill?.rowVersion, 5)
        XCTAssertEqual(bill?.syncState, .synced)
    }

    func testCreatesPendingTripThenPushesItsBill() async throws {
        SyncCursor.reset()
        let container = try makeContainer()
        let seed = ModelContext(container)
        let j = Journal(name: "Lisbon", currency: "EUR")        // serverID nil, syncState .local
        let b = BillRecord(amount: 30, category: .food, merchant: "Pastel")
        b.journal = j; b.syncState = .local
        seed.insert(j); seed.insert(b); try seed.save()

        let mock = MockSyncAPI(delta: APISyncDelta(trips: [], bills: [], cursor: 5),
                               pushResult: APISyncPushResult(appliedBills: 1, conflicts: []))
        let outcome = try await SyncEngine(container: container, api: mock).sync()
        XCTAssertEqual(outcome.createdTrips, 1)
        XCTAssertEqual(outcome.pushedBills, 1)

        let createdNames = await mock.createdTripNames
        XCTAssertEqual(createdNames, ["Lisbon"])                 // local trip created on the server
        let pushed = await mock.pushedBills
        XCTAssertEqual(pushed.count, 1)                          // its bill is now pushable
        XCTAssertNotNil(pushed.first?.tripID)

        let ctx = ModelContext(container)
        let journal = try ctx.fetch(FetchDescriptor<Journal>()).first
        XCTAssertNotNil(journal?.serverID)
        XCTAssertEqual(journal?.syncState, .synced)
    }

    func testLocalRenamePushesToServerAndMarksSynced() async throws {
        SyncCursor.reset()
        let container = try makeContainer()
        let serverID = UUID()
        let seed = ModelContext(container)
        // A trip already on the server, renamed locally (serverID set, syncState .local).
        let renamed = Journal(name: "Kyoto", currency: "JPY")
        renamed.serverID = serverID; renamed.rowVersion = 1; renamed.syncState = .local
        // A clean .synced trip with no local edit must NOT generate a spurious PATCH.
        let clean = Journal(name: "Tokyo", currency: "JPY")
        clean.serverID = UUID(); clean.rowVersion = 1; clean.syncState = .synced
        seed.insert(renamed); seed.insert(clean); try seed.save()

        let mock = MockSyncAPI(delta: APISyncDelta(trips: [], bills: [], cursor: 0))
        try await SyncEngine(container: container, api: mock).sync()

        let renames = await mock.renamedTrips
        XCTAssertEqual(renames.count, 1)                         // only the dirty trip is PATCHed
        XCTAssertEqual(renames.first?.id, serverID)
        XCTAssertEqual(renames.first?.name, "Kyoto")

        let ctx = ModelContext(container)
        let pushed = try ctx.fetch(FetchDescriptor<Journal>(
            predicate: #Predicate { $0.serverID == serverID })).first
        XCTAssertEqual(pushed?.syncState, .synced)              // now reconciled
        XCTAssertEqual(pushed?.rowVersion, 2)                   // stored from the server's response
    }
}

// MARK: - Capture re-point: server card → local draft mapping

final class ServerDraftMappingTests: XCTestCase {
    func testMapsServerCardDraft() {
        let dto = APIBillDraft(merchant: "Ichiran", amount: Decimal(string: "2840")!,
                               currencyCode: "JPY", categoryRaw: "food",
                               date: Date(timeIntervalSince1970: 1_700_000_000), source: "photo")
        let draft = BillDraft(serverDraft: dto, fallbackCurrency: "USD")
        XCTAssertEqual(draft.merchant, "Ichiran")
        XCTAssertEqual(draft.amount, Decimal(string: "2840"))
        XCTAssertEqual(draft.currencyCode, "JPY")
        XCTAssertEqual(draft.categoryRaw, "food")
        XCTAssertEqual(draft.source, .photo)
    }

    func testNilAmountPreservedAndCurrencyFallback() {
        let dto = APIBillDraft(merchant: "Blurry", amount: nil, currencyCode: "",
                               categoryRaw: nil, date: nil, source: "photo")
        let draft = BillDraft(serverDraft: dto, fallbackCurrency: "JPY")
        XCTAssertNil(draft.amount)                       // never guessed
        XCTAssertEqual(draft.currencyCode, "JPY")        // fallback when server gave empty
        XCTAssertNil(draft.categoryRaw)
    }
}

// MARK: - Agent chat SSE parsing

final class AgentSSETests: XCTestCase {
    func testParsesToolResultThenMessageThenDone() {
        let raw = "event: tool_result\ndata: {\"total\":\"48230.50\"}\n\n"
            + "event: message\ndata: {\"text\":\"You've spent ¥48,230 so far.\"}\n\n"
            + "event: done\ndata: {}\n\n"
        let events = APIClient.parseSSE(raw)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0], .toolResult(resultJSON: "{\"total\":\"48230.50\"}"))
        XCTAssertEqual(events[1], .message("You've spent ¥48,230 so far."))
        XCTAssertEqual(events[2], .done)
    }

    func testParsesLoneDeclinedFrame() {
        let raw = "event: declined\ndata: {\"message\":\"I can only help with travel and money.\"}\n\n"
        XCTAssertEqual(APIClient.parseSSE(raw),
                       [.declined("I can only help with travel and money.")])
    }

    func testMessageTextTakenVerbatimNotParsedForFigures() {
        // Figures live only in tool_result; the message text is passed through as-is.
        let events = APIClient.parseSSE("event: message\ndata: {\"text\":\"about 50\"}\n\n")
        XCTAssertEqual(events, [.message("about 50")])
    }

    func testTrailingFrameWithoutBlankLineIsFlushed() {
        let events = APIClient.parseSSE("event: done\ndata: {}")
        XCTAssertEqual(events, [.done])
    }
}

// MARK: - Untangle held-batch client logic (Slice ②)

/// A `RecognitionAPI` double for held-batch tests. `untangle` returns a canned plan
/// (or throws to exercise the degraded path); call counts let tests assert the
/// fast path never reaches the wire.
actor MockUntangleAPI: RecognitionAPI {
    enum Mode: Sendable {
        case plan(APIUntangleResponse)
        /// Fuse ALL inputs into one resolved card with the given amount (amount nil ⇒
        /// amountTrace null). Built from the live request ids so it always partitions.
        case fuseAll(amount: Decimal?, merchant: String)
        case throwTransport
    }
    private let mode: Mode
    private(set) var recognizeCount = 0
    private(set) var untangleCount = 0
    /// Card ids the coordinator actually sent on the last untangle request — lets a
    /// test assert that in-flight/failed cards are excluded from the inputs.
    private(set) var lastUntangleInputIDs: [UUID] = []

    init(_ mode: Mode) { self.mode = mode }

    func recognize(_ req: APICaptureRequest) async throws -> APICaptureResponse {
        recognizeCount += 1
        return CaptureResponseFixtures.empty
    }

    func untangle(_ req: APIUntangleRequest) async throws -> APIUntangleResponse {
        untangleCount += 1
        lastUntangleInputIDs = req.inputs.map(\.cardID)
        switch mode {
        case .plan(let r):
            return r
        case .throwTransport:
            throw APIError.transport("simulated timeout")
        case .fuseAll(let amount, let merchant):
            let ids = req.inputs.map(\.cardID)
            let trace = amount == nil ? nil : APIAmountTrace(sourceCardID: ids[0], field: "amount")
            let resolved = APIBillDraft(merchant: merchant, amount: amount, currencyCode: "JPY",
                categoryRaw: "food", date: Date(timeIntervalSince1970: 1_700_000_000), source: "text")
            return APIUntangleResponse(declined: false, message: nil,
                fuseGroups: [APIFuseGroup(groupID: UUID(), sourceCardIDs: ids,
                    resolvedDraft: resolved, amountTrace: trace, reason: "fused", confidence: 0.95)],
                duplicateGroups: [], cleanCardIDs: [])
        }
    }
}

enum CaptureResponseFixtures {
    static let empty = APICaptureResponse(declined: false, message: nil, card: nil, cards: [])
}

/// Pure-session tests: transitions + groups-as-views, no UI/network/DB.
final class HeldBatchSessionTests: XCTestCase {
    private func validator(currency: String = "JPY") -> BillValidator {
        BillValidator(knownCategoryRaws: Set(BillCategory.allCases.map(\.rawValue)),
                      journalCurrencyCode: currency, today: Date(timeIntervalSince1970: 1_700_000_000))
    }

    private func draft(_ id: UUID, amount: Decimal?, merchant: String?,
                       currency: String = "JPY", source: DraftSource = .text) -> BillDraft {
        BillDraft(id: id, merchant: merchant, amount: amount, currencyCode: currency,
                  date: Date(timeIntervalSince1970: 1_700_000_000), categoryRaw: "food",
                  source: source)
    }

    /// Enqueue a card and force it into `.review` with the given draft.
    private func seedReviewCard(_ session: inout RecordingSession, amount: Decimal?,
                                merchant: String?, source: DraftSource = .text) -> UUID {
        let id = session.enqueue(source: source)
        _ = session.completeExtraction(cardID: id,
            draft: draft(id, amount: amount, merchant: merchant, source: source))
        return id
    }

    private func dto(_ d: BillDraft) -> APIBillDraft {
        APIBillDraft(merchant: d.merchant, amount: d.amount, currencyCode: d.currencyCode,
                     categoryRaw: d.categoryRaw, date: d.date, source: d.source.rawValue)
    }

    func testBatchPhaseTransitions() {
        var session = RecordingSession(validator: validator())
        XCTAssertEqual(session.batchPhase, .adding)
        XCTAssertFalse(session.hasActiveBatch)

        session.markDoneAdding()
        XCTAssertEqual(session.batchPhase, .untangling)
        XCTAssertTrue(session.hasActiveBatch)

        // Idempotent: re-tap while untangling is a no-op (stays untangling).
        session.markDoneAdding()
        XCTAssertEqual(session.batchPhase, .untangling)

        session.applyUntangle(APIUntangleResponse(declined: false, message: nil,
            fuseGroups: [], duplicateGroups: [], cleanCardIDs: []))
        XCTAssertEqual(session.batchPhase, .reviewing)

        // Illegal jump: markDoneAdding from reviewing does not rewind to untangling.
        session.markDoneAdding()
        XCTAssertEqual(session.batchPhase, .reviewing)
    }

    func testGroupsAreViewsNotMutations() throws {
        var session = RecordingSession(validator: validator())
        let a = seedReviewCard(&session, amount: 1200, merchant: "Photo half")
        let b = seedReviewCard(&session, amount: 1200, merchant: "Note half")
        let beforeA = try XCTUnwrap(session.card(a)).draft
        let beforeB = try XCTUnwrap(session.card(b)).draft

        let gid = UUID()
        let resolved = draft(UUID(), amount: 1200, merchant: "Fused")
        session.markDoneAdding()
        session.applyUntangle(APIUntangleResponse(declined: false, message: nil,
            fuseGroups: [APIFuseGroup(groupID: gid, sourceCardIDs: [a, b],
                resolvedDraft: dto(resolved),
                amountTrace: APIAmountTrace(sourceCardID: a, field: "amount"),
                reason: "note completes photo", confidence: 0.9)],
            duplicateGroups: [], cleanCardIDs: []))
        XCTAssertEqual(session.groups.count, 1)

        // Split is a pure discard — the two member drafts restore byte-identical.
        session.split(groupID: gid)
        XCTAssertTrue(session.groups.isEmpty)
        XCTAssertEqual(try XCTUnwrap(session.card(a)).draft, beforeA)
        XCTAssertEqual(try XCTUnwrap(session.card(b)).draft, beforeB)
        XCTAssertEqual(Set(session.plainReviewCardIDs), [a, b])

        // Keep-both on a dup group is likewise a pure discard.
        let dupID = UUID()
        session.applyUntangle(APIUntangleResponse(declined: false, message: nil,
            fuseGroups: [],
            duplicateGroups: [APIDuplicateGroup(groupID: dupID, memberCardIDs: [a, b],
                survivorCardID: a, tier: "sameDetails", reason: "same merchant+amount+date")],
            cleanCardIDs: []))
        session.keepBoth(groupID: dupID)
        XCTAssertTrue(session.groups.isEmpty)
        XCTAssertEqual(try XCTUnwrap(session.card(a)).draft, beforeA)
        XCTAssertEqual(try XCTUnwrap(session.card(b)).draft, beforeB)
    }

    func testKeepOneSetsAsideReversibly() {
        var session = RecordingSession(validator: validator())
        let a = seedReviewCard(&session, amount: 500, merchant: "Dup A")
        let b = seedReviewCard(&session, amount: 500, merchant: "Dup B")
        let dupID = UUID()
        session.markDoneAdding()
        session.applyUntangle(APIUntangleResponse(declined: false, message: nil, fuseGroups: [],
            duplicateGroups: [APIDuplicateGroup(groupID: dupID, memberCardIDs: [a, b],
                survivorCardID: a, tier: "samePhoto", reason: "same photo")],
            cleanCardIDs: []))
        session.keepOne(groupID: dupID, survivor: a)
        // Survivor stays a plain review card; the other is set aside (not reviewable).
        XCTAssertEqual(session.plainReviewCardIDs, [a])
        XCTAssertEqual(session.card(b)?.state, .discarded)
    }

    func testPartitionFailOpen() {
        var session = RecordingSession(validator: validator())
        let a = seedReviewCard(&session, amount: 300, merchant: "Real card")
        let ghost = UUID()   // a cardID the server returns that the client no longer holds
        session.markDoneAdding()
        // Plan references a stale ghost id in a fuse with the live card → fail open.
        session.applyUntangle(APIUntangleResponse(declined: false, message: nil,
            fuseGroups: [APIFuseGroup(groupID: UUID(), sourceCardIDs: [ghost],
                resolvedDraft: dto(draft(UUID(), amount: 999, merchant: "Ghost")),
                amountTrace: nil, reason: "x", confidence: 0.5)],
            duplicateGroups: [], cleanCardIDs: [a]))
        // The ghost-only fuse is dropped; the live card is a plain review card.
        XCTAssertTrue(session.groups.isEmpty)
        XCTAssertEqual(session.plainReviewCardIDs, [a])
    }

    /// FIX 2: after filtering members against live cards, a fuse left with a single
    /// live member is INVALID (a fuse needs ≥2 sources). The whole group is dropped and
    /// the surviving live card fails open to a plain review card — never a 1-member fuse.
    func testInvalidGroupAfterPartitionFailsOpen() {
        var session = RecordingSession(validator: validator())
        let a = seedReviewCard(&session, amount: 300, merchant: "Real half")
        let ghost = UUID()   // a second source the client no longer holds (filtered out)
        session.markDoneAdding()
        // Plan fuses [a, ghost]; ghost is stale → only `a` survives filtering → 1 member.
        session.applyUntangle(APIUntangleResponse(declined: false, message: nil,
            fuseGroups: [APIFuseGroup(groupID: UUID(), sourceCardIDs: [a, ghost],
                resolvedDraft: dto(draft(UUID(), amount: 999, merchant: "Fused")),
                amountTrace: APIAmountTrace(sourceCardID: a, field: "amount"),
                reason: "x", confidence: 0.9)],
            duplicateGroups: [], cleanCardIDs: []))
        // The single-member fuse is dropped; `a` becomes a plain review card (fail open).
        XCTAssertTrue(session.groups.isEmpty)
        XCTAssertEqual(session.plainReviewCardIDs, [a])
        XCTAssertEqual(session.card(a)?.state, .review)
    }

    func testAmountTraceNullBlocksSave() throws {
        var session = RecordingSession(validator: validator())
        let a = seedReviewCard(&session, amount: nil, merchant: "Half A", source: .photo)
        let b = seedReviewCard(&session, amount: nil, merchant: "Half B", source: .text)
        let gid = UUID()
        session.markDoneAdding()
        // amountTrace == null ⇒ server omits the amount on the resolved draft.
        session.applyUntangle(APIUntangleResponse(declined: false, message: nil,
            fuseGroups: [APIFuseGroup(groupID: gid, sourceCardIDs: [a, b],
                resolvedDraft: dto(draft(UUID(), amount: nil, merchant: "Fused no amount")),
                amountTrace: nil, reason: "fused without a money source", confidence: 0.8)],
            duplicateGroups: [], cleanCardIDs: []))
        let newID = try XCTUnwrap(session.combine(groupID: gid))
        // The fused card has no amount → confirm blocks with amountRequired (never minted).
        XCTAssertThrowsError(try session.confirm(cardID: newID)) { error in
            XCTAssertEqual(error as? ConfirmError, .amountRequired)
        }
    }
}

/// Coordinator tests: the @MainActor save mapping + fast path + degraded path.
@MainActor
final class HeldBatchCoordinatorTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(BillMindSchemaV2.models)
        return try ModelContainer(for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    private func dto(merchant: String?, amount: Decimal?, source: String = "text") -> APIBillDraft {
        APIBillDraft(merchant: merchant, amount: amount, currencyCode: "JPY",
                     categoryRaw: "food", date: Date(timeIntervalSince1970: 1_700_000_000), source: source)
    }

    private func syncedJournal(_ ctx: ModelContext) -> Journal {
        let j = Journal(name: "Osaka", currency: "JPY")
        j.serverID = UUID(); j.syncState = .synced
        ctx.insert(j); try? ctx.save()
        return j
    }

    /// Deterministic poll-until: re-checks `condition` every ~5ms and returns as soon
    /// as it holds, `XCTFail`ing if `timeout` elapses first. Replaces fixed
    /// `Task.sleep` waits so each test blocks exactly as long as the async
    /// recognition/untangle Tasks actually need — fast when ready, no flaky delays.
    private func waitUntil(_ label: String = "",
                           timeout: TimeInterval = 2,
                           file: StaticString = #filePath, line: UInt = #line,
                           _ condition: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail("waitUntil timed out after \(timeout)s\(label.isEmpty ? "" : ": \(label)")",
                        file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 5_000_000)   // 5ms poll interval (not a fixed wait)
        }
    }

    /// Two held cards, fused into one, accepted, then saved: exactly one bill is
    /// persisted and the two member cards are set aside (never persisted). Drives the
    /// real coordinator path (markDoneAdding → mock untangle → combine → confirmAll).
    func testConfirmAllMapsOneFusedCardToOneBill() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let journal = syncedJournal(ctx)
        // The mock fuses ALL inputs into one resolved card with a real amount.
        let fusedAmount = try XCTUnwrap(Decimal(string: "1500"))
        let mock = MockUntangleAPI(.fuseAll(amount: fusedAmount, merchant: "Lunch"))
        let coord = RecordCoordinator(journal: journal, modelContext: ctx, recognizer: mock)

        coord.submitText("Lunch 1200 yen")
        coord.submitText("Same lunch, the drink")
        await waitUntil("both recognize Tasks reach .review") {
            coord.cards.count == 2 && coord.cards.allSatisfy { $0.state == .review }
        }
        XCTAssertEqual(coord.cards.count, 2)

        coord.markDoneAdding()
        await waitUntil("untangle round-trip") { coord.batchPhase == .reviewing }
        XCTAssertEqual(coord.batchPhase, .reviewing)
        XCTAssertEqual(coord.groups.count, 1)

        // Accept the fuse → one new review card; the two members are set aside.
        coord.combine(groupID: coord.groups[0].id)
        XCTAssertTrue(coord.groups.isEmpty)
        XCTAssertEqual(coord.plainReviewCards.count, 1)

        let blocked = coord.confirmAll()
        XCTAssertTrue(blocked.isEmpty)
        let bills = try ctx.fetch(FetchDescriptor<BillRecord>())
        XCTAssertEqual(bills.count, 1)                    // one fused card → one bill
        XCTAssertEqual(bills.first?.amount, Decimal(string: "1500"))   // amount unaltered
        XCTAssertEqual(bills.first?.merchant, "Lunch")
    }

    /// A fused card with `amountTrace == null` (server omitted the amount) cannot be
    /// saved — confirmAll reports it as blocked and no bill is written.
    func testConfirmAllBlocksFusedCardWithNullAmountTrace() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let journal = syncedJournal(ctx)
        let mock = MockUntangleAPI(.fuseAll(amount: nil, merchant: "No-amount fuse"))
        let coord = RecordCoordinator(journal: journal, modelContext: ctx, recognizer: mock)

        coord.submitText("A receipt half")
        coord.submitText("Another half")
        await waitUntil("both recognize Tasks reach .review") {
            coord.cards.count == 2 && coord.cards.allSatisfy { $0.state == .review }
        }
        coord.markDoneAdding()
        await waitUntil("untangle round-trip") { coord.groups.count == 1 }
        XCTAssertEqual(coord.groups.count, 1)

        let fusedID = coord.groups[0].id
        coord.combine(groupID: fusedID)
        let blocked = coord.confirmAll()
        XCTAssertEqual(blocked.count, 1)                  // amount required → blocked
        let bills = try ctx.fetch(FetchDescriptor<BillRecord>())
        XCTAssertEqual(bills.count, 0)                    // nothing minted, nothing saved
    }

    func testSingleInputFastPathBypassesUntangle() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let journal = syncedJournal(ctx)
        let mock = MockUntangleAPI(.plan(APIUntangleResponse(declined: false, message: nil,
            fuseGroups: [], duplicateGroups: [], cleanCardIDs: [])))
        let coord = RecordCoordinator(journal: journal, modelContext: ctx, recognizer: mock)

        coord.submitText("Coffee 480 yen today")
        await waitUntil("recognize Task settles to .review") { coord.cards.first?.state == .review }
        let id = try XCTUnwrap(coord.cards.first?.id)
        XCTAssertEqual(coord.cards.first?.state, .review)
        XCTAssertTrue(coord.allowsPerCardSave)           // per-card Save stays on
        XCTAssertFalse(coord.showsDoneAddingBar)         // no batch bar for a lone input

        // Done-adding is a no-op for a single card → never calls untangle.
        coord.markDoneAdding()
        XCTAssertEqual(coord.batchPhase, .adding)
        let untangleCalls = await mock.untangleCount
        XCTAssertEqual(untangleCalls, 0)

        // The instant per-card Save still works (the lone input writes one bill).
        let outcome = coord.confirm(cardID: id)
        XCTAssertEqual(outcome, .recorded)
        let bills = try ctx.fetch(FetchDescriptor<BillRecord>())
        XCTAssertEqual(bills.count, 1)
    }

    func testDegradedPathSavesPerCard() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let journal = syncedJournal(ctx)
        let mock = MockUntangleAPI(.throwTransport)     // untangle throws → degrade
        let coord = RecordCoordinator(journal: journal, modelContext: ctx, recognizer: mock)

        coord.submitText("Taxi 2000 yen")
        coord.submitText("Hotel 9000 yen")
        await waitUntil("both cards reach .review") {
            coord.cards.count == 2 && coord.cards.allSatisfy { $0.state == .review }
        }
        XCTAssertEqual(coord.cards.count, 2)

        coord.markDoneAdding()
        // Wait for the untangle Task to throw and degrade to reviewing.
        await waitUntil("untangle throws → degrade to reviewing") { coord.batchPhase == .reviewing }
        XCTAssertEqual(coord.batchPhase, .reviewing)
        XCTAssertNotNil(coord.errorMessage)              // surfaced the error
        XCTAssertEqual(coord.groups.count, 0)            // no groups → plain cards
        XCTAssertEqual(coord.plainReviewCards.count, 2)

        // Per-card Save still works in the degraded review.
        let blocked = coord.confirmAll()
        XCTAssertTrue(blocked.isEmpty)
        let bills = try ctx.fetch(FetchDescriptor<BillRecord>())
        XCTAssertEqual(bills.count, 2)
    }

    /// FIX 1: cards still claimed by an UNRESOLVED fuse/duplicate group are never
    /// persisted by confirmAll — they are reported as blocked (Save-all blocks until
    /// every group is touched). No hidden grouped member is written before resolution.
    func testConfirmAllSkipsUnresolvedGroupMembers() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let journal = syncedJournal(ctx)
        // The mock fuses ALL inputs into one pending fuse group (with a real amount).
        let fusedAmount = try XCTUnwrap(Decimal(string: "1500"))
        let mock = MockUntangleAPI(.fuseAll(amount: fusedAmount, merchant: "Lunch"))
        let coord = RecordCoordinator(journal: journal, modelContext: ctx, recognizer: mock)

        coord.submitText("Lunch 1200 yen")
        coord.submitText("Same lunch, the drink")
        await waitUntil("both cards reach .review") {
            coord.cards.count == 2 && coord.cards.allSatisfy { $0.state == .review }
        }
        let memberIDs = Set(coord.cards.map(\.id))

        coord.markDoneAdding()
        await waitUntil("untangle round-trip") { coord.groups.count == 1 }
        XCTAssertEqual(coord.groups.count, 1)            // one PENDING fuse group
        XCTAssertTrue(coord.plainReviewCards.isEmpty)    // both cards owned by the group

        // Save-all WITHOUT resolving the group: members are blocked, nothing persisted.
        let blocked = coord.confirmAll()
        XCTAssertEqual(Set(blocked), memberIDs)          // both grouped members blocked
        let bills = try ctx.fetch(FetchDescriptor<BillRecord>())
        XCTAssertEqual(bills.count, 0)                   // hidden grouped members never saved
    }

    /// FIX 1 (per-card path): the per-card `confirm` must NOT bypass the batch's group
    /// protections. A card claimed by a still-pending fuse/duplicate group is refused
    /// (.notReviewable) and never persisted via the per-card Save — closing the hole
    /// where a grouped member could be saved before its group is resolved. The only way
    /// to save it is to resolve the group first (here: combine), then save the result.
    func testPerCardConfirmRefusesGroupedMember() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let journal = syncedJournal(ctx)
        let fusedAmount = try XCTUnwrap(Decimal(string: "1500"))
        let mock = MockUntangleAPI(.fuseAll(amount: fusedAmount, merchant: "Lunch"))
        let coord = RecordCoordinator(journal: journal, modelContext: ctx, recognizer: mock)

        coord.submitText("Lunch 1200 yen")
        coord.submitText("Same lunch, the drink")
        await waitUntil("both cards reach .review") {
            coord.cards.count == 2 && coord.cards.allSatisfy { $0.state == .review }
        }

        coord.markDoneAdding()
        await waitUntil("untangle round-trip") { coord.groups.count == 1 }
        XCTAssertEqual(coord.groups.count, 1)            // one PENDING fuse group
        XCTAssertTrue(coord.plainReviewCards.isEmpty)    // both cards owned by the group

        // Try to save a grouped member directly via the per-card path: REFUSED, no bill.
        let groupedMemberID = try XCTUnwrap(coord.groups.first?.memberCardIDs.first)
        let refused = coord.confirm(cardID: groupedMemberID)
        XCTAssertEqual(refused, .notReviewable)          // claimed member cannot be saved
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<BillRecord>()).isEmpty)  // nothing persisted

        // Resolve the group (combine) → one plain review card; now the per-card Save works.
        let groupID = try XCTUnwrap(coord.groups.first?.id)
        coord.combine(groupID: groupID)
        XCTAssertTrue(coord.groups.isEmpty)
        XCTAssertEqual(coord.plainReviewCards.count, 1)
        let resolvedID = try XCTUnwrap(coord.plainReviewCards.first?.id)
        let outcome = coord.confirm(cardID: resolvedID)
        XCTAssertEqual(outcome, .recorded)               // saving works only after resolution
        let bills = try ctx.fetch(FetchDescriptor<BillRecord>())
        XCTAssertEqual(bills.count, 1)                   // exactly the resolved card
        XCTAssertEqual(bills.first?.amount, Decimal(string: "1500"))
    }

    /// FIX 3: only cards that reached `.review` feed the untangle request. A card still
    /// in flight (extracting) or failed must be excluded from the inputs.
    func testOnlyReviewCardsSentToUntangle() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let journal = syncedJournal(ctx)
        let mock = MockUntangleAPI(.plan(APIUntangleResponse(declined: false, message: nil,
            fuseGroups: [], duplicateGroups: [], cleanCardIDs: [])))
        let coord = RecordCoordinator(journal: journal, modelContext: ctx, recognizer: mock)

        // Two text cards land in .review via the local fallback (mock returns no card).
        coord.submitText("Taxi 2000 yen")
        coord.submitText("Hotel 9000 yen")
        // A photo card whose recognition returns nothing → it ends in .failed.
        coord.submitPhotos([UIImage()])
        // Two text cards reach .review and the photo card lands in .failed.
        await waitUntil("two .review + one .failed settle") {
            coord.cards.filter { $0.state == .review }.count == 2
                && coord.session.cards.contains { $0.state == .failed }
        }

        let reviewIDs = Set(coord.cards.filter { $0.state == .review }.map(\.id))
        let failedID = try XCTUnwrap(coord.session.cards.first { $0.state == .failed }?.id)
        XCTAssertEqual(reviewIDs.count, 2)               // the two text cards

        coord.markDoneAdding()
        // Untangle completes → the batch reaches .reviewing (the observable side effect).
        await waitUntil("untangle round-trip") { coord.batchPhase == .reviewing }
        let untangleCalls = await mock.untangleCount
        XCTAssertEqual(untangleCalls, 1)
        let sent = Set(await mock.lastUntangleInputIDs)
        XCTAssertEqual(sent, reviewIDs)                  // only .review cards sent
        XCTAssertFalse(sent.contains(failedID))          // failed card excluded
    }
}
