import Fluent
import Foundation

/// A moderation decision (input or output). Logs the DECISION, not the dangerous
/// content: a one-way `content_sha256` for dedup + repeat-offender counting, and
/// only a short redacted excerpt on a hard block. Purged with the account.
final class ModerationEvent: Model, @unchecked Sendable {
    static let schema = "moderation_events"

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: User
    @OptionalParent(key: "trip_id") var trip: Trip?
    @OptionalField(key: "agent_session_id") var agentSessionID: UUID?
    @Field(key: "request_id") var requestID: String
    @Field(key: "surface") var surface: String            // chat_input | chat_output | recognition
    @Field(key: "decision") var decision: String          // allow | soft | block
    @OptionalField(key: "top_category") var topCategory: String?
    @OptionalField(key: "score") var score: Double?
    @Field(key: "provider") var provider: String          // moderation_api | local_denylist | native_safety
    @Field(key: "content_sha256") var contentSHA256: String
    @OptionalField(key: "excerpt_redacted") var excerptRedacted: String?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}
    init(id: UUID? = nil, userID: User.IDValue, tripID: Trip.IDValue? = nil,
         agentSessionID: UUID? = nil, requestID: String, surface: String, decision: String,
         topCategory: String? = nil, score: Double? = nil, provider: String,
         contentSHA256: String, excerptRedacted: String? = nil) {
        self.id = id
        self.$user.id = userID
        self.$trip.id = tripID
        self.agentSessionID = agentSessionID
        self.requestID = requestID
        self.surface = surface
        self.decision = decision
        self.topCategory = topCategory
        self.score = score
        self.provider = provider
        self.contentSHA256 = contentSHA256
        self.excerptRedacted = excerptRedacted
    }
}

/// A user report of objectionable AI output (Apple Guideline 1.2). Routed to an
/// operator queue; purged with the account.
final class ContentReport: Model, @unchecked Sendable {
    static let schema = "content_reports"

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: User
    @OptionalField(key: "message_id") var messageID: UUID?
    @OptionalField(key: "session_id") var sessionID: UUID?
    @OptionalField(key: "trip_id") var tripID: UUID?
    @Field(key: "reason") var reason: String
    @OptionalField(key: "note") var note: String?
    @Field(key: "status") var status: String              // open | actioned
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}
    init(id: UUID? = nil, userID: User.IDValue, messageID: UUID? = nil, sessionID: UUID? = nil,
         tripID: UUID? = nil, reason: String, note: String? = nil, status: String = "open") {
        self.id = id
        self.$user.id = userID
        self.messageID = messageID
        self.sessionID = sessionID
        self.tripID = tripID
        self.reason = reason
        self.note = note
        self.status = status
    }
}
