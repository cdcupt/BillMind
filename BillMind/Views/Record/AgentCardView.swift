import SwiftUI

/// Identifies which card + field the edit drawer is editing.
struct EditTarget: Identifiable, Equatable {
    let cardID: UUID
    let field: BillField
    var id: String { "\(cardID.uuidString)-\(field.rawValue)" }
}

/// One bill card in the Record thread: an editable, issue-style card driven by an
/// `AgentCard`. Tapping any field opens the edit drawer (via `onEditField`);
/// clarify chips answer in place; Save confirms (the only write).
struct AgentCardView: View {
    let card: AgentCard
    let coordinator: RecordCoordinator
    let onEditField: (BillField) -> Void

    @State private var ackArmed = false
    @State private var pulse = false
    @State private var shimmer: CGFloat = -1

    /// One fixed status word per card, picked once at random from the pool when
    /// the card is created (Claude Code style). Different cards may differ, but
    /// within a single card the word never changes — `@State` evaluates the
    /// default once, and each card is a distinct view (`.id(card.id)`).
    @State private var thinkingWord = AgentCardView.thinkingPhrases.randomElement() ?? "Thinking…"

    /// Pool of status words shown while the agent calls the remote model.
    private static let thinkingPhrases = ["Thinking…", "Pondering…", "Reading…", "Recognizing…", "Tallying…", "Crunching…", "Musing…", "Reckoning…", "Mulling…", "Calculating…", "Sorting…", "Working…"]

    private var draft: BillDraft { card.draft }
    private var amountMissing: Bool { draft.amount == nil }

    var body: some View {
        ZStack {
            if card.state == .extracting {
                thinkingView.transition(.opacity)
            } else {
                cardContent.transition(.opacity)
            }
        }
        .sketchCard(cornerRadius: 18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(borderColor, lineWidth: 2)
        )
        .animation(.easeInOut(duration: 0.4), value: card.state)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            mainRow
            if !draft.lineItems.isEmpty { lineItems }
            if card.state == .clarifying { clarify }
            actions
        }
    }

    // MARK: - Thinking state (extraction in progress)

    /// A calm "agent is reading" state: a shimmering skeleton of the card-to-come
    /// with a pulsing sparkle, instead of an empty placeholder card. Cross-fades
    /// into the real card when the AI returns.
    private var thinkingView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: "sparkle")
                    .font(.system(size: 13))
                    .foregroundStyle(SketchTheme.warmOrange)
                    .scaleEffect(pulse ? 1.2 : 0.8)
                    .opacity(pulse ? 1 : 0.5)
                Text(thinkingWord)
                    .font(SketchTheme.captionFont(13))
                    .foregroundStyle(SketchTheme.softBlue)
                    .opacity(pulse ? 1 : 0.6)
                Spacer()
                Text(sourceLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(SketchTheme.lightBrown)
            }
            HStack(spacing: 12) {
                skeleton(RoundedRectangle(cornerRadius: 10), width: 40, height: 40)
                VStack(alignment: .leading, spacing: 7) {
                    skeleton(Capsule(), width: 130, height: 14)
                    HStack(spacing: 6) {
                        skeleton(Capsule(), width: 56, height: 12)
                        skeleton(Capsule(), width: 42, height: 12)
                    }
                }
                Spacer()
                skeleton(Capsule(), width: 58, height: 18)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) { shimmer = 1 }
        }
    }

    /// A skeleton placeholder with a left-to-right shimmer sweep.
    private func skeleton(_ shape: some Shape, width: CGFloat, height: CGFloat) -> some View {
        shape
            .fill(SketchTheme.lightBrown.opacity(0.16))
            .frame(width: width, height: height)
            .overlay(
                shape
                    .fill(LinearGradient(
                        colors: [.clear, SketchTheme.cream.opacity(0.95), .clear],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: width, height: height)
                    .offset(x: shimmer * (width + 50))
            )
            .clipShape(shape)
    }

    // MARK: - Header (status badge)

    private var header: some View {
        HStack {
            Text(badge.text)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .textCase(.uppercase)
                .padding(.horizontal, 9).padding(.vertical, 2)
                .background(badge.color.opacity(0.18))
                .foregroundStyle(badge.color)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Spacer()
            Text(sourceLabel)
                .font(.system(size: 10))
                .foregroundStyle(SketchTheme.lightBrown)
        }
    }

    // MARK: - Main row

    private var mainRow: some View {
        HStack(spacing: 12) {
            Image(systemName: category.sfSymbol)
                .font(.system(size: 18))
                .foregroundStyle(category.color)
                .frame(width: 40, height: 40)
                .background(category.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Button { onEditField(.merchant) } label: {
                    Text(draft.merchant ?? "Tap to name")
                        .font(SketchTheme.headlineFont(16))
                        .foregroundStyle(draft.merchant == nil ? SketchTheme.lightBrown : SketchTheme.softBrown)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("card-merchant")

                HStack(spacing: 6) {
                    Button { onEditField(.category) } label: {
                        Text(category.englishName + " ▾")
                            .font(SketchTheme.captionFont(12))
                            .padding(.horizontal, 9).padding(.vertical, 2)
                            .background(category.color.opacity(0.14))
                            .foregroundStyle(category.color)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("card-category")

                    Text("·").foregroundStyle(SketchTheme.lightBrown)

                    Button { onEditField(.date) } label: {
                        Text(dateLabel)
                            .font(SketchTheme.captionFont(12))
                            .foregroundStyle(draft.date == nil ? SketchTheme.mutedRed : SketchTheme.lightBrown)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("card-date")
                }
            }

            Spacer()

            Button { onEditField(.amount) } label: {
                Text(amountLabel)
                    .font(amountMissing ? SketchTheme.captionFont(13) : SketchTheme.headlineFont(18))
                    .italic(amountMissing)
                    .foregroundStyle(amountMissing ? SketchTheme.mutedRed : category.color)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("card-amount")
        }
    }

    private var lineItems: some View {
        VStack(spacing: 3) {
            Divider().background(SketchTheme.lightBrown.opacity(0.4))
            ForEach(Array(draft.lineItems.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(item.label).font(SketchTheme.captionFont(11)).foregroundStyle(SketchTheme.lightBrown)
                    Spacer()
                    Text("\(coordinator.currencySymbol)\(item.amount.formatted2)").font(SketchTheme.captionFont(11))
                }
            }
        }
    }

    // MARK: - Clarify

    private var clarify: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(card.openQuestions, id: \.field) { question in
                Text(question.prompt)
                    .font(SketchTheme.captionFont(12))
                    .foregroundStyle(SketchTheme.softBrown)
                HStack(spacing: 6) {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { _, option in
                        Button(option.label) {
                            coordinator.answer(cardID: card.id, field: question.field, value: option.value)
                        }
                        .buttonStyle(ChipButtonStyle())
                        .accessibilityIdentifier("clarify-\(option.label)")
                    }
                    if question.field == .date {
                        Button("Pick a date…") { onEditField(.date) }
                            .buttonStyle(ChipButtonStyle())
                            .accessibilityIdentifier("clarify-pick-date")
                    }
                }
            }
            Button("Skip — keep what was read") { coordinator.skip(cardID: card.id) }
                .font(SketchTheme.captionFont(12))
                .foregroundStyle(SketchTheme.lightBrown)
        }
    }

    // MARK: - Actions

    @ViewBuilder private var actions: some View {
        if card.state == .recorded {
            Group {
                if coordinator.savingCardIDs.contains(card.id) {
                    Label("Saving…", systemImage: "arrow.triangle.2.circlepath")
                        .font(SketchTheme.captionFont(13))
                        .foregroundStyle(SketchTheme.softBlue)
                        .accessibilityIdentifier("card-saving")
                } else {
                    Label("In the trip", systemImage: "checkmark.seal.fill")
                        .font(SketchTheme.captionFont(13))
                        .foregroundStyle(SketchTheme.sageGreen)
                }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.4), value: coordinator.savingCardIDs.contains(card.id))
        } else if card.state == .failed {
            HStack(spacing: 8) {
                Button("Retry") { coordinator.retry(cardID: card.id) }
                    .buttonStyle(HandDrawnButtonStyle(filled: true))
                Button("Discard") { coordinator.discard(cardID: card.id) }
                    .buttonStyle(HandDrawnButtonStyle(filled: false))
            }
        } else {
            HStack(spacing: 8) {
                Button(saveLabel) { save() }
                    .buttonStyle(HandDrawnButtonStyle(filled: true))
                    .disabled(card.state != .review)
                    .accessibilityIdentifier("card-save")
                Button("Discard") { coordinator.discard(cardID: card.id) }
                    .buttonStyle(HandDrawnButtonStyle(filled: false))
                    .accessibilityIdentifier("card-discard")
            }
        }
    }

    private var saveLabel: String {
        if amountMissing { return "Enter amount to save" }
        if !card.carriedGaps.isEmpty { return ackArmed ? "Save anyway" : "Save with gaps" }
        return "Save to trip"
    }

    private func save() {
        switch coordinator.confirm(cardID: card.id, acknowledging: ackArmed) {
        case .amountRequired: onEditField(.amount)
        case .needsAcknowledgment: ackArmed = true
        case .recorded, .notReviewable: ackArmed = false
        }
    }

    // MARK: - Derived

    private var category: BillCategory { BillCategory(rawValue: draft.categoryRaw ?? "") ?? .misc }
    private var amountLabel: String {
        amountMissing ? "amount required" : "\(coordinator.currencySymbol)\(draft.amount!.formatted2)"
    }
    private var dateLabel: String {
        guard let date = draft.date else { return draft.rawDateText.map { "“\($0)”" } ?? "add a date" }
        return date.relativeLabel
    }
    private var sourceLabel: String {
        switch draft.source { case .text: "from text"; case .photo: "from photo"; case .voice: "from voice"; case .manual: "manual" }
    }
    private var borderColor: Color {
        switch card.state {
        case .clarifying, .failed: SketchTheme.mutedRed.opacity(0.6)
        case .recorded: SketchTheme.sageGreen.opacity(0.6)
        default: SketchTheme.lightBrown.opacity(0.4)
        }
    }
    private var badge: (text: String, color: Color) {
        switch card.state {
        case .intake, .extracting, .validating: ("reading…", SketchTheme.softBlue)
        case .clarifying: ("needs info", SketchTheme.mutedRed)
        case .review: amountMissing ? ("needs info", SketchTheme.mutedRed) : ("ready", SketchTheme.sageGreen)
        case .recorded: coordinator.savingCardIDs.contains(card.id)
            ? ("saving…", SketchTheme.softBlue) : ("saved", SketchTheme.sageGreen)
        case .failed: ("extract failed", SketchTheme.mutedRed)
        case .discarded: ("discarded", SketchTheme.lightBrown)
        }
    }
}

// MARK: - Untangle review group rows
//
// Two sibling views to `AgentCardView` that render the held-batch untangle plan
// (slice ②) inside the same Record scroll: a fuse proposal (partials that are one
// bill) and a flagged duplicate group (the same bill twice). Both match the
// SketchTheme dedup grammar from design/dedup/DESIGN.html: a calm sand-caution
// dashed bracket (never gate-red), a first-person Ollie bar, and only reversible
// actions — nothing reads as auto-deleted. The non-destructive accept (Combine /
// Keep both) is the prominent filled-pine button; the escape (Split / Keep one)
// is the quiet outline.

/// A held-batch fuse proposal: one resolved card Ollie assembled from several
/// inputs, shown over a "made from" provenance strip so the money trace is
/// literal — the amount is tagged with the input it came from, never minted.
/// Combine accepts (→ one review card via the validator); Split discards the
/// proposal and the originals return intact. `amountTrace == nil` ⇒ the card
/// shows the red "amount required" gap exactly as a lone card does (A7).
struct FuseProposalView: View {
    let groupID: UUID
    let resolved: BillDraft
    let sourceCards: [AgentCard]
    let amountTrace: APIAmountTrace?
    let reason: String
    let coordinator: RecordCoordinator

    private var category: BillCategory { BillCategory(rawValue: resolved.categoryRaw ?? "") ?? .misc }
    private var amountMissing: Bool { resolved.amount == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ollieBar
            DashedBracket(label: "⌥ COMBINED INTO ONE", tint: SketchTheme.warmOrange) {
                VStack(alignment: .leading, spacing: 12) {
                    resolvedRow
                    Divider().background(SketchTheme.lightBrown.opacity(0.3))
                    provenance
                }
            }
            actions
        }
        .sketchCard(cornerRadius: 18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(SketchTheme.warmOrange.opacity(0.55), lineWidth: 2))
    }

    private var ollieBar: some View {
        OllieNoteBar(text: amountMissing
            ? "I joined these, but neither had a total. What was the amount?"
            : "I combined these — looks like one bill.")
    }

    /// The resolved bill at a glance: icon · merchant · category·date · amount.
    /// Amount italic-red when missing, mirroring `AgentCardView`'s gap treatment.
    private var resolvedRow: some View {
        HStack(spacing: 12) {
            Image(systemName: category.sfSymbol)
                .font(.system(size: 18)).foregroundStyle(category.color)
                .frame(width: 40, height: 40)
                .background(category.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(resolved.merchant ?? "Combined bill")
                    .font(SketchTheme.headlineFont(16)).foregroundStyle(SketchTheme.softBrown)
                Text("\(category.englishName) · \(dateLabel)")
                    .font(SketchTheme.captionFont(12)).foregroundStyle(SketchTheme.lightBrown)
            }
            Spacer()
            Text(amountLabel)
                .font(amountMissing ? SketchTheme.captionFont(13) : SketchTheme.amountFont(18))
                .italic(amountMissing)
                .foregroundStyle(amountMissing ? SketchTheme.mutedRed : category.color)
                .accessibilityIdentifier("fuse-amount")
        }
    }

    /// The "made from" strip: one slip per source input (photo thumb / note text),
    /// and — when the amount is known — its trace ("¥240 from your note").
    private var provenance: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("made from")
                .font(.system(size: 10, weight: .bold, design: .rounded)).textCase(.uppercase)
                .foregroundStyle(SketchTheme.lightBrown)
            ForEach(sourceCards) { card in
                ProvenanceSlip(card: card, isAmountSource: card.id == amountTrace?.sourceCardID)
            }
            if let trace = amountTraceLabel {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.turn.down.right").font(.system(size: 10))
                    Text(trace).font(SketchTheme.captionFont(11))
                }
                .foregroundStyle(SketchTheme.sageGreen)
                .accessibilityIdentifier("fuse-amount-trace")
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                coordinator.combine(groupID: groupID)
            } label: { Label("Combine", systemImage: "checkmark") }
                .buttonStyle(HandDrawnButtonStyle(filled: true))
                .accessibilityIdentifier("fuse-combine")
            Button("Split") { coordinator.split(groupID: groupID) }
                .buttonStyle(HandDrawnButtonStyle(filled: false))
                .accessibilityIdentifier("fuse-split")
            Spacer(minLength: 0)
        }
    }

    private var dateLabel: String { resolved.date?.relativeLabel ?? "no date" }
    private var amountLabel: String {
        amountMissing ? "amount required" : "\(coordinator.currencySymbol)\(resolved.amount!.formatted2)"
    }
    /// "¥240 from your note" / "¥240 read from the receipt" — Ollie's money-trace copy.
    private var amountTraceLabel: String? {
        guard let trace = amountTrace, let amount = resolved.amount,
              let source = sourceCards.first(where: { $0.id == trace.sourceCardID }) else { return nil }
        let money = "\(coordinator.currencySymbol)\(amount.formatted2)"
        return source.draft.source == .photo
            ? "\(money) read from the receipt"
            : "\(money) from your note"
    }
}

/// One source slip inside a fuse's "made from" strip — a small photo or note
/// chip, tagged with whether it supplied the amount.
private struct ProvenanceSlip: View {
    let card: AgentCard
    let isAmountSource: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12)).foregroundStyle(SketchTheme.softBrown)
                .frame(width: 26, height: 26)
                .background(SketchTheme.cream)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(SketchTheme.lightBrown.opacity(0.4), lineWidth: 1))
            Text(label).font(SketchTheme.captionFont(12)).foregroundStyle(SketchTheme.softBrown)
                .lineLimit(1)
            Spacer(minLength: 0)
            if isAmountSource {
                Text("amount").font(.system(size: 9, weight: .bold, design: .rounded)).textCase(.uppercase)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(SketchTheme.sageGreen.opacity(0.16))
                    .foregroundStyle(SketchTheme.sageGreen)
                    .clipShape(Capsule())
            }
        }
    }

    private var icon: String { card.draft.source == .photo ? "photo" : "pencil.line" }
    private var label: String {
        switch card.draft.source {
        case .photo: return card.draft.merchant.map { "Receipt · \($0)" } ?? "Receipt photo"
        case .text, .voice: return card.draft.merchant ?? "Your note"
        case .manual: return card.draft.merchant ?? "Manual entry"
        }
    }
}

/// A flagged duplicate group: several held cards Ollie thinks are the same bill,
/// tethered under one calm bracket. The survivor is pre-ringed pine; the others
/// are dimmed "set aside" (grey, never red). Keep both is the safe filled accept;
/// Keep one sets the dimmed members aside (reversible until Save).
struct DuplicateGroupView: View {
    let groupID: UUID
    let members: [AgentCard]
    let survivorID: UUID
    let tier: String
    let reason: String
    let coordinator: RecordCoordinator

    @State private var chosenSurvivor: UUID?

    private var survivor: UUID { chosenSurvivor ?? survivorID }
    /// Firm copy on an exact same-photo match; softer on a same-details match.
    private var isFirm: Bool { tier == "samePhoto" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OllieNoteBar(text: isFirm
                ? "This looks like the same photo twice. Keep one, or keep both?"
                : "These two might be the same bill. Keep both if they’re separate.")
            DashedBracket(label: isFirm ? "≈ SAME PHOTO" : "≈ SAME BILL TWICE",
                          tint: SketchTheme.warmOrange) {
                VStack(spacing: 10) {
                    ForEach(members) { member in
                        DuplicateMemberRow(
                            card: member,
                            isSurvivor: member.id == survivor,
                            currencySymbol: coordinator.currencySymbol
                        ) { chosenSurvivor = member.id }
                    }
                }
            }
            actions
        }
        .sketchCard(cornerRadius: 18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(SketchTheme.warmOrange.opacity(0.55), lineWidth: 2))
    }

    private var actions: some View {
        HStack(spacing: 8) {
            // Keep both is the safe, prominent one-tap (nothing reads as deleted).
            Button(members.count > 2 ? "Keep all" : "Keep both") {
                coordinator.keepBoth(groupID: groupID)
            }
            .buttonStyle(HandDrawnButtonStyle(filled: true))
            .accessibilityIdentifier("dup-keep-both")
            Button("Keep one") { coordinator.keepOne(groupID: groupID, survivor: survivor) }
                .buttonStyle(HandDrawnButtonStyle(filled: false))
                .accessibilityIdentifier("dup-keep-one")
            Spacer(minLength: 0)
        }
    }
}

/// One member inside a duplicate bracket. Survivor: pine ring + "keep this one".
/// Non-survivor: dimmed grey "set aside if kept 1" (never destructive-red), tap
/// to make it the survivor instead.
private struct DuplicateMemberRow: View {
    let card: AgentCard
    let isSurvivor: Bool
    let currencySymbol: String
    let onChoose: () -> Void

    private var draft: BillDraft { card.draft }
    private var category: BillCategory { BillCategory(rawValue: draft.categoryRaw ?? "") ?? .misc }

    var body: some View {
        Button(action: onChoose) {
            HStack(spacing: 12) {
                Image(systemName: category.sfSymbol)
                    .font(.system(size: 16)).foregroundStyle(category.color)
                    .frame(width: 36, height: 36)
                    .background(category.color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(draft.merchant ?? "Bill")
                            .font(SketchTheme.headlineFont(15)).foregroundStyle(SketchTheme.softBrown)
                        statusTag
                    }
                    Text("\(category.englishName) · \(sourceLabel)")
                        .font(SketchTheme.captionFont(11)).foregroundStyle(SketchTheme.lightBrown)
                }
                Spacer()
                Text(draft.amount.map { "\(currencySymbol)\($0.formatted2)" } ?? "—")
                    .font(SketchTheme.amountFont(16))
                    .foregroundStyle(isSurvivor ? category.color : SketchTheme.lightBrown)
            }
            .padding(10)
            .background((isSurvivor ? SketchTheme.warmWhite : SketchTheme.cream).opacity(isSurvivor ? 1 : 0.7))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(isSurvivor ? SketchTheme.sageGreen : SketchTheme.lightBrown.opacity(0.3),
                        lineWidth: isSurvivor ? 2 : 1))
            .opacity(isSurvivor ? 1 : 0.6)   // dimmed "set aside" preview — never red
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(isSurvivor ? "dup-survivor" : "dup-member")
    }

    @ViewBuilder private var statusTag: some View {
        if isSurvivor {
            tag("✓ keep this one", color: SketchTheme.sageGreen)
        } else {
            tag("set aside if kept 1", color: SketchTheme.lightBrown)
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 9, weight: .bold, design: .rounded)).textCase(.uppercase)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.16)).foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var sourceLabel: String {
        switch draft.source { case .text: "typed"; case .photo: "photo"; case .voice: "voice"; case .manual: "manual" }
    }
}

// MARK: - Shared sketch chrome (bracket + Ollie bar)

/// The calm sand-caution dashed bracket the dedup design tethers groups with —
/// a labelled tab over a dashed-outlined content well. Never gate-red: this is
/// "Ollie noticed," not "danger."
struct DashedBracket<Content: View>: View {
    let label: String
    let tint: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded)).textCase(.uppercase)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(tint.opacity(0.18)).foregroundStyle(SketchTheme.softBrown)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            content()
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .stroke(tint.opacity(0.55), style: StrokeStyle(lineWidth: 1.6, dash: [5, 4])))
        }
    }
}

/// A small first-person Ollie line with the owl mascot — the warm "I noticed /
/// I tidied these" voice, reused across fuse and dup groups.
struct OllieNoteBar: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(AnimalType.owl.imageName)
                .resizable().scaledToFill().frame(width: 26, height: 26).clipShape(Circle())
            Text(text).font(SketchTheme.bodyFont(13)).foregroundStyle(SketchTheme.softBrown)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Edit drawer

/// Bottom sheet for editing one field: date / category → pure selection;
/// amount → number pad; merchant → text + recent chips. Presented once from the
/// thread container via `.sheet(item:)`; commits only on Set / a selection.
struct EditDrawerView: View {
    let target: EditTarget
    let coordinator: RecordCoordinator
    let dismiss: () -> Void

    @State private var amountText = ""
    @State private var merchantText = ""
    @State private var pickedDate = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule().fill(SketchTheme.lightBrown.opacity(0.5)).frame(width: 40, height: 4).frame(maxWidth: .infinity)
            switch target.field {
            case .amount: amountEditor
            case .merchant: merchantEditor
            case .date: dateEditor
            case .category: categoryEditor
            case .currency: EmptyView()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperBackground()
        .presentationDetents([.medium])
    }

    private var amountEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Enter amount").font(SketchTheme.headlineFont(20)).foregroundStyle(SketchTheme.softBrown)
            HStack {
                Text(coordinator.currencySymbol).font(SketchTheme.amountFont(28)).foregroundStyle(SketchTheme.lightBrown)
                TextField("0.00", text: $amountText)
                    .font(SketchTheme.amountFont(36)).keyboardType(.decimalPad)
                    .accessibilityIdentifier("drawer-amount-field")
            }
            Button("Set amount") {
                if let value = Decimal(string: amountText), value > 0 {
                    coordinator.edit(cardID: target.cardID, field: .amount, value: .amount(value))
                    dismiss()
                }
            }
            .buttonStyle(HandDrawnButtonStyle(filled: true))
            .accessibilityIdentifier("drawer-set")
        }
    }

    private var merchantEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Merchant").font(SketchTheme.headlineFont(20)).foregroundStyle(SketchTheme.softBrown)
            TextField("Store or company name", text: $merchantText)
                .textFieldStyle(.plain).padding(12)
                .background(SketchTheme.cream).clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("drawer-merchant-field")
            if !recentMerchants.isEmpty {
                FlowChips(items: recentMerchants) { merchantText = $0 }
            }
            Button("Set merchant") {
                coordinator.setMerchant(cardID: target.cardID, merchantText)
                dismiss()
            }
            .buttonStyle(HandDrawnButtonStyle(filled: true))
            .accessibilityIdentifier("drawer-set")
        }
    }

    private var dateEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("When was it?").font(SketchTheme.headlineFont(20)).foregroundStyle(SketchTheme.softBrown)
            HStack(spacing: 8) {
                Button("Today") { setDate(Date()) }.buttonStyle(ChipButtonStyle())
                Button("Yesterday") { setDate(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()) }
                    .buttonStyle(ChipButtonStyle())
            }
            DatePicker("", selection: $pickedDate, displayedComponents: .date)
                .datePickerStyle(.graphical).labelsHidden()
                .accessibilityIdentifier("drawer-datepicker")
            Button("Set date") { setDate(pickedDate) }
                .buttonStyle(HandDrawnButtonStyle(filled: true))
                .accessibilityIdentifier("drawer-set")
        }
    }

    private var categoryEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a category").font(SketchTheme.headlineFont(20)).foregroundStyle(SketchTheme.softBrown)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                ForEach(BillCategory.allCases) { cat in
                    Button {
                        coordinator.edit(cardID: target.cardID, field: .category, value: .category(cat.rawValue))
                        dismiss()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: cat.sfSymbol).font(.system(size: 16)).foregroundStyle(cat.color)
                            Text(cat.englishName).font(.system(size: 11, weight: .medium, design: .rounded))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(cat.color.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(SketchTheme.softBrown)
                    .accessibilityIdentifier("drawer-cat-\(cat.rawValue)")
                }
            }
        }
    }

    private func setDate(_ date: Date) {
        coordinator.edit(cardID: target.cardID, field: .date, value: .date(date))
        dismiss()
    }

    private var recentMerchants: [String] {
        var seen = Set<String>(), out: [String] = []
        for bill in coordinator.journal.sortedBills {
            guard let m = bill.merchant, !m.isEmpty, !seen.contains(m) else { continue }
            seen.insert(m); out.append(m)
            if out.count == 4 { break }
        }
        return out
    }
}

// MARK: - Small reusable styles

struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SketchTheme.captionFont(13))
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(SketchTheme.softBlue.opacity(configuration.isPressed ? 0.3 : 0.15))
            .foregroundStyle(Color(hex: "56707E"))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(SketchTheme.softBlue, lineWidth: 1.5))
    }
}

struct HandDrawnButtonStyle: ButtonStyle {
    let filled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SketchTheme.headlineFont(15))
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(filled ? SketchTheme.sageGreen : Color.clear)
            .foregroundStyle(filled ? .white : SketchTheme.softBrown)
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(filled ? Color(hex: "93AB8B") : SketchTheme.lightBrown, lineWidth: 1.8))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void
    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Button(item) { onTap(item) }
                    .font(SketchTheme.captionFont(12))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(SketchTheme.cream).foregroundStyle(SketchTheme.softBrown)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(SketchTheme.lightBrown.opacity(0.4), lineWidth: 1))
            }
        }
    }
}
