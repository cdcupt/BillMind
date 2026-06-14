import Vapor

/// The live agent brain: Gemini `generateContent` with function-calling. Tools
/// are declared; the model either calls one (→ we execute it server-side and
/// loop) or returns narration. Tool results are fed back as text so the model
/// only ever narrates numbers it was given — it cannot invent one.
///
/// The request build + response parse are pure/static so they're unit-tested
/// without a network call; the live `next` is verified against the real key at
/// deploy.
struct GeminiLLMClient: LLMClient {
    let model: String

    init(model: String = "gemini-2.0-flash") { self.model = model }

    func next(messages: [LLMMessage], tools: [ToolSpec], on req: Request) async throws -> LLMResponse {
        guard let key = Environment.get("GEMINI_API_KEY"), !key.isEmpty else {
            throw Abort(.serviceUnavailable, reason: "GEMINI_API_KEY not configured")
        }
        let uri = URI(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(key)")
        let response = try await req.client.post(uri) { out in
            try out.content.encode(Self.buildRequest(messages: messages, tools: tools))
        }
        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "Gemini returned \(response.status.code)")
        }
        let data = response.body.map { Data(buffer: $0) } ?? Data()
        return try Self.parse(data)
    }

    // MARK: - pure, testable

    static func buildRequest(messages: [LLMMessage], tools: [ToolSpec]) -> GReq {
        let contents: [GReqContent] = messages.map { m in
            switch m.role {
            case "assistant":
                return GReqContent(role: "model", parts: [GReqPart(text: m.content)])
            case "tool":
                return GReqContent(role: "user",
                    parts: [GReqPart(text: "Tool \(m.toolName ?? "tool") returned: \(m.content)")])
            default:
                return GReqContent(role: "user", parts: [GReqPart(text: m.content)])
            }
        }
        let decls = tools.map { GReqFn(name: $0.name, description: $0.description, parameters: GReqSchema()) }
        return GReq(contents: contents, tools: decls.isEmpty ? nil : [GReqTool(functionDeclarations: decls)])
    }

    /// Parsed with JSONSerialization (Gemini's `args` is arbitrary JSON) → a
    /// tool call (args re-serialized to a JSON string) or the narration text.
    static func parse(_ data: Data) throws -> LLMResponse {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let candidates = obj?["candidates"] as? [[String: Any]]
        let parts = ((candidates?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
        for part in parts {
            if let fc = part["functionCall"] as? [String: Any], let name = fc["name"] as? String {
                let args = fc["args"] as? [String: Any] ?? [:]
                let argsData = (try? JSONSerialization.data(withJSONObject: args)) ?? Data("{}".utf8)
                return .toolCall(name: name, argsJSON: String(data: argsData, encoding: .utf8) ?? "{}")
            }
        }
        let text = parts.compactMap { $0["text"] as? String }.joined()
        return .finalText(text.isEmpty ? "I couldn't produce an answer." : text)
    }
}

// Request shapes (encode-only — we send text parts; responses are parsed loosely).
struct GReq: Content { let contents: [GReqContent]; let tools: [GReqTool]? }
struct GReqContent: Content { let role: String; let parts: [GReqPart] }
struct GReqPart: Content { let text: String }
struct GReqTool: Content { let functionDeclarations: [GReqFn] }
struct GReqFn: Content { let name: String; let description: String; let parameters: GReqSchema }
struct GReqSchema: Content { var type: String = "object" }
