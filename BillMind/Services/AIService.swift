import Foundation
import UIKit

enum AIError: LocalizedError {
    case noAPIKey
    case invalidImage
    case invalidResponse(String)
    case httpError(Int, String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No API key configured"
        case .invalidImage: return "Could not process image"
        case .invalidResponse(let msg): return "Invalid response: \(msg)"
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        case .networkError(let err): return err.localizedDescription
        }
    }
}

final class AIService {

    /// Recognize a bill from one or more images using the configured AI provider
    func recognizeBill(
        images: [UIImage],
        provider: AIProvider,
        model: String,
        apiKey: String
    ) async throws -> AIRecognitionResult {
        guard !apiKey.isEmpty else { throw AIError.noAPIKey }

        // Convert images to JPEG base64
        let imageDataList = try images.map { image -> Data in
            guard let data = image.jpegData(compressionQuality: 0.8) else {
                throw AIError.invalidImage
            }
            return data
        }

        // Build request based on provider
        let (request, isGemini) = try buildRequest(
            imageDataList: imageDataList,
            provider: provider,
            model: model,
            apiKey: apiKey
        )

        // Execute
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? 0

        guard (200...299).contains(statusCode) else {
            let errorMsg = parseErrorMessage(data: data, isGemini: isGemini)
            throw AIError.httpError(statusCode, errorMsg)
        }

        // Parse response
        let text = try extractText(data: data, isGemini: isGemini)
        return try parseRecognitionResult(text)
    }

    // MARK: - Request Building

    private func buildRequest(
        imageDataList: [Data],
        provider: AIProvider,
        model: String,
        apiKey: String
    ) throws -> (URLRequest, Bool) {
        if provider.usesGeminiFormat {
            return (try buildGeminiRequest(imageDataList: imageDataList, model: model, apiKey: apiKey), true)
        } else {
            return (try buildOpenAIRequest(imageDataList: imageDataList, provider: provider, model: model, apiKey: apiKey), false)
        }
    }

    private func buildGeminiRequest(imageDataList: [Data], model: String, apiKey: String) throws -> URLRequest {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-goog-api-key")
        request.timeoutInterval = 60

        // Build parts: images + text prompt
        var parts: [[String: Any]] = imageDataList.map { data in
            ["inlineData": ["mimeType": "image/jpeg", "data": data.base64EncodedString()]]
        }
        parts.append(["text": Prompts.billRecognition])

        let body: [String: Any] = [
            "contents": [["parts": parts]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func buildOpenAIRequest(imageDataList: [Data], provider: AIProvider, model: String, apiKey: String) throws -> URLRequest {
        let url = URL(string: provider.baseURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        // Build content array: images + text
        var content: [[String: Any]] = imageDataList.map { data in
            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(data.base64EncodedString())"]]
        }
        content.append(["type": "text", "text": Prompts.billRecognition])

        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": content]],
            "max_tokens": 2048
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Response Parsing

    private func extractText(data: Data, isGemini: Bool) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.invalidResponse("Cannot parse JSON")
        }

        if isGemini {
            guard let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else {
                throw AIError.invalidResponse("Missing candidates")
            }
            for part in parts {
                if let text = part["text"] as? String { return text }
            }
            throw AIError.invalidResponse("No text in response")
        } else {
            guard let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw AIError.invalidResponse("Missing choices")
            }
            return content
        }
    }

    private func parseRecognitionResult(_ text: String) throws -> AIRecognitionResult {
        // Clean up: remove markdown code blocks if present
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") { cleaned = String(cleaned.dropFirst(7)) }
        if cleaned.hasPrefix("```") { cleaned = String(cleaned.dropFirst(3)) }
        if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw AIError.invalidResponse("Cannot encode text")
        }

        do {
            return try JSONDecoder().decode(AIRecognitionResult.self, from: data)
        } catch {
            throw AIError.invalidResponse("JSON decode failed: \(error.localizedDescription)")
        }
    }

    private func parseErrorMessage(data: Data, isGemini: Bool) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? "Unknown error"
        }
        if let error = json["error"] as? [String: Any], let msg = error["message"] as? String {
            return msg
        }
        return "Unknown error"
    }
}

// MARK: - BillMind API — wire DTOs
//
// These mirror contract/openapi.yaml exactly. Money is a decimal string
// (@DecimalString), dates are ISO-8601 (APICoders). The `API` prefix keeps them
// distinct from the app's on-device models (Journal/BillRecord/AIRecognitionResult).

struct APIErrorBody: Decodable { let error: Bool; let reason: String }

struct APIAuthTokens: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let userID: UUID
}

struct APIUser: Codable, Sendable {
    let id: UUID
    let displayName: String?
    let email: String?
    let aiQuotaTier: String
}

struct APITrip: Codable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let currencyCode: String
    @DecimalString var exchangeRate: Decimal
    let mascot: String?
    let rowVersion: Int
}

struct APICreateTripRequest: Encodable, Sendable {
    let name: String
    let currencyCode: String
    let mascot: String?
}

struct APIBill: Codable, Sendable, Identifiable {
    let id: UUID
    let tripID: UUID
    let merchant: String?
    @DecimalString var amount: Decimal
    let currencyCode: String
    let date: Date
    let categoryRaw: String?
    let source: String
    let notes: String?
    let rowVersion: Int
}

struct APICreateBillRequest: Encodable, Sendable {
    let tripID: UUID
    let merchant: String?
    @DecimalString var amount: Decimal
    let currencyCode: String?
    let date: Date
    let categoryRaw: String?
    let source: String?
    let notes: String?
}

struct APIConfirmRequest: Encodable, Sendable {
    let tripID: UUID
    let merchant: String?
    @OptionalDecimalString var amount: Decimal?
    let currencyCode: String?
    let date: Date?
    let categoryRaw: String?
    let source: String?
}

// Capture (text or photo) → a card to confirm, or a calm decline.
struct APICaptureRequest: Encodable, Sendable {
    let text: String?
    let tripID: UUID
    let imageBase64: String?
    let mimeType: String?
    /// The device's local date (yyyy-MM-dd) so the server resolves "today"/"yesterday"
    /// against the user's calendar, not its own UTC clock.
    var clientDate: String? = APICaptureRequest.localDateString()

    static func localDateString() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"   // f.timeZone defaults to the device's local zone
        return f.string(from: Date())
    }
}

struct APIMindRequest: Encodable, Sendable {
    let tripID: UUID
}

struct APIMindResponse: Decodable, Sendable {
    let imageBase64: String
    let mimeType: String
}

struct APIBillDraft: Codable, Sendable {
    let merchant: String?
    @OptionalDecimalString var amount: Decimal?
    let currencyCode: String
    let categoryRaw: String?
    let date: Date?
    let source: String
}

struct APIGap: Codable, Sendable {
    let field: String
    let reason: String
    let prompt: String
    let options: [String]
}

struct APICard: Codable, Sendable {
    let tripID: UUID
    let draft: APIBillDraft
    let gaps: [APIGap]
    let canSave: Bool
}

struct APICaptureResponse: Codable, Sendable {
    let declined: Bool
    let message: String?
    let card: APICard?
    /// One card per recognized bill (a sentence can yield several). Falls back to
    /// `[card]` for older servers that don't send `cards`.
    let cards: [APICard]?
    var allCards: [APICard] { cards ?? card.map { [$0] } ?? [] }
}

// Stats
struct APICategoryTotal: Codable, Sendable {
    let category: String
    @DecimalString var amount: Decimal
}

struct APIStats: Codable, Sendable {
    let scope: String
    @DecimalString var total: Decimal
    let billCount: Int
    let byCategory: [APICategoryTotal]
}

// Agent chat
struct APIChatRequest: Encodable, Sendable { let message: String }

struct APIToolResult: Codable, Sendable {
    let name: String
    let resultJSON: String
}

struct APIAgentTurn: Codable, Sendable {
    let declined: Bool
    let text: String
    let toolResults: [APIToolResult]
    let conversationID: UUID?
}

/// A typed frame from the agent's SSE stream (/v1/agent/chat/stream). Figures
/// only ever ride in `toolResult` (computed server-side), never parsed out of
/// the assistant's prose.
enum AgentEvent: Sendable, Equatable {
    case toolResult(resultJSON: String)
    case message(String)
    case declined(String)
    case done
}

// Sync
struct APITripSync: Codable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let currencyCode: String
    @DecimalString var exchangeRate: Decimal
    let mascot: String?
    let rowVersion: Int
    let updatedAt: Date?
    let deleted: Bool
}

struct APIBillSync: Codable, Sendable, Identifiable {
    let id: UUID
    let tripID: UUID
    let merchant: String?
    @DecimalString var amount: Decimal
    let currencyCode: String
    let date: Date
    let categoryRaw: String?
    let source: String
    let notes: String?
    let rowVersion: Int
    let updatedAt: Date?
    let deleted: Bool
}

struct APISyncDelta: Codable, Sendable {
    let trips: [APITripSync]
    let bills: [APIBillSync]
    let cursor: Double
}

struct APIBillUpsert: Codable, Sendable {
    let id: UUID
    let tripID: UUID
    let merchant: String?
    @DecimalString var amount: Decimal
    let currencyCode: String?
    let date: Date
    let categoryRaw: String?
    let source: String?
    let notes: String?
    let rowVersion: Int
    let deleted: Bool?
}

struct APISyncPush: Encodable, Sendable { let bills: [APIBillUpsert]? }

struct APISyncPushResult: Codable, Sendable {
    let appliedBills: Int
    let conflicts: [UUID]
}

// Moderation report
struct APIReportRequest: Encodable, Sendable {
    let messageID: UUID?
    let sessionID: UUID?
    let tripID: UUID?
    let reason: String
    let note: String?
}

struct APIReportResponse: Codable, Sendable { let reportID: UUID }

// MARK: - BillMind API — client errors

enum APIError: LocalizedError, Equatable {
    case notConfigured
    case unauthorized
    case notFound                 // also returned for cross-tenant access (by design)
    case unprocessable(String)    // 422 — e.g. confirm without an amount
    case http(Int, String)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "The app isn't configured to reach the server."
        case .unauthorized: return "Your session has expired. Please sign in again."
        case .notFound: return "That item couldn't be found."
        case .unprocessable(let reason): return reason
        case .http(let code, let reason): return "Server error (\(code)): \(reason)"
        case .decoding(let detail): return "Couldn't read the server response. \(detail)"
        case .transport(let detail): return "Network problem. \(detail)"
        }
    }
}

// MARK: - Sync API seam

/// The server calls the SyncEngine needs, abstracted so it can be tested with a
/// mock. APIClient conforms via its existing createTrip/syncPull/syncPush.
/// `createTrip` lets the engine push locally-created trips (the sync contract
/// pushes bills only), so trips can be made offline and created on reconnect.
protocol SyncAPI: Sendable {
    func createTrip(_ req: APICreateTripRequest) async throws -> APITrip
    func deleteTrip(_ id: UUID) async throws
    func syncPull(since cursor: Double) async throws -> APISyncDelta
    func syncPush(_ push: APISyncPush) async throws -> APISyncPushResult
}

extension APIClient: SyncAPI {}

/// Server-side capture the Record flow needs, abstracted for testing. APIClient
/// conforms via its existing `recognize`.
protocol RecognitionAPI: Sendable {
    func recognize(_ req: APICaptureRequest) async throws -> APICaptureResponse
}

extension APIClient: RecognitionAPI {}

// MARK: - BillMind API — client

/// Reads/writes the session token pair. Abstracted so the production Keychain
/// vault and an in-memory test double share one interface, and so the client can
/// refresh + clear tokens itself.
protocol TokenStore: Sendable {
    func accessToken() async -> String?
    func refreshToken() async -> String?
    func update(_ tokens: APIAuthTokens) async
    func clear() async
}

/// The single typed entry point to the BillMind server. An actor so token reads
/// and the single-flight refresh stay serialized: when several requests 401 at
/// once, exactly one refresh runs and the rest await it, then each retries once.
actor APIClient {
    static let defaultBaseURL = URL(string: "https://billmind.daichenlab.com")!

    private let baseURL: URL
    private let session: URLSession
    private let tokenStore: TokenStore?
    private let onSignedOut: (@Sendable () async -> Void)?
    private var refreshInFlight: Task<Bool, Never>?

    init(baseURL: URL = APIClient.defaultBaseURL,
         session: URLSession = .shared,
         tokenStore: TokenStore? = nil,
         onSignedOut: (@Sendable () async -> Void)? = nil) {
        self.baseURL = baseURL
        self.session = session
        self.tokenStore = tokenStore
        self.onSignedOut = onSignedOut
    }

    // MARK: Endpoints (auth)

    func signIn(provider: String, idToken: String, nonce: String? = nil) async throws -> APIAuthTokens {
        struct Body: Encodable { let idToken: String; let nonce: String? }
        return try await post("v1/auth/\(provider)", body: Body(idToken: idToken, nonce: nonce), authed: false)
    }

    func refresh(refreshToken: String) async throws -> APIAuthTokens {
        struct Body: Encodable { let refreshToken: String }
        return try await post("v1/auth/refresh", body: Body(refreshToken: refreshToken), authed: false)
    }

    func logout(refreshToken: String) async throws {
        struct Body: Encodable { let refreshToken: String }
        try await postNoContent("v1/auth/logout", body: Body(refreshToken: refreshToken), authed: false)
    }

    // MARK: Endpoints (account + ledger)

    func me() async throws -> APIUser { try await get("v1/account/me") }
    func deleteAccount() async throws { try await delete("v1/account") }

    func trips() async throws -> [APITrip] { try await get("v1/trips") }

    func createTrip(_ req: APICreateTripRequest) async throws -> APITrip {
        try await post("v1/trips", body: req)
    }

    /// Soft-delete a trip and its bills on the server (tombstones propagate on sync).
    func deleteTrip(_ id: UUID) async throws {
        try await delete("v1/trips/\(id.uuidString)")
    }

    func bills(tripID: UUID) async throws -> [APIBill] {
        try await get("v1/trips/\(tripID.uuidString)/bills")
    }

    func createBill(_ req: APICreateBillRequest) async throws -> APIBill {
        try await post("v1/bills", body: req)
    }

    func confirm(_ req: APIConfirmRequest) async throws -> APIBill {
        try await post("v1/bills/confirm", body: req)
    }

    // MARK: Endpoints (capture + agent + stats)

    func recognize(_ req: APICaptureRequest) async throws -> APICaptureResponse {
        try await post("v1/recognition", body: req)
    }

    /// Server-side Mind generation (Gemini image gen with the app's own key).
    /// Slow — image generation can take 60–120s — so this uses a long timeout.
    func generateMind(tripID: UUID) async throws -> APIMindResponse {
        let data = try await dataWithRetry(authed: true) {
            try await self.makeRequest("POST", "v1/minds",
                                       body: APIMindRequest(tripID: tripID),
                                       authed: true, timeout: 200)
        }
        return try decode(data)
    }

    func chat(message: String) async throws -> APIAgentTurn {
        try await post("v1/agent/chat", body: APIChatRequest(message: message))
    }

    /// Streams an agent turn as typed SSE events: `toolResult`* then `message`
    /// then `done`, or a lone `declined`. Cancelling the consuming Task cancels
    /// the network read.
    func chatStream(message: String) async throws -> AsyncThrowingStream<AgentEvent, Error> {
        let request = try await makeRequest("POST", "v1/agent/chat/stream",
                                            body: APIChatRequest(message: message), authed: true)
        let session = self.session
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        throw http.statusCode == 401 ? APIError.unauthorized
                            : APIError.http(http.statusCode, "chat stream failed")
                    }
                    var eventName: String?
                    var dataLine: String?
                    for try await line in bytes.lines {
                        if line.isEmpty {
                            if let event = APIClient.frame(event: eventName, data: dataLine) {
                                continuation.yield(event)
                            }
                            eventName = nil; dataLine = nil
                        } else if line.hasPrefix("event:") {
                            eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            dataLine = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        }
                    }
                    if let event = APIClient.frame(event: eventName, data: dataLine) {
                        continuation.yield(event)   // flush a trailing frame with no blank line
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Turn one SSE `event:`/`data:` pair into an AgentEvent. Pure + static so it
    /// is unit-tested without a network stream.
    static func frame(event: String?, data: String?) -> AgentEvent? {
        guard let event else { return nil }
        switch event {
        case "tool_result": return .toolResult(resultJSON: data ?? "")
        case "message": return .message(jsonField(data, "text") ?? (data ?? ""))
        case "declined": return .declined(jsonField(data, "message") ?? (data ?? ""))
        case "done": return .done
        default: return nil
        }
    }

    /// Parse a full SSE payload into events (test helper; mirrors the streaming loop).
    static func parseSSE(_ raw: String) -> [AgentEvent] {
        var events: [AgentEvent] = []
        var eventName: String?
        var dataLine: String?
        for piece in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(piece)
            if line.isEmpty {
                if let event = frame(event: eventName, data: dataLine) { events.append(event) }
                eventName = nil; dataLine = nil
            } else if line.hasPrefix("event:") {
                eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                dataLine = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            }
        }
        if let event = frame(event: eventName, data: dataLine) { events.append(event) }
        return events
    }

    private static func jsonField(_ data: String?, _ key: String) -> String? {
        guard let data, let bytes = data.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return nil }
        return obj[key] as? String
    }

    func stats(tripID: UUID? = nil, scope: String? = nil) async throws -> APIStats {
        var items: [URLQueryItem] = []
        if let tripID { items.append(.init(name: "tripId", value: tripID.uuidString)) }
        if let scope { items.append(.init(name: "scope", value: scope)) }
        return try await get("v1/stats", query: items)
    }

    // MARK: Endpoints (sync + moderation)

    func syncPull(since cursor: Double) async throws -> APISyncDelta {
        try await get("v1/sync", query: [.init(name: "since", value: String(cursor))])
    }

    func syncPush(_ push: APISyncPush) async throws -> APISyncPushResult {
        try await post("v1/sync", body: push)
    }

    func report(_ req: APIReportRequest) async throws -> APIReportResponse {
        try await post("v1/moderation/report", body: req)
    }

    // MARK: Request engine

    private func get<R: Decodable>(_ path: String, query: [URLQueryItem] = [], authed: Bool = true) async throws -> R {
        let data = try await dataWithRetry(authed: authed) {
            try await self.makeRequest("GET", path, query: query, body: Optional<Int>.none, authed: authed)
        }
        return try decode(data)
    }

    private func post<B: Encodable, R: Decodable>(_ path: String, body: B, authed: Bool = true) async throws -> R {
        let data = try await dataWithRetry(authed: authed) {
            try await self.makeRequest("POST", path, body: body, authed: authed)
        }
        return try decode(data)
    }

    private func postNoContent<B: Encodable>(_ path: String, body: B, authed: Bool = true) async throws {
        _ = try await dataWithRetry(authed: authed) {
            try await self.makeRequest("POST", path, body: body, authed: authed)
        }
    }

    private func delete(_ path: String, authed: Bool = true) async throws {
        _ = try await dataWithRetry(authed: authed) {
            try await self.makeRequest("DELETE", path, body: Optional<Int>.none, authed: authed)
        }
    }

    private func decode<R: Decodable>(_ data: Data) throws -> R {
        do { return try APICoders.decoder.decode(R.self, from: data) }
        catch { throw APIError.decoding(error.localizedDescription) }
    }

    /// Sends the built request; on a 401 for an authed call, runs (or joins) a
    /// single refresh and retries once with the rebuilt request (fresh token).
    /// If refresh fails, signs out and surfaces `.unauthorized`.
    private func dataWithRetry(authed: Bool, _ build: () async throws -> URLRequest) async throws -> Data {
        do {
            return try await validatedData(try await build())
        } catch APIError.unauthorized where authed && tokenStore != nil {
            guard await refreshOnce() else {
                await onSignedOut?()
                throw APIError.unauthorized
            }
            do {
                return try await validatedData(try await build())
            } catch APIError.unauthorized {
                await onSignedOut?()
                throw APIError.unauthorized
            }
        }
    }

    /// Single-flight refresh: concurrent callers share one in-flight task.
    private func refreshOnce() async -> Bool {
        if let inFlight = refreshInFlight { return await inFlight.value }
        let task = Task { () -> Bool in
            guard let store = self.tokenStore, let rt = await store.refreshToken() else { return false }
            do {
                let tokens = try await self.refresh(refreshToken: rt)
                await store.update(tokens)
                return true
            } catch {
                return false
            }
        }
        refreshInFlight = task
        let result = await task.value
        refreshInFlight = nil
        return result
    }

    private func makeRequest<B: Encodable>(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: B?, authed: Bool,
        timeout: TimeInterval? = nil
    ) async throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.notConfigured
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = method
        if let timeout { request.timeoutInterval = timeout }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do { request.httpBody = try APICoders.encoder.encode(body) }
            catch { throw APIError.decoding("encode failed: \(error.localizedDescription)") }
        }
        if authed, let token = await tokenStore?.accessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Transport + status mapping. Returns the body data on 2xx; throws a typed
    /// APIError (decoding the {error,reason} envelope) otherwise.
    private func validatedData(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw APIError.transport(error.localizedDescription) }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("no HTTP response")
        }
        switch http.statusCode {
        case 200...299:
            return data
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        case 422:
            throw APIError.unprocessable(reason(from: data) ?? "Unprocessable request")
        default:
            throw APIError.http(http.statusCode, reason(from: data) ?? "Unexpected error")
        }
    }

    private func reason(from data: Data) -> String? {
        (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.reason
    }
}
