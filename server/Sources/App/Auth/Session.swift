import Vapor
@preconcurrency import JWT
import Fluent

/// Our own short-lived access token (HS256). The client sends it as a bearer;
/// the refresh token (opaque, revocable) mints new ones.
struct SessionToken: Content, JWTPayload {
    var sub: SubjectClaim
    var exp: ExpirationClaim

    init(userID: UUID, ttl: TimeInterval = 900) {
        self.sub = SubjectClaim(value: userID.uuidString)
        self.exp = ExpirationClaim(value: Date().addingTimeInterval(ttl))
    }

    func verify(using signer: JWTSigner) throws {
        try exp.verifyNotExpired()
    }

    var userID: UUID? { UUID(uuidString: sub.value) }
}

extension User: Authenticatable {}

/// Bearer access-JWT → `currentUser`. Rejects unknown or soft-deleted users.
/// Every protected route group runs behind this; tenant scoping then filters
/// every query by `req.auth.require(User.self)`.
struct UserAuthMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let token: SessionToken
        do {
            token = try request.jwt.verify(as: SessionToken.self)
        } catch {
            throw Abort(.unauthorized, reason: "invalid or expired session")
        }
        guard let uid = token.userID,
              let user = try await User.find(uid, on: request.db),
              user.deletedAt == nil
        else {
            throw Abort(.unauthorized)
        }
        request.auth.login(user)
        return try await next.respond(to: request)
    }
}
