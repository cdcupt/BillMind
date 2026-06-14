import Vapor

enum ModerationDecision: String, Content {
    case allow      // proceed normally
    case soft       // de-escalate (disambiguation / supportive / strip-injection)
    case block      // refuse before any model call
}

enum ModerationSurface: String, Content {
    case chatInput = "chat_input"
    case chatOutput = "chat_output"
    case recognition
}

struct ModerationVerdict {
    let decision: ModerationDecision
    let topCategory: String?
    let score: Double?
    let provider: String   // moderation_api | local_denylist | native_safety

    static let allow = ModerationVerdict(decision: .allow, topCategory: nil, score: nil, provider: "moderation_api")
}

struct ModerationScores: Content {
    let categories: [String: Double]
}

/// Injectable so tests run the gate logic without calling OpenAI.
protocol ModerationClient: Sendable {
    func score(_ text: String, on req: Request) async throws -> ModerationScores
}
