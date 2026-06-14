import XCTVapor
import Fluent
import FluentSQLiteDriver
@testable import App

private struct StubOIDC3: OIDCVerifier {
    let identity: VerifiedIdentity
    func verify(idToken: String, provider: OIDCProvider, on req: Request) async throws -> VerifiedIdentity { identity }
}
private struct AllowMod: ModerationClient {
    func score(_ text: String, on req: Request) async throws -> ModerationScores { ModerationScores(categories: [:]) }
}
private struct BlockMod: ModerationClient {
    func score(_ text: String, on req: Request) async throws -> ModerationScores {
        ModerationScores(categories: ["sexual/minors": 0.95])
    }
}
/// Calls one tool, then narrates — driven by whether the last message is a tool result.
private struct ScriptedLLM: LLMClient {
    func next(messages: [LLMMessage], tools: [ToolSpec], on req: Request) async throws -> LLMResponse {
        if messages.last?.role == "tool" { return .finalText("Here's your spending total.") }
        return .toolCall(name: "compute_totals", argsJSON: "{}")
    }
}
/// Never finishes — exercises the loop bound.
private struct AlwaysToolLLM: LLMClient {
    func next(messages: [LLMMessage], tools: [ToolSpec], on req: Request) async throws -> LLMResponse {
        .toolCall(name: "compute_totals", argsJSON: "{}")
    }
}

final class AgentChatTests: XCTestCase {
    private func makeApp(llm: LLMClient, mod: ModerationClient = AllowMod(), quota: QuotaService = QuotaService()) async throws -> Application {
        let app = try await Application.make(.testing)
        app.databases.use(.sqlite(.memory), as: .sqlite)
        app.migrations.add(CreateInitialSchema())
        try await app.autoMigrate()
        app.jwt.signers.use(.hs256(key: Array("test-signing-key-0123456789abcdef".utf8)))
        let id = VerifiedIdentity(provider: .google, subject: "u1", email: "u1@example.com", isPrivateRelay: false, name: "u1")
        try app.register(collection: AuthController(oidc: StubOIDC3(identity: id)))
        try app.register(collection: TripController())
        try app.register(collection: BillController())
        try app.register(collection: AgentController(agent: AgentService(
            llm: llm, moderation: ModerationService(client: mod), quota: quota)))
        return app
    }

    private func setup(_ app: Application) async throws -> AuthTokensDTO {
        var t: AuthTokensDTO!
        try await app.test(.POST, "v1/auth/google",
            beforeRequest: { try $0.content.encode(["idToken": "stub"]) },
            afterResponse: { res async throws in t = try res.content.decode(AuthTokensDTO.self) })
        var trip: TripDTO!
        try await app.test(.POST, "v1/trips", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: { try $0.content.encode(CreateTripRequest(name: "Osaka", currencyCode: "JPY", mascot: nil)) },
            afterResponse: { res async throws in trip = try res.content.decode(TripDTO.self) })
        try await app.test(.POST, "v1/bills", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: { try $0.content.encode(CreateBillRequest(tripID: trip.id, merchant: "Ichiran", amount: 2840,
                currencyCode: "JPY", date: Date(), categoryRaw: "food", source: "manual", notes: nil)) },
            afterResponse: { res async in XCTAssertEqual(res.status, .ok) })
        return t
    }

    func testChatRunsToolAndAudits() async throws {
        let app = try await makeApp(llm: ScriptedLLM())
        let t = try await setup(app)
        try await app.test(.POST, "v1/agent/chat", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: { try $0.content.encode(AgentController.ChatRequest(message: "how much have I spent?")) },
            afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let turn = try res.content.decode(AgentTurnResponse.self)
                XCTAssertFalse(turn.declined)
                XCTAssertEqual(turn.toolResults.first?.name, "compute_totals")
                XCTAssertTrue(turn.toolResults.first?.resultJSON.contains("2840") ?? false)
            })
        // The audit trail: a tool_call row with the computed result exists.
        let toolCalls = try await ToolCall.query(on: app.db).all()
        XCTAssertEqual(toolCalls.count, 1)
        XCTAssertEqual(toolCalls.first?.toolName, "compute_totals")
        XCTAssertTrue(toolCalls.first?.resultJSON?.contains("2840") ?? false)
        try await app.asyncShutdown()
    }

    func testModerationBlocksBeforeAnyModelCall() async throws {
        let app = try await makeApp(llm: ScriptedLLM(), mod: BlockMod())
        let t = try await setup(app)
        try await app.test(.POST, "v1/agent/chat", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: { try $0.content.encode(AgentController.ChatRequest(message: "...")) },
            afterResponse: { res async throws in
                let turn = try res.content.decode(AgentTurnResponse.self)
                XCTAssertTrue(turn.declined)
                XCTAssertNil(turn.conversationID)
            })
        let convos = try await Conversation.query(on: app.db).count()
        XCTAssertEqual(convos, 0)            // blocked before a conversation is created
        try await app.asyncShutdown()
    }

    func testBoundedLoopDoesNotHang() async throws {
        let app = try await makeApp(llm: AlwaysToolLLM())
        let t = try await setup(app)
        try await app.test(.POST, "v1/agent/chat", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: { try $0.content.encode(AgentController.ChatRequest(message: "loop please")) },
            afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                let turn = try res.content.decode(AgentTurnResponse.self)
                XCTAssertEqual(turn.toolResults.count, 4)   // maxIterations bound
            })
        try await app.asyncShutdown()
    }

    func testChatStreamEmitsSSEFrames() async throws {
        let app = try await makeApp(llm: ScriptedLLM())
        let t = try await setup(app)
        try await app.test(.POST, "v1/agent/chat/stream", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: { try $0.content.encode(AgentController.ChatRequest(message: "how much?")) },
            afterResponse: { res async in
                XCTAssertEqual(res.status, .ok)
                XCTAssertTrue(res.headers.first(name: .contentType)?.contains("text/event-stream") ?? false)
                let s = res.body.string
                XCTAssertTrue(s.contains("event: tool_result"))
                XCTAssertTrue(s.contains("2840"))
                XCTAssertTrue(s.contains("event: message"))
                XCTAssertTrue(s.contains("event: done"))
            })
        try await app.asyncShutdown()
    }

    func testQuotaEnforced() async throws {
        let app = try await makeApp(llm: ScriptedLLM(), quota: QuotaService(dailyChatLimit: 1))
        let t = try await setup(app)
        let headers: HTTPHeaders = ["Authorization": "Bearer \(t.accessToken)"]
        try await app.test(.POST, "v1/agent/chat", headers: headers,
            beforeRequest: { try $0.content.encode(AgentController.ChatRequest(message: "first")) },
            afterResponse: { res async in XCTAssertEqual(res.status, .ok) })
        try await app.test(.POST, "v1/agent/chat", headers: headers,
            beforeRequest: { try $0.content.encode(AgentController.ChatRequest(message: "second")) },
            afterResponse: { res async in XCTAssertEqual(res.status, .tooManyRequests) })
        try await app.asyncShutdown()
    }
}
