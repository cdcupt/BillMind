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
        // NOTE: BillRecord stores money as Double (amountDouble), so it is only
        // accurate to display precision (2dp), not exact Decimal. To be fixed when
        // capture writes exact server amounts (BillRecord.amount → stored Decimal).
        XCTAssertEqual((bill.amount as NSDecimalNumber).doubleValue, 19.99, accuracy: 0.005)

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
    private(set) var pullCount = 0
    private(set) var pushCount = 0

    init(delta: APISyncDelta,
         pushResult: APISyncPushResult = APISyncPushResult(appliedBills: 0, conflicts: [])) {
        self.delta = delta
        self.pushResult = pushResult
    }

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
}
