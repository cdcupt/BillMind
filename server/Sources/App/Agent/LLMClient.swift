import Vapor

/// A message in the agent turn (sent to / produced by the model).
struct LLMMessage: Sendable {
    let role: String          // user | assistant | tool
    let content: String
    let toolName: String?     // set on tool-result messages

    init(role: String, content: String, toolName: String? = nil) {
        self.role = role
        self.content = content
        self.toolName = toolName
    }
}

/// A tool the model may call (declared to the LLM as a function).
struct ToolSpec: Sendable {
    let name: String
    let description: String
    let parameters: String  // human/JSON-schema-ish description of args
}

/// What the model returns each step: either call a tool, or final narration.
enum LLMResponse: Sendable {
    case toolCall(name: String, argsJSON: String)
    case finalText(String)
}

/// Injectable so the agent loop is tested without calling a provider. The live
/// Gemini function-calling client lands in the next slice.
protocol LLMClient: Sendable {
    func next(messages: [LLMMessage], tools: [ToolSpec], on req: Request) async throws -> LLMResponse
}

/// Placeholder until the live Gemini client is wired — keeps the endpoint
/// present and returns a clear error rather than silently answering.
struct UnconfiguredLLMClient: LLMClient {
    func next(messages: [LLMMessage], tools: [ToolSpec], on req: Request) async throws -> LLMResponse {
        throw Abort(.serviceUnavailable, reason: "agent LLM is not configured yet")
    }
}
