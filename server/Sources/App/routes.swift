import Vapor

func routes(_ app: Application) throws {
    // Liveness/readiness probe — used by Docker Compose healthcheck + Caddy.
    app.get("healthz") { _ async -> HealthStatus in
        HealthStatus(status: "ok", service: "billmind-server", version: "0.1.0")
    }

    app.get { _ async -> String in
        "BillMind 2.0 server — see /healthz"
    }
}

struct HealthStatus: Content {
    let status: String
    let service: String
    let version: String
}
