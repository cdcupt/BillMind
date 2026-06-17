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
    private static let thinkingPhrases = ["Thinking…", "Pondering…", "Reading…", "Recognizing…", "Tallying…", "Crunching…", "Cooking…", "Noodling…", "Musing…", "Conjuring…", "Reckoning…", "Mulling…", "Calculating…", "Sorting…", "Working…"]

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
