import Vapor

/// `POST /v1/agent/chat` — ask-anything. v1 returns a JSON turn (assistant text
/// + the computed tool results); SSE streaming is layered over the same service
/// in the next slice.
struct AgentController: RouteCollection {
    let agent: AgentService

    func boot(routes: RoutesBuilder) throws {
        let group = routes.grouped("v1", "agent").grouped(UserAuthMiddleware())
        group.post("chat", use: chat)
        group.post("chat", "stream", use: chatStream)
    }

    struct ChatRequest: Content { let message: String }

    /// SSE variant — the client renders typed turns (`tool_result` chips, then the
    /// assistant `message`). v1 emits the frames once the turn completes; true
    /// token-by-token streaming arrives with the live Gemini client. A decline is
    /// emitted as a single `declined` frame (no model call, no tool frames).
    func chatStream(_ req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let body = try req.content.decode(ChatRequest.self)
        let result = try await agent.run(message: body.message, user: user, on: req)

        var sse = ""
        if result.declined {
            sse += "event: declined\ndata: \(Self.json(["message": result.text]))\n\n"
        } else {
            for toolResult in result.toolResults {
                sse += "event: tool_result\ndata: \(toolResult.resultJSON)\n\n"
            }
            sse += "event: message\ndata: \(Self.json(["text": result.text]))\n\n"
            sse += "event: done\ndata: {}\n\n"
        }

        let response = Response(status: .ok)
        response.headers.replaceOrAdd(name: .contentType, value: "text/event-stream")
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-cache")
        response.body = .init(string: sse)
        return response
    }

    private static func json(_ dict: [String: String]) -> String {
        let data = (try? JSONEncoder().encode(dict)) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func chat(_ req: Request) async throws -> AgentTurnResponse {
        let user = try req.auth.require(User.self)
        let body = try req.content.decode(ChatRequest.self)
        let result = try await agent.run(message: body.message, user: user, on: req)
        return AgentTurnResponse(
            declined: result.declined,
            text: result.text,
            toolResults: result.toolResults.map { ToolResultDTO(name: $0.name, resultJSON: $0.resultJSON) },
            conversationID: result.conversationID
        )
    }
}

struct ToolResultDTO: Content {
    let name: String
    let resultJSON: String
}

struct AgentTurnResponse: Content {
    let declined: Bool
    let text: String
    let toolResults: [ToolResultDTO]
    let conversationID: UUID?
}
