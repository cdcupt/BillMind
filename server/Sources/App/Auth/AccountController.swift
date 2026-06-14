import Vapor
import Fluent

/// `/v1/account/*` — behind auth. Identity + the Apple-mandated deletion.
struct AccountController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let acct = routes.grouped("v1", "account").grouped(UserAuthMiddleware())
        acct.get("me", use: me)
        acct.delete(use: deleteAccount)
    }

    func me(_ req: Request) async throws -> UserDTO {
        try UserDTO(req.auth.require(User.self))
    }

    /// Explicit, ordered, idempotent purge in one transaction — does NOT rely on
    /// DB cascade (so it behaves identically on Postgres and SQLite and is fully
    /// testable). Guideline 5.1.1(v): every user-scoped row is removed.
    /// (Receipt-image blob purge hooks in here once the blob store lands — it
    /// must run before bill_images rows are deleted.)
    func deleteAccount(_ req: Request) async throws -> HTTPStatus {
        let user = try req.auth.require(User.self)
        let uid = try user.requireID()

        try await req.db.transaction { db in
            // trips → bills → line items / images
            let tripIDs = try await Trip.query(on: db).filter(\.$owner.$id == uid).all()
                .map { try $0.requireID() }
            if !tripIDs.isEmpty {
                let billIDs = try await Bill.query(on: db).filter(\.$trip.$id ~~ tripIDs).all()
                    .map { try $0.requireID() }
                if !billIDs.isEmpty {
                    try await LineItem.query(on: db).filter(\.$bill.$id ~~ billIDs).delete(force: true)
                    try await BillImage.query(on: db).filter(\.$bill.$id ~~ billIDs).delete(force: true)
                    try await Bill.query(on: db).filter(\.$trip.$id ~~ tripIDs).delete(force: true)
                }
                try await Trip.query(on: db).filter(\.$owner.$id == uid).delete(force: true)
            }

            // conversations → messages → tool_calls
            let convIDs = try await Conversation.query(on: db).filter(\.$user.$id == uid).all()
                .map { try $0.requireID() }
            if !convIDs.isEmpty {
                let msgIDs = try await Message.query(on: db).filter(\.$conversation.$id ~~ convIDs).all()
                    .map { try $0.requireID() }
                if !msgIDs.isEmpty {
                    try await ToolCall.query(on: db).filter(\.$message.$id ~~ msgIDs).delete(force: true)
                    try await Message.query(on: db).filter(\.$conversation.$id ~~ convIDs).delete(force: true)
                }
                try await Conversation.query(on: db).filter(\.$user.$id == uid).delete(force: true)
            }

            // direct user-scoped rows (incl. the LLM logs + safety + sessions)
            try await AIUsage.query(on: db).filter(\.$user.$id == uid).delete(force: true)
            try await ModerationEvent.query(on: db).filter(\.$user.$id == uid).delete(force: true)
            try await ContentReport.query(on: db).filter(\.$user.$id == uid).delete(force: true)
            try await RefreshToken.query(on: db).filter(\.$user.$id == uid).delete(force: true)
            try await Identity.query(on: db).filter(\.$user.$id == uid).delete(force: true)

            try await user.delete(force: true, on: db)
        }
        return .noContent
    }
}
