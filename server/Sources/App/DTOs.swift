import Vapor

/// The session pair returned by sign-in / refresh.
struct AuthTokensDTO: Content {
    let accessToken: String
    let refreshToken: String
    let userID: UUID
}

/// Account identity for the client (Settings → Account).
struct UserDTO: Content {
    let id: UUID
    let displayName: String?
    let email: String?
    let aiQuotaTier: String

    init(_ user: User) throws {
        self.id = try user.requireID()
        self.displayName = user.displayName
        self.email = user.primaryEmail
        self.aiQuotaTier = user.aiQuotaTier
    }
}
