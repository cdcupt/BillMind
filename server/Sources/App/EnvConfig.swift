import Vapor

/// Validates environment configuration at boot. As each subsystem is wired in
/// (DB, auth, agent, moderation, blobs), its secret moves from "recommended"
/// to "required" and a missing value fails fast (process exits non-zero) — no
/// booting half-configured in production.
enum EnvConfig {
    static func validate(_ app: Application) {
        let recommended = [
            "DATABASE_URL",
            "JWT_SIGNING_KEY",
            "APPLE_CLIENT_ID",
            "GOOGLE_CLIENT_ID",
            "GEMINI_API_KEY",          // recognition + chat
            "OPENAI_MODERATION_KEY",   // moderation gate
            "BLOB_MASTER_KEY",         // receipt-image encryption
        ]
        let missing = recommended.filter { Environment.get($0) == nil }
        if missing.isEmpty {
            app.logger.info("EnvConfig: all recommended secrets present")
        } else {
            app.logger.warning("EnvConfig: not set (acceptable in skeleton mode): \(missing.joined(separator: ", "))")
        }
    }
}
