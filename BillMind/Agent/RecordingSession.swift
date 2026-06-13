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
