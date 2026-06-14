import Vapor

/// The live primary classifier: OpenAI's free `omni-moderation-latest` endpoint.
/// Returns per-category continuous scores; not metered into the AI quota.
struct OpenAIModerationClient: ModerationClient {
    func score(_ text: String, on req: Request) async throws -> ModerationScores {
        guard let key = Environment.get("OPENAI_MODERATION_KEY"), !key.isEmpty else {
            throw Abort(.internalServerError, reason: "OPENAI_MODERATION_KEY not configured")
        }
        let uri = URI(string: "https://api.openai.com/v1/moderations")
        let response = try await req.client.post(uri) { out in
            out.headers.bearerAuthorization = .init(token: key)
            try out.content.encode(Request_(model: "omni-moderation-latest", input: text))
        }
        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "moderation API returned \(response.status.code)")
        }
        let decoded = try response.content.decode(Response_.self)
        return ModerationScores(categories: decoded.results.first?.categoryScores ?? [:])
    }

    private struct Request_: Content { let model: String; let input: String }
    private struct Response_: Content {
        struct Result: Content {
            let flagged: Bool
            let categoryScores: [String: Double]
            enum CodingKeys: String, CodingKey { case flagged; case categoryScores = "category_scores" }
        }
        let results: [Result]
    }
}
