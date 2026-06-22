import Vapor
import BillMindCore

/// The fusion + dedup reasoner. Given the held cards (text-only — drafts, notes,
/// photo hashes, NO image bytes), it proposes which cards are ONE bill (fuse) or
/// the SAME bill (dup). Injectable so the controller (and its money guard) is
/// tested without Gemini, mirroring the `Recognizer` DI pattern.
///
/// The reasoner only PROPOSES. The controller enforces money-safety regardless of
/// what the model returns (verbatim-amount post-check) and guarantees the partition
/// invariant — so a buggy or adversarial model can never mint an amount or drop a
/// card. The reasoner's amount on a fused group is advisory; the controller drops
/// any value that isn't byte-equal to a member card's amount.
protocol UntangleReasoner: Sendable {
    func untangle(_ inputs: [UntangleInput], today: String, on req: Request) async throws -> UntanglePlan
}

// MARK: - Plan (the reasoner's proposal, pre-guard)

/// A fuse proposal as the reasoner returns it. The controller re-derives the amount
/// and trace from member cards; `proposedAmount` / `amountSourceCardID` are only
/// what the model SUGGESTED and are validated against the inputs before use.
struct ProposedFuse: Sendable {
    let sourceCardIDs: [UUID]
    let merchant: String?
    let proposedAmount: Decimal?
    let currencyCode: String?
    let categoryRaw: String?
    let date: Date?
    /// Which member card the model claims the amount came from (cited, not trusted).
    let amountSourceCardID: UUID?
    let reason: String
    let confidence: Double
}

struct ProposedDuplicate: Sendable {
    let memberCardIDs: [UUID]
    let survivorCardID: UUID
    let tier: String        // "samePhoto" | "sameDetails"
    let reason: String
}

/// The reasoner's raw proposal. May be incomplete or wrong about money/partition —
/// the controller sanitizes it. `declined` lets the reasoner opt the whole batch out.
struct UntanglePlan: Sendable {
    var fuses: [ProposedFuse] = []
    var duplicates: [ProposedDuplicate] = []
    var declined: Bool = false
    var message: String? = nil

    static let empty = UntanglePlan()
}

// MARK: - Stub (tests)

/// Deterministic test double — returns a fixed plan. Mirrors `StubRecognizer`.
struct StubUntangleReasoner: UntangleReasoner {
    var plan: UntanglePlan = .empty
    func untangle(_ inputs: [UntangleInput], today: String, on req: Request) async throws -> UntanglePlan { plan }
}

/// A reasoner that never groups anything — every card is clean. The default in
/// production wiring would still be the Gemini one; this is a safe no-op fallback.
struct NoopUntangleReasoner: UntangleReasoner {
    func untangle(_ inputs: [UntangleInput], today: String, on req: Request) async throws -> UntanglePlan { .empty }
}

// MARK: - Gemini (live)

/// Live fusion/dedup over Gemini `generateContent` (strict JSON, thinkingBudget:0),
/// mirroring `GeminiRecognizer`. The PROMPT forbids minting amounts and forbids
/// fusing cards whose amounts disagree; the request build + response parse are
/// pure/static so they unit-test without a network call. Money-safety does NOT
/// depend on the prompt being obeyed — the controller re-checks every amount.
struct GeminiUntangleReasoner: UntangleReasoner {
    let model: String

    init(model: String = "gemini-2.5-flash") { self.model = model }

    static let instructions = """
    You de-tangle a small batch of expense cards the user just captured. Decide, \
    using ONLY the data given, which cards are:
      • ONE bill split across cards (FUSE) — e.g. a partial photo completed by a note;
      • the SAME bill captured twice (DUPLICATE) — e.g. the same photo, or the same \
        merchant+amount+date.
    Cards not in any group are clean and need no entry.

    STRICT JSON output (no prose, no markdown), an object with keys:
      "fuses": [ { "sourceCardIDs": [card-id, ...], "merchant": string?, \
    "amount": number?, "currency": string?, "category": string?, "date": "yyyy-MM-dd"?, \
    "amountSourceCardID": card-id?, "reason": string, "confidence": number } ],
      "duplicates": [ { "memberCardIDs": [card-id, ...], "survivorCardID": card-id, \
    "tier": "samePhoto" | "sameDetails", "reason": string } ],
      "declined": boolean?, "message": string?

    MONEY RULES (mandatory):
      • For a fuse, set each field ONLY from a card that already contains it. Never \
    write a value no card provided.
      • NEVER output an amount that is not present VERBATIM in one of the input cards. \
    If you set an amount, set "amountSourceCardID" to the card it came from.
      • If two cards in a would-be fuse carry DIFFERENT amounts, DO NOT fuse them.
      • If no card in a fuse supplies an amount, OMIT "amount" (and "amountSourceCardID").
    Use only card ids that appear in the input. Reference each card in at most one group.
    """

    func untangle(_ inputs: [UntangleInput], today: String, on req: Request) async throws -> UntanglePlan {
        guard let key = Environment.get("GEMINI_API_KEY"), !key.isEmpty else {
            throw Abort(.serviceUnavailable, reason: "GEMINI_API_KEY not configured")
        }
        let uri = URI(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(key)")
        let prompt = Self.instructions + "\ntoday=\(today)\nCards:\n" + Self.encodeCards(inputs)
        let body = GVReq(contents: [GVContent(role: "user", parts: [
            GVPart(text: prompt, inlineData: nil),
        ])], generationConfig: .fastStructured)
        let response = try await req.client.post(uri) { try $0.content.encode(body) }
        guard response.status == .ok else {
            throw Abort(.badGateway, reason: "Gemini untangle returned \(response.status.code)")
        }
        let data = response.body.map { Data(buffer: $0) } ?? Data()
        return try Self.parse(data)
    }

    // MARK: - pure, testable

    /// A compact, model-readable rendering of the cards (ids + the fields the model
    /// is allowed to copy from). Amounts are passed as strings so the model echoes
    /// them verbatim rather than reformatting a float.
    static func encodeCards(_ inputs: [UntangleInput]) -> String {
        inputs.map { input in
            let d = input.draft
            let amount = d.amount.map { NSDecimalNumber(decimal: $0).stringValue } ?? "null"
            let merchant = d.merchant ?? "null"
            let note = input.noteText ?? "null"
            let hash = input.photoHash ?? "null"
            return "- cardID=\(input.cardID) merchant=\(merchant) amount=\(amount) " +
                   "currency=\(d.currencyCode) category=\(d.categoryRaw ?? "null") " +
                   "hasPhoto=\(input.hasPhoto) note=\(note) photoHash=\(hash)"
        }.joined(separator: "\n")
    }

    /// Pull the model's text, extract the JSON object (tolerating ``` fences / prose),
    /// and decode it into an `UntanglePlan`. Unknown/garbage shapes degrade to an
    /// empty plan (every card clean) rather than throwing — the batch still saves.
    static func parse(_ data: Data) throws -> UntanglePlan {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let parts = (((obj?["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
        let text = parts.compactMap { $0["text"] as? String }.joined()
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start <= end else {
            return .empty
        }
        let jsonText = String(text[start...end])
        guard let root = (try? JSONSerialization.jsonObject(with: Data(jsonText.utf8))) as? [String: Any] else {
            return .empty
        }
        return decodePlan(root)
    }

    static func decodePlan(_ root: [String: Any]) -> UntanglePlan {
        var plan = UntanglePlan()
        plan.declined = root["declined"] as? Bool ?? false
        plan.message = root["message"] as? String

        for raw in (root["fuses"] as? [[String: Any]] ?? []) {
            let ids = uuids(raw["sourceCardIDs"])
            guard !ids.isEmpty else { continue }
            plan.fuses.append(ProposedFuse(
                sourceCardIDs: ids,
                merchant: raw["merchant"] as? String,
                proposedAmount: decimal(raw["amount"]),
                currencyCode: raw["currency"] as? String,
                categoryRaw: (raw["category"] as? String)?.lowercased(),
                date: date(raw["date"]),
                amountSourceCardID: (raw["amountSourceCardID"] as? String).flatMap { UUID(uuidString: $0) },
                reason: raw["reason"] as? String ?? "fused",
                confidence: number(raw["confidence"]) ?? 0
            ))
        }
        for raw in (root["duplicates"] as? [[String: Any]] ?? []) {
            let ids = uuids(raw["memberCardIDs"])
            guard ids.count >= 2,
                  let survivor = (raw["survivorCardID"] as? String).flatMap({ UUID(uuidString: $0) }) ?? ids.first
            else { continue }
            let tier = (raw["tier"] as? String) == "samePhoto" ? "samePhoto" : "sameDetails"
            plan.duplicates.append(ProposedDuplicate(
                memberCardIDs: ids,
                survivorCardID: ids.contains(survivor) ? survivor : ids[0],
                tier: tier,
                reason: raw["reason"] as? String ?? "duplicate"
            ))
        }
        return plan
    }

    // MARK: - lenient scalar coercion

    private static func uuids(_ any: Any?) -> [UUID] {
        (any as? [Any] ?? []).compactMap { ($0 as? String).flatMap { UUID(uuidString: $0) } }
    }
    private static func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }
    /// Amount is decoded as a `Decimal` from the model's string/number. We round-trip
    /// through a string so the value compares byte-exact against a member card's amount.
    private static func decimal(_ any: Any?) -> Decimal? {
        if let s = any as? String { return Decimal(string: s) }
        if let i = any as? Int { return Decimal(i) }
        if let d = any as? Double { return Decimal(string: NSNumber(value: d).stringValue) }
        return nil
    }
    private static func date(_ any: Any?) -> Date? {
        guard let s = any as? String else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
}
