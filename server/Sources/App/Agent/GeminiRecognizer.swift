import Vapor
import BillMindCore

/// Photo recognition. Injectable so the capture path is tested without Gemini.
protocol Recognizer: Sendable {
    func recognize(imageBase64: String, mimeType: String, on req: Request) async throws -> AIRecognitionResult
}

/// Live: Gemini vision → strict-JSON receipt extraction → AIRecognitionResult.
/// The prompt forbids inventing the total (it stays nil → the validator asks).
/// The response parse is pure/static and unit-tested without a network call.
struct GeminiRecognizer: Recognizer {
    let model: String

    init(model: String = "gemini-2.0-flash") { self.model = model }

    static let prompt = """
    Extract this receipt as STRICT JSON (no prose, no markdown) with keys: \
    merchant (string), date (yyyy-MM-dd), totalAmount (number), currency (ISO 4217), \
    category (one of: food, transport, accommodation, shopping, entertainment, utilities, \
    medical, education, subscription, misc), lineItems (array of {description, amount}), notes. \
    Omit any field you cannot read. NEVER invent the total — omit totalAmount if it is unreadable.
    """

    func recognize(imageBase64: String, mimeType: String, on req: Request) async throws -> AIRecognitionResult {
        guard let key = Environment.get("GEMINI_API_KEY"), !key.isEmpty else {
            throw Abort(.serviceUnavailable, reason: "GEMINI_API_KEY not configured")
        }
        let uri = URI(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(key)")
        let body = GVReq(contents: [GVContent(role: "user", parts: [
            GVPart(text: Self.prompt, inlineData: nil),
            GVPart(text: nil, inlineData: GVInline(mimeType: mimeType, data: imageBase64)),
        ])])
        let response = try await req.client.post(uri) { try $0.content.encode(body) }
        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "Gemini recognition returned \(response.status.code)")
        }
        let data = response.body.map { Data(buffer: $0) } ?? Data()
        return try Self.parse(data)
    }

    /// Pull the model's text, extract the JSON object (tolerating ``` fences /
    /// prose), and decode it into AIRecognitionResult.
    static func parse(_ data: Data) throws -> AIRecognitionResult {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let parts = (((obj?["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
        let text = parts.compactMap { $0["text"] as? String }.joined()
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start <= end else {
            throw Abort(.badGateway, reason: "recognition returned no JSON")
        }
        let jsonText = String(text[start...end])
        return try JSONDecoder().decode(AIRecognitionResult.self, from: Data(jsonText.utf8))
    }
}

// Gemini vision request (encode-only; nil parts are omitted by synthesized Codable).
struct GVReq: Content { let contents: [GVContent] }
struct GVContent: Content { let role: String; let parts: [GVPart] }
struct GVPart: Content {
    let text: String?
    let inlineData: GVInline?
    enum CodingKeys: String, CodingKey { case text; case inlineData = "inline_data" }
}
struct GVInline: Content {
    let mimeType: String
    let data: String
    enum CodingKeys: String, CodingKey { case mimeType = "mime_type"; case data }
}
