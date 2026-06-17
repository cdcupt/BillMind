import Fluent
import Foundation

/// A per-trip agent conversation (session-scoped on the surface; the rows are
/// the durable transcript for rehydration + the financial audit trail).
final class Conversation: Model, @unchecked Sendable {
    static let schema = "conversations"

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: User
    @OptionalParent(key: "trip_id") var trip: Trip?
    @OptionalField(key: "title") var title: String?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}
    init(id: UUID? = nil, userID: User.IDValue, tripID: Trip.IDValue? = nil, title: String? = nil) {
        self.id = id
        self.$user.id = userID
        self.$trip.id = tripID
        self.title = title
    }
}

/// One turn in a conversation. Token counts feed usage metering.
final class Message: Model, @unchecked Sendable {
    static let schema = "messages"

    @ID(key: .id) var id: UUID?
    @Parent(key: "conversation_id") var conversation: Conversation
    @Field(key: "role") var role: String                  // user | assistant | tool
    @Field(key: "content") var content: String
    @OptionalField(key: "model") var model: String?
    @OptionalField(key: "prompt_tokens") var promptTokens: Int?
    @OptionalField(key: "completion_tokens") var completionTokens: Int?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}
    init(id: UUID? = nil, conversationID: Conversation.IDValue, role: String, content: String,
         model: String? = nil, promptTokens: Int? = nil, completionTokens: Int? = nil) {
        self.id = id
        self.$conversation.id = conversationID
        self.role = role
        self.content = content
        self.model = model
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

/// THE financial audit trail: every number the agent stated maps to a tool_call
/// with its computed args + result. The eval harness asserts against these rows.
final class ToolCall: Model, @unchecked Sendable {
    static let schema = "tool_calls"

    @ID(key: .id) var id: UUID?
    @Parent(key: "message_id") var message: Message
    @Field(key: "tool_name") var toolName: String
    @Field(key: "args_json") var argsJSON: String
    @OptionalField(key: "result_json") var resultJSON: String?
    @Field(key: "status") var status: String              // ok | error
    @OptionalField(key: "duration_ms") var durationMs: Int?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}
    init(id: UUID? = nil, messageID: Message.IDValue, toolName: String, argsJSON: String,
         resultJSON: String? = nil, status: String = "ok", durationMs: Int? = nil) {
        self.id = id
        self.$message.id = messageID
        self.toolName = toolName
        self.argsJSON = argsJSON
        self.resultJSON = resultJSON
        self.status = status
        self.durationMs = durationMs
    }
}

/// Per-account AI cost metering (powers the quota gate). Free moderation calls
/// are NOT recorded here.
final class AIUsage: Model, @unchecked Sendable {
    static let schema = "ai_usage"

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: User
    @Field(key: "kind") var kind: String                  // recognition | chat
    @Field(key: "tokens_in") var tokensIn: Int
    @Field(key: "tokens_out") var tokensOut: Int
    @Field(key: "cost_micros") var costMicros: Int
    @OptionalField(key: "model") var model: String?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}
    init(id: UUID? = nil, userID: User.IDValue, kind: String, tokensIn: Int, tokensOut: Int,
         costMicros: Int, model: String? = nil) {
        self.id = id
        self.$user.id = userID
        self.kind = kind
        self.tokensIn = tokensIn
        self.tokensOut = tokensOut
        self.costMicros = costMicros
        self.model = model
    }
}
