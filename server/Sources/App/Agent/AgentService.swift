import Vapor
import Fluent

/// The agent turn: moderation → quota → a bounded LLM↔tools loop. Every figure
/// comes from a deterministic tool over the user's data (audited in tool_calls);
/// the model only narrates. The structural guarantee: there is no tool that
/// writes or invents a figure.
struct AgentService {
    let llm: LLMClient
    let moderation: ModerationService
    let quota: QuotaService
    let maxIterations: Int

    init(llm: LLMClient, moderation: ModerationService, quota: QuotaService, maxIterations: Int = 4) {
        self.llm = llm
        self.moderation = moderation
        self.quota = quota
        self.maxIterations = maxIterations
    }

    /// Read tools (v1). Declared to the model; executed server-side, user-scoped.
    static let toolSpecs: [ToolSpec] = [
        ToolSpec(name: "compute_totals",
                 description: "Total spending + per-category breakdown for the user, optionally one trip.",
                 parameters: "{ tripId?: UUID }"),
        ToolSpec(name: "query_bills",
                 description: "List the user's bills, optionally filtered by category or merchant.",
                 parameters: "{ tripId?: UUID, category?: String, merchant?: String }"),
    ]

    struct Result {
        let declined: Bool
        let text: String
        let toolResults: [(name: String, resultJSON: String)]
        let conversationID: UUID?
    }

    func run(message: String, user: User, on req: Request) async throws -> Result {
        let uid = try user.requireID()

        // 1. Moderation (chat input).
        let verdict = try await moderation.evaluate(message, surface: .chatInput, expenseShaped: false, on: req)
        try await moderation.logEvent(verdict, raw: message, surface: .chatInput, userID: uid,
                                      requestID: req.id, on: req.db)
        if verdict.decision == .block {
            return Result(declined: true,
                          text: "I can't help with that one — I'm your travel-and-money agent.",
                          toolResults: [], conversationID: nil)
        }

        // 2. Quota (before any model call).
        try await quota.assertChatAllowed(uid, on: req.db)

        // 3. Conversation + the user turn.
        let convo = Conversation(userID: uid)
        try await convo.save(on: req.db)
        let convoID = try convo.requireID()
        try await Message(conversationID: convoID, role: "user", content: message).save(on: req.db)

        // 4. Bounded LLM ↔ tools loop.
        var llmMessages = [LLMMessage(role: "user", content: message)]
        var toolResults: [(name: String, resultJSON: String)] = []

        for _ in 0..<maxIterations {
            let response = try await llm.next(messages: llmMessages, tools: Self.toolSpecs, on: req)
            switch response {
            case .toolCall(let name, let argsJSON):
                let resultJSON = try await executeTool(name, argsJSON: argsJSON, userID: uid, db: req.db)
                // Audit: a tool message + the tool_call row (every number is traceable).
                let toolMsg = Message(conversationID: convoID, role: "tool", content: resultJSON)
                try await toolMsg.save(on: req.db)
                try await ToolCall(messageID: try toolMsg.requireID(), toolName: name,
                                   argsJSON: argsJSON, resultJSON: resultJSON, status: "ok").save(on: req.db)
                toolResults.append((name, resultJSON))
                llmMessages.append(LLMMessage(role: "tool", content: resultJSON))

            case .finalText(let text):
                try await Message(conversationID: convoID, role: "assistant", content: text).save(on: req.db)
                try await AIUsage(userID: uid, kind: "chat", tokensIn: 0, tokensOut: 0,
                                  costMicros: 0, model: "gemini").save(on: req.db)
                return Result(declined: false, text: text, toolResults: toolResults, conversationID: convoID)
            }
        }

        // Loop budget exhausted — bound the spend, answer honestly.
        let fallback = "I couldn't finish working that out — try rephrasing?"
        try await Message(conversationID: convoID, role: "assistant", content: fallback).save(on: req.db)
        try await AIUsage(userID: uid, kind: "chat", tokensIn: 0, tokensOut: 0, costMicros: 0, model: "gemini").save(on: req.db)
        return Result(declined: false, text: fallback, toolResults: toolResults, conversationID: convoID)
    }

    // MARK: - tool execution (user-scoped; the only source of figures)

    private struct ToolArgs: Content { let tripId: String?; let category: String?; let merchant: String? }
    private struct TotalsResult: Content { let total: Decimal; let count: Int; let byCategory: [CategoryTotalDTO] }

    private func executeTool(_ name: String, argsJSON: String, userID: UUID, db: Database) async throws -> String {
        let args = (try? JSONDecoder().decode(ToolArgs.self, from: Data(argsJSON.utf8)))
            ?? ToolArgs(tripId: nil, category: nil, merchant: nil)
        let tripID = args.tripId.flatMap { UUID(uuidString: $0) }

        switch name {
        case "compute_totals":
            let t = try await AgentTools.computeTotals(db, userID: userID, tripID: tripID)
            let payload = TotalsResult(total: t.total, count: t.count,
                byCategory: t.byCategory.map { CategoryTotalDTO(category: $0.category, amount: $0.amount) })
            return try Self.encode(payload)
        case "query_bills":
            let bills = try await AgentTools.queryBills(db, userID: userID, tripID: tripID,
                                                        category: args.category, merchant: args.merchant)
            return try Self.encode(bills.compactMap { try? BillDTO($0) })
        default:
            throw Abort(.badRequest, reason: "unknown tool: \(name)")
        }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        String(data: try JSONEncoder().encode(value), encoding: .utf8) ?? "{}"
    }
}
