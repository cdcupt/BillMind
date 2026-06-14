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
        app.logger.info("Postgres configured from DATABASE_URL")
    } else {
        app.logger.warning("DATABASE_URL not set — running without a database (skeleton mode)")
    }

    // Body size cap (receipt uploads get a dedicated, larger route limit later).
    app.routes.defaultMaxBodySize = "1mb"

    try routes(app)
}
