import Fluent
import Foundation

/// The account. Email is nullable + relay-aware (Apple may send only a private
/// relay address, or nothing on later logins) — identity is keyed off the OIDC
/// subject, never email. Soft-deleted so `DELETE /account` can purge in order.
final class User: Model, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id) var id: UUID?
    @OptionalField(key: "display_name") var displayName: String?
    @OptionalField(key: "primary_email") var primaryEmail: String?
    @Field(key: "ai_quota_tier") var aiQuotaTier: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?
    @Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?

    init() {}
    init(id: UUID? = nil, displayName: String? = nil, primaryEmail: String? = nil, aiQuotaTier: String = "free") {
        self.id = id
        self.displayName = displayName
        self.primaryEmail = primaryEmail
        self.aiQuotaTier = aiQuotaTier
    }
}

/// One sign-in identity (Apple or Google). Separate from `User` so a person can
/// link both providers to one account. Login lookup is UNIQUE(provider, subject).
final class Identity: Model, @unchecked Sendable {
    static let schema = "identities"

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: User
    @Field(key: "provider") var provider: String          // "apple" | "google"
    @Field(key: "subject") var subject: String            // OIDC "sub"
    @OptionalField(key: "email_at_link") var emailAtLink: String?
    @Field(key: "is_private_relay") var isPrivateRelay: Bool
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}
    init(id: UUID? = nil, userID: User.IDValue, provider: String, subject: String,
         emailAtLink: String? = nil, isPrivateRelay: Bool = false) {
        self.id = id
        self.$user.id = userID
        self.provider = provider
        self.subject = subject
        self.emailAtLink = emailAtLink
        self.isPrivateRelay = isPrivateRelay
    }
}

/// An opaque, revocable refresh token (only its SHA-256 hash is stored, never
/// the raw value). Revocation is what makes sign-out and account-deletion real.
final class RefreshToken: Model, @unchecked Sendable {
    static let schema = "refresh_tokens"

    @ID(key: .id) var id: UUID?
    @Parent(key: "user_id") var user: User
    @Field(key: "token_hash") var tokenHash: String       // hex SHA-256 of the opaque token
    @Timestamp(key: "issued_at", on: .create) var issuedAt: Date?
    @Field(key: "expires_at") var expiresAt: Date
    @OptionalField(key: "revoked_at") var revokedAt: Date?

    init() {}
    init(id: UUID? = nil, userID: User.IDValue, tokenHash: String, expiresAt: Date) {
        self.id = id
        self.$user.id = userID
        self.tokenHash = tokenHash
        self.expiresAt = expiresAt
    }
}
