import Vapor
import Fluent
import BillMindCore

/// `POST /v1/untangle` — the held-batch reasoning hop. The client sends the cards
/// it already holds (text-only, no image bytes) and gets back a PLAN: which cards
/// are ONE bill (fuse), which are the SAME bill (dup), which are clean. Recognition
/// is NOT repeated; this is an optional second hop over cards the client already
/// got from /v1/recognition. The save path is unchanged — untangle returns a plan
/// only (one fused card → one bill, saved later via the existing confirm route).
///
/// Money-safety is enforced HERE, server-side, regardless of the model:
///   ① verbatim-amount post-check — a fused `resolvedDraft.amount` is dropped unless
///      it is Decimal-equal to one of that group's MEMBER-CARD amounts (and the
///      cited trace card actually carries it); amountTrace is nulled when dropped.
///   ② conflicting amounts are never fused (the reasoner is told, and we re-check).
///   ③ partition invariant — every input cardID lands in exactly one bucket; any
///      card the model omits (or double-claims) falls open to cleanCardIDs.
/// No new free-text enters the system, so there is no re-moderation.
struct UntangleController: RouteCollection {
    let reasoner: UntangleReasoner

    init(reasoner: UntangleReasoner) { self.reasoner = reasoner }

    func boot(routes: RoutesBuilder) throws {
        let group = routes.grouped("v1").grouped(UserAuthMiddleware())
        // Text-only body (drafts + photo hashes, no image bytes) → the tight global
        // 1mb cap is fine; no per-route override needed.
        group.post("untangle", use: untangle)
    }

    func untangle(_ req: Request) async throws -> UntangleResponse {
        let user = try req.auth.require(User.self)
        let uid = try user.requireID()
        let body = try req.content.decode(UntangleRequest.self)

        // Owner-scope on tripID — a foreign trip is 404 (mirrors CaptureController).
        guard let trip = try await Trip.query(on: req.db)
            .filter(\.$id == body.tripID).filter(\.$owner.$id == uid).first()
        else { throw Abort(.notFound, reason: "trip not found") }

        let inputs = body.inputs
        // Empty or single-input batches need no reasoning: the lone (or zero) card is
        // clean by definition. This also matches the A6 fast path — a single input is
        // never grouped.
        guard inputs.count > 1 else {
            return UntangleResponse(declined: false, message: nil, fuseGroups: [],
                                    duplicateGroups: [], cleanCardIDs: inputs.map(\.cardID))
        }

        let today = CaptureController.validClientDate(body.clientDate) ?? LocalTextRecognizer.utcTodayString()
        let plan = try await reasoner.untangle(inputs, today: today, on: req)
        if plan.declined {
            // A declined batch still partitions cleanly: nothing grouped, all clean.
            return UntangleResponse(declined: true, message: plan.message,
                                    fuseGroups: [], duplicateGroups: [],
                                    cleanCardIDs: inputs.map(\.cardID))
        }

        return Self.assemble(plan: plan, inputs: inputs, trip: trip)
    }

    // MARK: - Plan → guarded, partitioned response (pure / testable)

    /// Sanitize the model's proposal into the wire response, enforcing the money
    /// guard and the partition invariant. Pure (no DB / network) so the critical
    /// path is unit-tested directly.
    static func assemble(plan: UntanglePlan, inputs: [UntangleInput], trip: Trip) -> UntangleResponse {
        let byID = Dictionary(uniqueKeysWithValues: inputs.map { ($0.cardID, $0) })
        let currency = trip.currencyCode
        let validator = BillValidator(
            knownCategoryRaws: Set(BillCategory.allCases.map(\.rawValue)),
            journalCurrencyCode: currency, today: Date()
        )

        var claimed = Set<UUID>()          // cardIDs placed into a group (exactly-once)
        var fuseGroups: [FuseGroupDTO] = []
        var duplicateGroups: [DuplicateGroupDTO] = []

        // --- Fuses (money-critical) ---
        for fuse in plan.fuses {
            // Only real, not-yet-claimed member cards. ≥2 distinct members or it's
            // not a fuse — a lone card is just clean.
            let members = orderedUnique(fuse.sourceCardIDs).filter { byID[$0] != nil && !claimed.contains($0) }
            guard members.count >= 2 else { continue }

            // GUARD ②: never fuse cards whose amounts disagree. Distinct member
            // amounts ⇒ refuse the fuse entirely (those cards stay for the clean set).
            let memberAmounts = members.compactMap { byID[$0]?.draft.amount }
            if hasConflictingAmounts(memberAmounts) { continue }

            // GUARD ①: the resolved amount must be byte-equal (Decimal-equal) to a
            // member card's amount, and the cited trace card must actually carry it.
            // Anything else (a minted amount, a value from no card) is dropped and the
            // trace is nulled — the client then shows "amount required".
            let (resolvedAmount, trace) = resolveAmount(fuse: fuse, members: members, byID: byID)

            let resolvedDraft = BillDraftDTO(
                merchant: fuse.merchant ?? firstNonNil(members, byID) { $0.draft.merchant },
                amount: resolvedAmount,
                currencyCode: fuse.currencyCode ?? firstNonNil(members, byID) { $0.draft.currencyCode } ?? currency,
                categoryRaw: fuse.categoryRaw ?? firstNonNil(members, byID) { $0.draft.categoryRaw },
                date: fuse.date ?? firstNonNil(members, byID) { $0.draft.date },
                source: members.compactMap { byID[$0]?.draft.source }.first ?? DraftSource.manual.rawValue
            )
            // Run the resolved draft through the existing validator (gaps are advisory
            // here; the client renders them just like a recognition card).
            _ = validator.validate(resolvedDraft.asDraft())

            members.forEach { claimed.insert($0) }
            fuseGroups.append(FuseGroupDTO(
                groupID: UUID(),
                sourceCardIDs: members,
                resolvedDraft: resolvedDraft,
                amountTrace: trace,
                reason: fuse.reason,
                confidence: fuse.confidence
            ))
        }

        // --- Duplicates ---
        for dup in plan.duplicates {
            let members = orderedUnique(dup.memberCardIDs).filter { byID[$0] != nil && !claimed.contains($0) }
            guard members.count >= 2 else { continue }
            let survivor = members.contains(dup.survivorCardID) ? dup.survivorCardID : members[0]
            members.forEach { claimed.insert($0) }
            duplicateGroups.append(DuplicateGroupDTO(
                groupID: UUID(),
                memberCardIDs: members,
                survivorCardID: survivor,
                tier: dup.tier == "samePhoto" ? "samePhoto" : "sameDetails",
                reason: dup.reason
            ))
        }

        // --- Clean set = the partition's remainder (fail-open) ---
        // Any input the model didn't group (or that we rejected above) lands here, in
        // input order. This is what guarantees the partition is TOTAL.
        let cleanCardIDs = inputs.map(\.cardID).filter { !claimed.contains($0) }

        return UntangleResponse(declined: false, message: nil,
                                fuseGroups: fuseGroups, duplicateGroups: duplicateGroups,
                                cleanCardIDs: cleanCardIDs)
    }

    // MARK: - money guard helpers

    /// The verbatim-amount post-check. Returns (amount, trace) only when the resolved
    /// amount is Decimal-equal to a member card's amount AND the trace card carries
    /// that exact value; otherwise (nil, nil) — the model cannot mint or move money.
    static func resolveAmount(fuse: ProposedFuse, members: [UUID],
                              byID: [UUID: UntangleInput]) -> (Decimal?, AmountTraceDTO?) {
        // The set of amounts the user actually provided across the member cards.
        let memberAmountByCard: [(UUID, Decimal)] = members.compactMap { id in
            byID[id]?.draft.amount.map { (id, $0) }
        }
        guard !memberAmountByCard.isEmpty else { return (nil, nil) }   // no card supplies it → omit

        // Prefer the model's proposed amount, but ONLY if it's byte-equal to a member's.
        if let proposed = fuse.proposedAmount,
           let match = memberAmountByCard.first(where: { $0.1 == proposed }) {
            // Honour the model's cited source iff that card truly carries this amount;
            // otherwise fall back to the matching member we found.
            if let cited = fuse.amountSourceCardID,
               let citedAmount = byID[cited]?.draft.amount, citedAmount == proposed,
               members.contains(cited) {
                return (proposed, AmountTraceDTO(sourceCardID: cited))
            }
            return (proposed, AmountTraceDTO(sourceCardID: match.0))
        }

        // Model proposed no amount (or a minted one we just rejected). If exactly one
        // distinct amount exists across members, that's an unambiguous trace; use it.
        let distinct = Set(memberAmountByCard.map { $0.1 })
        if distinct.count == 1, let only = memberAmountByCard.first {
            return (only.1, AmountTraceDTO(sourceCardID: only.0))
        }
        // Ambiguous (shouldn't reach here — conflicts are filtered earlier) → omit.
        return (nil, nil)
    }

    /// True when ≥2 DISTINCT amounts are present across member cards (a money conflict
    /// → must not fuse). Cards with no amount don't count as a conflict on their own.
    static func hasConflictingAmounts(_ amounts: [Decimal]) -> Bool {
        Set(amounts).count > 1
    }

    // MARK: - small pure helpers

    private static func orderedUnique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }

    private static func firstNonNil<T>(_ members: [UUID], _ byID: [UUID: UntangleInput],
                                       _ pick: (UntangleInput) -> T?) -> T? {
        for id in members { if let v = byID[id].flatMap(pick) { return v } }
        return nil
    }
}
