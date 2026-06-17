import Vapor
import Fluent

/// `POST /v1/moderation/report` — the Apple Guideline 1.2 report path. Records a
/// user report of objectionable AI output → operator queue. Owner-scoped; does
/// not call the LLM. Purged with the account.
struct ReportController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let group = routes.grouped("v1", "moderation").grouped(UserAuthMiddleware())
        group.post("report", use: report)
    }

    struct ReportRequest: Content {
        let messageID: UUID?
        let sessionID: UUID?
        let tripID: UUID?
        let reason: String
        let note: String?
    }

    struct ReportResponse: Content { let reportID: UUID }

    func report(_ req: Request) async throws -> Response {
        let user = try req.auth.require(User.self)
        let body = try req.content.decode(ReportRequest.self)
        let record = ContentReport(userID: try user.requireID(), messageID: body.messageID,
                                   sessionID: body.sessionID, tripID: body.tripID,
                                   reason: body.reason, note: body.note?.prefix(2000).description)
        try await record.save(on: req.db)
        let response = try await ReportResponse(reportID: record.requireID())
            .encodeResponse(status: .accepted, for: req)
        return response
    }
}
