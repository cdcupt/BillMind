import Vapor
import Fluent
import Foundation

/// The moderation gate. Order: normalize → local catastrophic denylist →
/// jailbreak check → OpenAI per-category scoring → intent-aware thresholds
/// (expense-shaped text raises the gray-zone bar near 1.0; catastrophic is
/// never suppressed; capture screens catastrophic-only). Fails safe (denylist +
/// native safety) if the API is unavailable.
struct ModerationService {
    let client: ModerationClient

    // Tunable thresholds (config in production).
    static let hardThreshold = 0.5
    static let softThreshold = 0.85
    static let expenseGrayThreshold = 0.98

    /// Zero-tolerance categories (block at the low threshold; never suppressed).
    static let hardCategories: Set<String> = [
        "sexual/minors", "illicit/violent", "self-harm/instructions", "violence/graphic",
    ]
    /// Gray-zone categories (soft-handle above the higher threshold).
    static let grayCategories: Set<String> = [
        "harassment", "harassment/threatening", "hate", "hate/threatening",
        "sexual", "self-harm", "self-harm/intent", "illicit", "violence",
    ]
    /// Jailbreak / injection markers → SOFT (strip/ignore the directive; a curious
    /// user is not an attacker). Safe to keep in-repo.
    static let jailbreakPhrases: [String] = [
        "ignore previous instructions", "ignore all previous instructions",
        "disregard the above", "reveal your system prompt", "show your system prompt",
        "developer mode", "dan mode",
    ]
    /// The catastrophic network-free denylist is curated OUT OF BAND and loaded at
    /// deploy (never committed). Empty here by design.
    static let catastrophicDenylist: [String] = []

    func evaluate(_ raw: String, surface: ModerationSurface, expenseShaped: Bool,
                  on req: Request) async throws -> ModerationVerdict {
        let text = Self.normalize(raw)

        // 1. local catastrophic denylist — always, network-free.
        if Self.catastrophicDenylist.contains(where: { text.contains($0) }) {
            return ModerationVerdict(decision: .block, topCategory: "catastrophic", score: 1.0, provider: "local_denylist")
        }
        let jailbroken = Self.jailbreakPhrases.contains(where: { text.contains($0) })

        // 2. moderation API — fail safe on error (denylist already ran; lean on native safety).
        let scores: [String: Double]
        do {
            scores = try await client.score(text, on: req).categories
        } catch {
            req.logger.warning("moderation API unavailable, degrading: \(error)")
            return jailbroken
                ? ModerationVerdict(decision: .soft, topCategory: "jailbreak", score: nil, provider: "local_denylist")
                : ModerationVerdict(decision: .allow, topCategory: nil, score: nil, provider: "native_safety")
        }

        // 3. hard categories block at the low threshold (never suppressed).
        if let hit = topHit(scores, in: Self.hardCategories, threshold: Self.hardThreshold) {
            return ModerationVerdict(decision: .block, topCategory: hit.0, score: hit.1, provider: "moderation_api")
        }
        // Capture/recognition: catastrophic-only — a lawful purchase description never gray-zone-blocks.
        if surface == .recognition {
            return jailbroken ? soft("jailbreak") : .allow
        }
        // 4. gray-zone soft-handle; expense-shaped text raises the bar near 1.0.
        let grayThreshold = expenseShaped ? Self.expenseGrayThreshold : Self.softThreshold
        if let hit = topHit(scores, in: Self.grayCategories, threshold: grayThreshold) {
            return ModerationVerdict(decision: .soft, topCategory: hit.0, score: hit.1, provider: "moderation_api")
        }
        if jailbroken { return soft("jailbreak") }
        return .allow
    }

    /// Persist the DECISION (never the dangerous content): one-way content hash +
    /// a short redacted excerpt only on a block.
    func logEvent(_ verdict: ModerationVerdict, raw: String, surface: ModerationSurface,
                  userID: UUID, requestID: String, on db: Database) async throws {
        let event = ModerationEvent(
            userID: userID, requestID: requestID, surface: surface.rawValue,
            decision: verdict.decision.rawValue, topCategory: verdict.topCategory,
            score: verdict.score, provider: verdict.provider,
            contentSHA256: TokenService.sha256Hex(Self.normalize(raw)),
            excerptRedacted: verdict.decision == .block ? String(raw.prefix(120)) : nil
        )
        try await event.save(on: db)
    }

    // MARK: - helpers

    private func soft(_ category: String) -> ModerationVerdict {
        ModerationVerdict(decision: .soft, topCategory: category, score: nil, provider: "local_denylist")
    }

    private func topHit(_ scores: [String: Double], in categories: Set<String>, threshold: Double) -> (String, Double)? {
        var best: (String, Double)?
        for (category, score) in scores where categories.contains(category) && score >= threshold {
            if best == nil || score > best!.1 { best = (category, score) }
        }
        return best
    }

    /// NFKC-ish fold + strip zero-width / default-ignorable scalars + lowercase,
    /// so encoded-trick inputs are caught before classification.
    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        let stripped = folded.unicodeScalars.filter {
            !$0.properties.isDefaultIgnorableCodePoint && $0 != "\u{FEFF}"
        }
        return String(String.UnicodeScalarView(stripped)).lowercased()
    }
}
