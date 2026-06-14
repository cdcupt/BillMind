import Vapor
import Fluent

/// `/v1/auth/*` — provider sign-in, refresh rotation, logout.
struct AuthController: RouteCollection {
    let oidc: OIDCVerifier

    func boot(routes: RoutesBuilder) throws {
        let auth = routes.grouped("v1", "auth")
        auth.post("apple") { try await self.signIn($0, provider: .apple) }
        auth.post("google") { try await self.signIn($0, provider: .google) }
        auth.post("refresh", use: refresh)
        auth.post("logout", use: logout)
    }

    struct SignInRequest: Content { let idToken: String; let nonce: String? }
    struct RefreshRequest: Content { let refreshToken: String }

    func signIn(_ req: Request, provider: OIDCProvider) async throws -> AuthTokensDTO {
        let body = try req.content.decode(SignInRequest.self)
        let verified = try await oidc.verify(idToken: body.idToken, provider: provider, on: req)
        let user = try await findOrCreateUser(req, verified: verified)
        let uid = try user.requireID()
        let access = try TokenService.issueAccess(req, userID: uid)
        let refresh = try await TokenService.issueRefresh(req, userID: uid)
        return AuthTokensDTO(accessToken: access, refreshToken: refresh, userID: uid)
    }

    /// Identity lookup is keyed on (provider, subject) — never email. A verified,
    /// non-relay email links a second provider to the same account; otherwise a
    /// fresh account is created (Apple private-relay addresses are not stored as
    /// the primary email).
    private func findOrCreateUser(_ req: Request, verified: VerifiedIdentity) async throws -> User {
        if let identity = try await Identity.query(on: req.db)
            .filter(\.$provider == verified.provider.rawValue)
            .filter(\.$subject == verified.subject)
            .with(\.$user).first() {
            return identity.user
        }

        if let email = verified.email, !verified.isPrivateRelay,
           let existing = try await User.query(on: req.db).filter(\.$primaryEmail == email).first() {
            let identity = Identity(userID: try existing.requireID(), provider: verified.provider.rawValue,
                                    subject: verified.subject, emailAtLink: email, isPrivateRelay: false)
            try await identity.save(on: req.db)
            return existing
        }

        let user = User(displayName: verified.name,
                        primaryEmail: verified.isPrivateRelay ? nil : verified.email)
        try await user.save(on: req.db)
        let identity = Identity(userID: try user.requireID(), provider: verified.provider.rawValue,
                                subject: verified.subject, emailAtLink: verified.email,
                                isPrivateRelay: verified.isPrivateRelay)
        try await identity.save(on: req.db)
        return user
    }

    func refresh(_ req: Request) async throws -> AuthTokensDTO {
        let body = try req.content.decode(RefreshRequest.self)
        let rotated = try await TokenService.rotate(req, presentedRefresh: body.refreshToken)
        return AuthTokensDTO(accessToken: rotated.access, refreshToken: rotated.refresh, userID: rotated.userID)
    }

    func logout(_ req: Request) async throws -> HTTPStatus {
        let body = try req.content.decode(RefreshRequest.self)
        try await TokenService.revoke(req, presentedRefresh: body.refreshToken)
        return .noContent
    }
}
