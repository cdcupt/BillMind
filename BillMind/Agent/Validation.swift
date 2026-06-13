import Foundation

/// A concrete value a clarification answer can carry back into a draft.
enum ClarificationValue: Sendable, Equatable {
    case amount(Decimal)
    case date(Date)
    case category(String)
    case currency(String)
}

/// One selectable answer for a clarifying question (rendered as a chip).
struct ClarificationOption: Sendable, Equatable {
    let label: String
    let value: ClarificationValue

    init(label: String, value: ClarificationValue) {
        self.label = label
        self.value = value
    }
}

/// A question the agent asks to resolve a validation gap. Always chip-answerable —
/// answering patches the draft field directly, with no second AI call.
struct ClarificationQuestion: Sendable, Equatable {
    let field: BillField
    let prompt: String
    let options: [ClarificationOption]

    init(field: BillField, prompt: String, options: [ClarificationOption]) {
        self.field = field
        self.prompt = prompt
        self.options = options
    }
}

/// A problem the validator found, paired with the question that resolves it.
struct ValidationGap: Sendable, Equatable {
    let field: BillField
    let reason: String
    let question: ClarificationQuestion
}

/// Deterministic, AI-free validation of a draft.
///
/// This is the gate between extraction and the user: it reconciles the math,
/// the date, the currency, and the category using plain rules — never model
/// confidence — and emits the gaps that drive clarification. Because answering
/// a gap *pins* the field, re-running `validate` after an answer cannot re-raise
/// the same gap, which is what bounds the clarify loop.
struct BillValidator: Sendable {
    /// Smallest difference treated as a real amount mismatch (currency-agnostic).
    /// Exact in base-10 Decimal; avoids a force-unwrapped string initializer.
    static let amountTolerance: Decimal = Decimal(1) / Decimal(100)

    /// Known category raw values (lowercased), e.g. BillCategory.allCases rawValues.
    let knownCategoryRaws: Set<String>
    /// Currency the active journal files in; a differing card currency is flagged.
    let journalCurrencyCode: String
    /// Reference "today" for the missing-date question. Injected for testability.
    let today: Date

    init(knownCategoryRaws: Set<String>, journalCurrencyCode: String, today: Date) {
        self.knownCategoryRaws = knownCategoryRaws
        self.journalCurrencyCode = journalCurrencyCode
        self.today = today
    }

    /// All gaps for a draft, skipping fields the user has pinned or acknowledged.
    func validate(_ draft: BillDraft) -> [ValidationGap] {
        var gaps: [ValidationGap] = []

        if shouldCheck(.amount, in: draft) {
            if let gap = amountGap(for: draft) { gaps.append(gap) }
        }
        if shouldCheck(.date, in: draft) {
            if let gap = dateGap(for: draft) { gaps.append(gap) }
        }
        if shouldCheck(.currency, in: draft) {
            if let gap = currencyGap(for: draft) { gaps.append(gap) }
        }
        if shouldCheck(.category, in: draft) {
            if let gap = categoryGap(for: draft) { gaps.append(gap) }
        }
        return gaps
    }

    /// A draft is recordable only when it has an amount and no *unacknowledged* gaps.
    /// Missing amount is never auto-resolved, so it always blocks confirmation.
    func unresolvedFields(for draft: BillDraft) -> [BillField] {
        validate(draft).map(\.field)
    }

    // MARK: - Per-field rules

    private func shouldCheck(_ field: BillField, in draft: BillDraft) -> Bool {
        !draft.pinnedFields.contains(field) && !draft.acknowledgedGaps.contains(field)
    }

    private func amountGap(for draft: BillDraft) -> ValidationGap? {
        // Rule 1: a printed total that disagrees with the line-item sum.
        if let amount = draft.amount, let sum = draft.lineItemTotal,
           abs(amount - sum) > Self.amountTolerance {
            let q = ClarificationQuestion(
                field: .amount,
                prompt: "The printed total reads \(amount) but the line items add up to \(sum). Which is the real total?",
                options: [
                    ClarificationOption(label: "\(sum)", value: .amount(sum)),
                    ClarificationOption(label: "\(amount)", value: .amount(amount)),
                ]
            )
            return ValidationGap(field: .amount, reason: "total ≠ Σ line items", question: q)
        }
        // Rule 2: no amount at all. Chip options can only be offered if the host
        // supplied candidates (e.g. an ambiguous spoken amount); otherwise the gap
        // stands with no auto-answer and blocks confirmation.
        if draft.amount == nil {
            let q = ClarificationQuestion(
                field: .amount,
                prompt: "I couldn't read an amount — what was the total?",
                options: []
            )
            return ValidationGap(field: .amount, reason: "amount missing", question: q)
        }
        return nil
    }

    private func dateGap(for draft: BillDraft) -> ValidationGap? {
        guard draft.date == nil else { return nil }
        if let raw = draft.rawDateText {
            let q = ClarificationQuestion(
                field: .date,
                prompt: "The date is hard to read — I see “\(raw)”. When was it?",
                options: []
            )
            return ValidationGap(field: .date, reason: "date unparseable", question: q)
        }
        let q = ClarificationQuestion(
            field: .date,
            prompt: "No date on this one — when was it?",
            options: [ClarificationOption(label: "Today", value: .date(today))]
        )
        return ValidationGap(field: .date, reason: "date missing", question: q)
    }

    private func currencyGap(for draft: BillDraft) -> ValidationGap? {
        guard draft.currencyCode != journalCurrencyCode else { return nil }
        let q = ClarificationQuestion(
            field: .currency,
            prompt: "This card is in \(draft.currencyCode) but the journal is in \(journalCurrencyCode). Keep it in \(draft.currencyCode)?",
            options: [
                ClarificationOption(label: "Keep \(draft.currencyCode)", value: .currency(draft.currencyCode)),
                ClarificationOption(label: "Use \(journalCurrencyCode)", value: .currency(journalCurrencyCode)),
            ]
        )
        return ValidationGap(field: .currency, reason: "currency ≠ journal", question: q)
    }

    private func categoryGap(for draft: BillDraft) -> ValidationGap? {
        guard let raw = draft.categoryRaw,
              !knownCategoryRaws.contains(raw.lowercased()) else { return nil }
        let q = ClarificationQuestion(
            field: .category,
            prompt: "I wasn't sure of the category (“\(raw)”). Which fits best?",
            options: []
        )
        return ValidationGap(field: .category, reason: "category unknown", question: q)
    }
}
