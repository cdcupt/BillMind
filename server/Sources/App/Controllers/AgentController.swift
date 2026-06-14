import Vapor

/// `POST /v1/agent/chat` — ask-anything. v1 returns a JSON turn (assistant text
/// + the computed tool results); SSE streaming is layered over the same service
/// in the next slice.
struct AgentController: RouteCollection {
    let agent: AgentService

    func boot(routes: RoutesBuilder) throws {
        let group = routes.grouped("v1", "agent").grouped(UserAuthMiddleware())
        group.post("chat", use: chat)
    }

    struct ChatRequest: Content { let message: String }

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
