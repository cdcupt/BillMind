import Vapor
import Fluent

/// Per-account AI quota — counts today's chat usage and refuses when over.
/// Checked BEFORE any model call (a block costs zero provider tokens). Free
/// moderation calls are not metered, so they never count here.
struct QuotaService {
    let dailyChatLimit: Int

    init(dailyChatLimit: Int = 200) {
        self.dailyChatLimit = dailyChatLimit
    }

    func assertChatAllowed(_ userID: UUID, on db: Database) async throws {
        let since = Calendar.current.startOfDay(for: Date())
        let usedToday = try await AIUsage.query(on: db)
            .filter(\.$user.$id == userID)
            .filter(\.$kind == "chat")
            .filter(\.$createdAt >= since)
            .count()
        guard usedToday < dailyChatLimit else {
            throw Abort(.tooManyRequests, reason: "You've used today's AI. Text capture still works — try again tomorrow.")
        }
    }
}
