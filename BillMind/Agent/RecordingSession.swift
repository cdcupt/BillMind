import Foundation

/// A bill card tracked by a recording session: a draft plus its lifecycle state
/// and clarification bookkeeping.
struct AgentCard: Identifiable, Sendable, Equatable {
    let id: UUID
    var draft: BillDraft
    var state: CardState
    /// Number of clarification rounds already spent on this card.
    var clarifyRounds: Int
    /// Questions currently awaiting the user (chip-answerable).
    var openQuestions: [ClarificationQuestion]
    /// Gaps left unresolved after clarification was skipped or the round budget
    /// ran out. Non-empty here means confirmation requires explicit acknowledgment.
    var carriedGaps: [BillField]
}

/// What the host should do after a state transition. The session itself performs
/// no I/O, no AI, and no persistence — it returns effects for the host
/// (a `@MainActor` coordinator) to carry out. `.persist` is the *only* signal on
/// which a `BillRecord` is written.
enum SessionEffect: Sendable, Equatable {
    case askQuestions(_ questions: [ClarificationQuestion], cardID: UUID, round: Int)
    case readyForReview(cardID: UUID)
    case extractionFailed(cardID: UUID)
    case persist(cardID: UUID)
}

/// Why a confirmation was refused.
enum ConfirmError: Error, Sendable, Equatable {
    /// The card is not in `review` (e.g. still clarifying or already recorded).
    case notReviewable
    /// Amount is `nil`. The agent never guesses money, so this always blocks.
    case amountRequired
    /// The card has unresolved gaps the user must explicitly acknowledge first.
    case needsAcknowledgment
}

/// Where the held batch is in its lifecycle, distinct from per-card `CardState`
/// (the proven card machine is untouched). A batch only exists while more than one
/// card is held; a lone clean input never leaves `adding` (the A6 fast path).
///
/// `adding` → user is dropping inputs; each recognized → a HELD card with Save paused.
/// `untangling` → "Done adding" tapped; the untangle round-trip is in flight.
/// `reviewing` → the plan arrived (or degraded); the user resolves groups then saves.
enum BatchPhase: String, Sendable, Equatable {
    case adding
    case untangling
    case reviewing
}

/// A proposal the untangle plan makes over the held drafts. Groups are **views**
/// over held cards — no held draft is mutated or destroyed at proposal time — so
/// `split` / `keepBoth` are pure discards of the group and reversibility is
/// structural. A group references its members by `cardID`, never by a copied draft
/// (except the assembled `resolvedDraft` of a fuse, which the user reviews/saves).
enum UntangleGroup: Sendable, Equatable, Identifiable {
    /// Several held cards the model thinks describe ONE bill. `resolvedDraft` is the
    /// assembled card the user would save; `amountTrace == nil` means no member
    /// supplied an amount → the resolved card surfaces "amount required" (never minted).
    case fuseProposed(groupID: UUID, resolvedDraft: BillDraft, sourceCardIDs: [UUID],
                      amountTrace: APIAmountTrace?, reason: String, confidence: Double)
    /// Several held cards that are the SAME bill. `survivorID` is kept on Save; the
    /// rest are set aside (never persisted — no delete).
    case flaggedDuplicate(groupID: UUID, memberCardIDs: [UUID], survivorID: UUID,
                          tier: String, reason: String)

    var id: UUID {
        switch self {
        case .fuseProposed(let gid, _, _, _, _, _): return gid
        case .flaggedDuplicate(let gid, _, _, _, _): return gid
        }
    }

    /// The held cards this group is a view over (so the coordinator can tell which
    /// held cards a group "owns" — those are not rendered as plain review rows).
    var memberCardIDs: [UUID] {
        switch self {
        case .fuseProposed(_, _, let ids, _, _, _): return ids
        case .flaggedDuplicate(_, let ids, _, _, _): return ids
        }
    }
}

/// The pure state machine behind the recording agent.
///
/// `RecordingSession` is a value type with mutating transitions, which makes it
/// fully unit-testable without a UI, network, or database. The app wraps an
/// instance in a `@MainActor` observable coordinator that owns the single
/// `ModelContext` writer and performs the returned `SessionEffect`s; this keeps
/// the "Confirm is the only write" and "single writer" rules structural rather
/// than aspirational.
///
/// Budgets are enforced here: clarification rounds per card, questions per turn,
/// and LLM calls per session.
struct RecordingSession: Sendable {
    private(set) var cards: [AgentCard] = []

    // MARK: - Held batch (Slice ②)

    /// The held-batch phase. `adding` until the user taps "Done adding".
    private(set) var batchPhase: BatchPhase = .adding
    /// The untangle plan as VIEWS over held cards. Empty until `applyUntangle`.
    /// Resolution fns (`combine/split/keepOne/keepBoth`) only ever *remove* a group
    /// here — they never mutate a held draft — so a resolved group returns to plain
    /// review cards and reversibility is structural.
    private(set) var groups: [UntangleGroup] = []

    /// Whether a held batch is in flight, i.e. per-card Save must be paused. True
    /// once the user commits to the batch by tapping "Done adding".
    var hasActiveBatch: Bool { batchPhase != .adding }

    let validator: BillValidator
    let maxClarifyRounds: Int
    let maxQuestionsPerTurn: Int
    let llmCallBudget: Int
    private(set) var llmCallsUsed: Int = 0

    init(
        validator: BillValidator,
        maxClarifyRounds: Int = 2,
        maxQuestionsPerTurn: Int = 2,
        llmCallBudget: Int = 8
    ) {
        self.validator = validator
        self.maxClarifyRounds = maxClarifyRounds
        self.maxQuestionsPerTurn = maxQuestionsPerTurn
        self.llmCallBudget = llmCallBudget
    }

    // MARK: - Budget

    /// Remaining extraction calls this session is allowed to make.
    var remainingLLMCalls: Int { max(0, llmCallBudget - llmCallsUsed) }

    // MARK: - Card lifecycle

    /// Register a new input as a card in `intake`. Returns its id.
    mutating func enqueue(source: DraftSource) -> UUID {
        let id = UUID()
        cards.append(
            AgentCard(
                id: id,
                draft: BillDraft(id: id, currencyCode: validator.journalCurrencyCode, source: source),
                state: .intake,
                clarifyRounds: 0,
                openQuestions: [],
                carriedGaps: []
            )
        )
        return id
    }

    /// Claim one LLM call for extraction (or retry). Returns `false` — without
    /// changing state — when the session's call budget is exhausted.
    mutating func beginExtraction(cardID: UUID) -> Bool {
        guard remainingLLMCalls > 0, let i = index(cardID) else { return false }
        llmCallsUsed += 1
        cards[i].state = .extracting
        return true
    }

    /// Attach a successful extraction's draft and run validation, moving the card
    /// to `clarifying` (with questions) or `review`.
    mutating func completeExtraction(cardID: UUID, draft: BillDraft) -> [SessionEffect] {
        guard let i = index(cardID) else { return [] }
        // Preserve the card's identity on the draft regardless of the source's id
        // (BillDraft.id is `let`, so re-create it rather than mutate).
        let attached = BillDraft(
            id: cardID,
            merchant: draft.merchant,
            amount: draft.amount,
            currencyCode: draft.currencyCode,
            date: draft.date,
            rawDateText: draft.rawDateText,
            categoryRaw: draft.categoryRaw,
            lineItems: draft.lineItems,
            source: draft.source,
            pinnedFields: draft.pinnedFields,
            acknowledgedGaps: draft.acknowledgedGaps
        )
        cards[i].draft = attached
        cards[i].state = .validating
        return resolve(cardID: cardID)
    }

    /// Record an extraction failure as a first-class, retryable state.
    mutating func failExtraction(cardID: UUID) -> SessionEffect {
        if let i = index(cardID) { cards[i].state = .failed }
        return .extractionFailed(cardID: cardID)
    }

    /// Claim a call to retry a failed extraction. `false` if over budget.
    mutating func retryExtraction(cardID: UUID) -> Bool {
        guard remainingLLMCalls > 0, let i = index(cardID), cards[i].state == .failed
        else { return false }
        llmCallsUsed += 1
        cards[i].state = .extracting
        return true
    }

    // MARK: - Clarification

    /// Apply a chip answer to an open question. Pins the field so re-validation
    /// won't re-ask it, then re-resolves the card once all open questions are done.
    mutating func answer(cardID: UUID, field: BillField, value: ClarificationValue) -> [SessionEffect] {
        guard let i = index(cardID), cards[i].state == .clarifying else { return [] }
        apply(value: value, to: &cards[i].draft)
        cards[i].draft.pinnedFields.insert(field)
        cards[i].openQuestions.removeAll { $0.field == field }
        guard cards[i].openQuestions.isEmpty else { return [] }
        return resolve(cardID: cardID)
    }

    /// Directly edit a gap-relevant field (amount/date/category/currency) from the
    /// card UI — same machinery as `answer` (apply + pin + re-resolve) but not tied
    /// to an open clarify question. Clears the field from any carried/acknowledged
    /// gap so re-validation can settle the card. This is what makes a blocked card
    /// recoverable by editing rather than only by chip.
    mutating func edit(cardID: UUID, field: BillField, value: ClarificationValue) -> [SessionEffect] {
        guard let i = index(cardID) else { return [] }
        apply(value: value, to: &cards[i].draft)
        cards[i].draft.pinnedFields.insert(field)
        cards[i].draft.acknowledgedGaps.remove(field)
        cards[i].carriedGaps.removeAll { $0 == field }
        return resolve(cardID: cardID)
    }

    /// Set the draft's merchant directly. Merchant is never a validator gap, so it
    /// needs no `ClarificationValue` case, no pin, and no re-validate — this is the
    /// dedicated path that backs the merchant edit drawer.
    mutating func setMerchant(cardID: UUID, _ merchant: String?) {
        guard let i = index(cardID) else { return }
        let trimmed = merchant?.trimmingCharacters(in: .whitespacesAndNewlines)
        cards[i].draft.merchant = (trimmed?.isEmpty == false) ? trimmed : nil
    }

    /// Skip the open round: carry remaining gaps to `review` (acknowledgment
    /// required at confirm). Nothing is backfilled — unresolved fields stay
    /// genuinely unresolved, honoring "never guess".
    mutating func skipClarification(cardID: UUID) -> [SessionEffect] {
        guard let i = index(cardID), cards[i].state == .clarifying else { return [] }
        let fields = cards[i].openQuestions.map(\.field)
        for f in fields { cards[i].draft.acknowledgedGaps.insert(f) }
        cards[i].carriedGaps = mergeCarried(cards[i].carriedGaps, fields)
        cards[i].openQuestions = []
        cards[i].state = .review
        return [.readyForReview(cardID: cardID)]
    }

    // MARK: - Held batch transitions (Slice ②)

    /// `adding → untangling`. Commits the held cards to a batch so per-card Save is
    /// paused while the untangle round-trip runs. Idempotent: re-tapping while
    /// already untangling/reviewing is a no-op (re-runnable per the v1 contract).
    mutating func markDoneAdding() {
        guard batchPhase == .adding else { return }
        batchPhase = .untangling
    }

    /// `untangling → reviewing`. Builds `groups` from the untangle plan as views over
    /// the live held cards, validating the partition: any plan group that references
    /// a card no longer present is **dropped**, and any live held card not accounted
    /// for by a surviving group **fails open** to a plain review card (never dropped).
    /// No held draft is mutated here — groups are pure views.
    mutating func applyUntangle(_ response: APIUntangleResponse) {
        // A declined plan degrades to plain review (per-card Save still works).
        guard !response.declined else {
            groups = []
            batchPhase = .reviewing
            return
        }
        // Live cards eligible to be grouped/reviewed (anything not terminal).
        let liveIDs = Set(activeCardIDs)
        var built: [UntangleGroup] = []
        var accounted = Set<UUID>()

        for fg in response.fuseGroups {
            // Keep only members still live and not already claimed by an earlier group.
            let members = fg.sourceCardIDs.filter { liveIDs.contains($0) && !accounted.contains($0) }
            // A fuse needs ≥2 source members to mean anything. If filtering left it with
            // 0 or 1, DROP the whole group and let the surviving live member fail open to
            // a plain review card (never a one-member fuse).
            guard members.count >= 2 else { continue }
            let resolved = BillDraft(serverDraft: fg.resolvedDraft,
                                     fallbackCurrency: validator.journalCurrencyCode)
            built.append(.fuseProposed(groupID: fg.groupID, resolvedDraft: resolved,
                                       sourceCardIDs: members, amountTrace: fg.amountTrace,
                                       reason: fg.reason, confidence: fg.confidence))
            accounted.formUnion(members)
        }
        for dg in response.duplicateGroups {
            let members = dg.memberCardIDs.filter { liveIDs.contains($0) && !accounted.contains($0) }
            // A dup group needs ≥2 members and a live survivor to mean anything.
            guard members.count >= 2, members.contains(dg.survivorCardID) else { continue }
            built.append(.flaggedDuplicate(groupID: dg.groupID, memberCardIDs: members,
                                           survivorID: dg.survivorCardID, tier: dg.tier, reason: dg.reason))
            accounted.formUnion(members)
        }
        // cleanCardIDs + any unaccounted live card → plain review (fail-open). We
        // don't store them anywhere special: a held card not owned by a group simply
        // renders as a plain review row (see `plainReviewCardIDs`).
        groups = built
        batchPhase = .reviewing
    }

    /// Degrade straight to `reviewing` with no groups — the held cards become plain
    /// review rows and per-card Save still works. Used when untangle errors/times out.
    mutating func degradeToReview() {
        groups = []
        batchPhase = .reviewing
    }

    /// Return the session to a fresh, empty `adding` state after a batch was **fully
    /// saved**. Drops every now-`recorded` card from the live list (their `BillRecord`s
    /// are already persisted by the host, so the session no longer needs them — keeping
    /// them would leave the Record tab showing a blank "Save all · 0 bills" screen), and
    /// clears the resolved groups. Only the coordinator calls this, and only when
    /// `confirmAll` reported no blocked rows and no non-terminal cards remain — so a
    /// partial save (any clarifying/grouped/failed card still pending) never resets.
    ///
    /// `discarded` (set-aside) cards are dropped too: they are terminal, never persisted,
    /// and a fresh `adding` session must start with nothing lingering. Any non-terminal
    /// card is preserved as a guard — this method is a no-op-on-content when work remains.
    mutating func resetAfterFullSave() {
        cards.removeAll { $0.state.isTerminal }
        groups = []
        batchPhase = .adding
    }

    /// Held card ids the untangle plan did NOT claim — they render as plain review
    /// rows. This is the fail-open surface: a card that actually reached `.review`
    /// and is unaccounted for by any group lands here. Only `.review` cards qualify
    /// (consistent with the untangle-input filter): a card still in flight
    /// (`intake`/`extracting`/`validating`/`clarifying`) or `failed`/terminal is NOT
    /// a review row — it never participates in the batch review surface.
    var plainReviewCardIDs: [UUID] {
        let claimed = Set(groups.flatMap { $0.memberCardIDs })
        return cards.filter { $0.state == .review && !claimed.contains($0.id) }.map(\.id)
    }

    /// The cards the review surface must RENDER (distinct from the savable
    /// `plainReviewCardIDs`). A held card that hit any validation gap is parked in
    /// `.clarifying` (or is still `.validating`/`.extracting`/`.intake`, or
    /// `.failed`), so it is NOT in `plainReviewCardIDs` — yet the user still needs to
    /// SEE it and finish it. This surface is every non-terminal held card no group
    /// claims: `.intake`/`.extracting`/`.validating`/`.clarifying`/`.review`/`.failed`.
    /// Each renders its own state via `AgentCardView` (clarify chips, thinking, ready,
    /// retry); resolving a card mutates it into `.review`, which makes it savable.
    /// Over-narrowing this to `.review` only is exactly what made finished-but-
    /// unresolved batches vanish into a blank "0 bills" review screen.
    var reviewSurfaceCardIDs: [UUID] {
        let claimed = Set(groups.flatMap { $0.memberCardIDs })
        return cards.filter { !$0.state.isTerminal && !claimed.contains($0.id) }.map(\.id)
    }

    /// Resolve a fuse group by ACCEPTING it. Injects the resolved draft as ONE new
    /// held card (run through the same validator gate as any card), sets aside the
    /// member cards it subsumes, and drops the group. The new card then saves as a
    /// single bill via the unchanged confirm path. `amountTrace == nil` ⇒ the server
    /// omitted the amount ⇒ the card surfaces "amount required" and `confirm` blocks
    /// — code never invents money. Returns the new card's id (nil if not a fuse).
    @discardableResult
    mutating func combine(groupID: UUID) -> UUID? {
        guard let i = groups.firstIndex(where: { $0.id == groupID }),
              case .fuseProposed(_, let resolved, let members, _, _, _) = groups[i] else { return nil }
        let newID = UUID()
        cards.append(
            AgentCard(id: newID,
                      draft: BillDraft(
                          id: newID,
                          merchant: resolved.merchant,
                          amount: resolved.amount,
                          currencyCode: resolved.currencyCode,
                          date: resolved.date,
                          rawDateText: resolved.rawDateText,
                          categoryRaw: resolved.categoryRaw,
                          lineItems: resolved.lineItems,
                          source: resolved.source),
                      state: .validating,
                      clarifyRounds: 0,
                      openQuestions: [],
                      carriedGaps: [])
        )
        _ = resolve(cardID: newID)            // gate via validator → review (or amount-required)
        for m in members { setAside(cardID: m) }   // members subsumed; never saved
        groups.remove(at: i)
        return newID
    }

    /// Resolve a fuse group by SPLITTING it — pure discard of the group. The held
    /// member drafts were never mutated, so they restore byte-identical as plain
    /// review cards. This is what makes a wrong fuse one-tap reversible.
    mutating func split(groupID: UUID) {
        groups.removeAll { $0.id == groupID }
    }

    /// Resolve a duplicate group by KEEPING ONE — set aside every member except the
    /// chosen survivor (or the group's own survivor if the choice isn't a member),
    /// then drop the group so the survivor saves as a plain review card.
    mutating func keepOne(groupID: UUID, survivor: UUID) {
        guard let i = groups.firstIndex(where: { $0.id == groupID }),
              case .flaggedDuplicate(_, let members, let groupSurvivor, _, _) = groups[i] else { return }
        let keep = members.contains(survivor) ? survivor : groupSurvivor
        for m in members where m != keep { setAside(cardID: m) }
        groups.remove(at: i)
    }

    /// Resolve a duplicate group by KEEPING BOTH — pure discard of the group. No
    /// member is set aside, so every member restores as its own plain review card
    /// (the "these are genuinely distinct" escape hatch).
    mutating func keepBoth(groupID: UUID) {
        groups.removeAll { $0.id == groupID }
    }

    /// Card ids the session still acts on for the batch (not recorded/discarded).
    var activeCardIDs: [UUID] { cards.filter { !$0.state.isTerminal }.map(\.id) }

    /// Set a card aside: a duplicate the user chose not to keep. Modeled as
    /// `discarded` so it's never persisted and disappears from the review surface —
    /// there is no delete; it simply isn't saved.
    private mutating func setAside(cardID: UUID) {
        if let i = index(cardID) { cards[i].state = .discarded }
    }

    // MARK: - Confirmation (single writer)

    /// Confirm a card. The only path to `.persist`. Refuses if the card is not in
    /// review, has no amount, or has unacknowledged carried gaps.
    mutating func confirm(cardID: UUID, acknowledging: Bool = false) throws -> SessionEffect {
        guard let i = index(cardID) else { throw ConfirmError.notReviewable }
        guard cards[i].state.isConfirmable else { throw ConfirmError.notReviewable }
        guard cards[i].draft.amount != nil else { throw ConfirmError.amountRequired }
        if !cards[i].carriedGaps.isEmpty && !acknowledging { throw ConfirmError.needsAcknowledgment }
        cards[i].state = .recorded
        return .persist(cardID: cardID)
    }

    /// Drop a card without persisting it.
    mutating func discard(cardID: UUID) {
        if let i = index(cardID) { cards[i].state = .discarded }
    }

    // MARK: - Accessors

    func card(_ id: UUID) -> AgentCard? { cards.first { $0.id == id } }

    /// Cards that reached `recorded` — the session's contribution to the books.
    var recordedCards: [AgentCard] { cards.filter { $0.state == .recorded } }

    // MARK: - Internals

    private func index(_ id: UUID) -> Int? { cards.firstIndex { $0.id == id } }

    /// Decide a card's next state from current validation gaps, honoring the
    /// clarify-round budget. Only chip-answerable gaps open a round; the rest are
    /// carried to review for direct editing / acknowledgment.
    private mutating func resolve(cardID: UUID) -> [SessionEffect] {
        guard let i = index(cardID) else { return [] }
        let gaps = validator.validate(cards[i].draft)
        if gaps.isEmpty {
            cards[i].carriedGaps = []
            cards[i].openQuestions = []
            cards[i].state = .review
            return [.readyForReview(cardID: cardID)]
        }

        let askable = gaps.filter { !$0.question.options.isEmpty }
        let budgetLeft = cards[i].clarifyRounds < maxClarifyRounds

        guard budgetLeft, !askable.isEmpty else {
            // No rounds left, or nothing is chip-answerable: carry every gap to
            // review. The user resolves by editing or acknowledges and saves.
            // Merge (don't overwrite) so gaps carried in an earlier pass survive.
            cards[i].carriedGaps = mergeCarried(cards[i].carriedGaps, gaps.map(\.field))
            for f in cards[i].carriedGaps { cards[i].draft.acknowledgedGaps.insert(f) }
            cards[i].openQuestions = []
            cards[i].state = .review
            return [.readyForReview(cardID: cardID)]
        }

        cards[i].clarifyRounds += 1
        let asked = Array(askable.prefix(maxQuestionsPerTurn))
        cards[i].openQuestions = asked.map(\.question)
        cards[i].state = .clarifying
        return [.askQuestions(asked.map(\.question), cardID: cardID, round: cards[i].clarifyRounds)]
    }

    private func apply(value: ClarificationValue, to draft: inout BillDraft) {
        switch value {
        case .amount(let a): draft.amount = a
        case .date(let d): draft.date = d; draft.rawDateText = nil
        case .category(let c): draft.categoryRaw = c
        case .currency(let c): draft.currencyCode = c
        }
    }

    private func mergeCarried(_ existing: [BillField], _ new: [BillField]) -> [BillField] {
        var out = existing
        for f in new where !out.contains(f) { out.append(f) }
        return out
    }
}
