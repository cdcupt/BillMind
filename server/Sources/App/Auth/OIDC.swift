import Vapor
@preconcurrency import JWT

enum OIDCProvider: String, Content {
    case apple
    case google
}

/// What we trust after verifying a provider id_token.
struct VerifiedIdentity {
    let provider: OIDCProvider
    let subject: String          // the stable OIDC "sub"
    let email: String?
    let isPrivateRelay: Bool
    let name: String?
}

/// Injectable so tests can stub provider verification (no real id_tokens needed).
protocol OIDCVerifier: Sendable {
    func verify(idToken: String, provider: OIDCProvider, on req: Request) async throws -> VerifiedIdentity
}

/// Claims we read out of an Apple/Google id_token.
private struct OIDCClaims: JWTPayload {
    let iss: IssuerClaim
    let sub: SubjectClaim
    let aud: AudienceClaim
    let exp: ExpirationClaim
    let email: String?
    func verify(using signer: JWTSigner) throws { try exp.verifyNotExpired() }
}

/// Verifies the id_token's signature against the provider's published JWKS, then
/// checks issuer / audience / expiry.
struct LiveOIDCVerifier: OIDCVerifier {
    func verify(idToken: String, provider: OIDCProvider, on req: Request) async throws -> VerifiedIdentity {
        let jwksURL: String
        let issuers: [String]
        let audience: String?
        switch provider {
        case .apple:
            jwksURL = "https://appleid.apple.com/auth/keys"
            issuers = ["https://appleid.apple.com"]
            audience = Environment.get("APPLE_CLIENT_ID")
        case .google:
            jwksURL = "https://www.googleapis.com/oauth2/v3/certs"
            issuers = ["https://accounts.google.com", "accounts.google.com"]
            audience = Environment.get("GOOGLE_CLIENT_ID")
        }

        let response = try await req.client.get(URI(string: jwksURL))
        let jwks = try response.content.decode(JWKS.self)
        let signers = JWTSigners()
        try signers.use(jwks: jwks)

        let claims = try signers.verify(idToken, as: OIDCClaims.self)
        guard issuers.contains(claims.iss.value) else {
            throw Abort(.unauthorized, reason: "id_token issuer mismatch")
        }
        if let audience {
            guard claims.aud.value.contains(audience) else {
                throw Abort(.unauthorized, reason: "id_token audience mismatch")
            }
        }
        try claims.exp.verifyNotExpired()

        let email = claims.email
        let isRelay = email?.hasSuffix("privaterelay.appleid.com") ?? false
        return VerifiedIdentity(provider: provider, subject: claims.sub.value,
                                email: email, isPrivateRelay: isRelay, name: nil)
    }
}
