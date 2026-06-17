import Vapor
import Fluent
import Crypto

/// Issues / rotates / revokes sessions. Access = short HS256 JWT; refresh =
/// opaque random token, of which only the SHA-256 hash is stored.
enum TokenService {
    static let refreshTTL: TimeInterval = 60 * 60 * 24 * 30   // 30 days

    static func issueAccess(_ req: Request, userID: UUID) throws -> String {
        try req.jwt.sign(SessionToken(userID: userID))
    }

    static func issueRefresh(_ req: Request, userID: UUID) async throws -> String {
        let raw = randomToken()
        let token = RefreshToken(userID: userID, tokenHash: sha256Hex(raw),
                                 expiresAt: Date().addingTimeInterval(refreshTTL))
        try await token.save(on: req.db)
        return raw
    }

    /// Validate the presented refresh token, revoke it, and mint a fresh pair.
    static func rotate(_ req: Request, presentedRefresh raw: String) async throws
        -> (access: String, refresh: String, userID: UUID) {
        let hash = sha256Hex(raw)
        guard let token = try await RefreshToken.query(on: req.db)
            .filter(\.$tokenHash == hash).first(),
            token.revokedAt == nil, token.expiresAt > Date()
        else {
            throw Abort(.unauthorized, reason: "invalid refresh token")
        }
        token.revokedAt = Date()
        try await token.save(on: req.db)

        let userID = token.$user.id
        let access = try issueAccess(req, userID: userID)
        let refresh = try await issueRefresh(req, userID: userID)
        return (access, refresh, userID)
    }

    static func revoke(_ req: Request, presentedRefresh raw: String) async throws {
        let hash = sha256Hex(raw)
        if let token = try await RefreshToken.query(on: req.db)
            .filter(\.$tokenHash == hash).first(), token.revokedAt == nil {
            token.revokedAt = Date()
            try await token.save(on: req.db)
        }
    }

    static func revokeAll(_ req: Request, userID: UUID) async throws {
        let tokens = try await RefreshToken.query(on: req.db)
            .filter(\.$user.$id == userID).all()
        for token in tokens where token.revokedAt == nil {
            token.revokedAt = Date()
            try await token.save(on: req.db)
        }
    }

    // MARK: - helpers

    private static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        for i in bytes.indices { bytes[i] = UInt8.random(in: .min ... .max) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func sha256Hex(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
