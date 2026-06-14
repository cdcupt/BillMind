import Vapor
import Fluent
import FluentPostgresDriver

/// Boot-time configuration. Reads everything from the environment (the VPS
/// `.env`); fails fast on malformed required secrets as subsystems are wired in.
public func configure(_ app: Application) async throws {
    EnvConfig.validate(app)

    // Postgres — configured only when DATABASE_URL is present, so the skeleton
    // (and `/healthz`) boots in dev without a database. Migrations land in the
    // next slice (the data model).
    if let databaseURL = Environment.get("DATABASE_URL") {
        try app.databases.use(.postgres(url: databaseURL), as: .psql)
        app.migrations.add(CreateInitialSchema())
        // Single-instance v1: apply pending migrations on boot.
        try await app.autoMigrate()
        app.logger.info("Postgres configured + migrated")
    } else {
        app.logger.warning("DATABASE_URL not set — running without a database (skeleton mode)")
    }

    // Body size cap (receipt uploads get a dedicated, larger route limit later).
    app.routes.defaultMaxBodySize = "1mb"

    // Session signing (HS256). Required secret in production; dev fallback only.
    let signingKey = Environment.get("JWT_SIGNING_KEY")
        ?? "dev-insecure-signing-key-change-me-0123456789"
    app.jwt.signers.use(.hs256(key: Array(signingKey.utf8)))

    try routes(app)
    try app.register(collection: AuthController(oidc: LiveOIDCVerifier()))
    try app.register(collection: AccountController())
    try app.register(collection: TripController())
    try app.register(collection: BillController())
    try app.register(collection: StatsController())
    let moderationService = ModerationService(client: OpenAIModerationClient())
    try app.register(collection: CaptureController(moderation: moderationService))
    let geminiModel = Environment.get("GEMINI_MODEL") ?? "gemini-2.0-flash"
    try app.register(collection: AgentController(agent: AgentService(
        llm: GeminiLLMClient(model: geminiModel), moderation: moderationService, quota: QuotaService()
    )))
    try app.register(collection: SyncController())
    try app.register(collection: ReportController())
}
