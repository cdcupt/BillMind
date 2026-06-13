import Foundation
import SwiftData
import UIKit

/// Owns one `RecordingSession` for a journal and is the **single** `BillRecord`
/// writer. The UI calls these methods; the coordinator performs the agent core's
/// effects and persists only on confirm. `@MainActor` keeps the session and the
/// `ModelContext` write on the main actor — the "single writer" rule, structural.
@MainActor
@Observable
final class RecordCoordinator {
    private(set) var session: RecordingSession
    let journal: Journal
    private let modelContext: ModelContext
    /// Source images kept in memory for retry; not persisted, not observed.
    @ObservationIgnored private var sourceImages: [UUID: UIImage] = [:]

    /// User-facing extraction error (e.g. provider failure), shown then cleared.
    var errorMessage: String?

    init(journal: Journal, modelContext: ModelContext) {
        self.journal = journal
        self.modelContext = modelContext
        let validator = BillValidator(
            knownCategoryRaws: Set(BillCategory.allCases.map(\.rawValue)),
            journalCurrencyCode: journal.currency,
            today: Date()
        )
        self.session = RecordingSession(validator: validator)
    }

    /// Visible cards (discarded ones hidden), newest last.
    var cards: [AgentCard] { session.cards.filter { $0.state != .discarded } }

    var currencySymbol: String {
        CurrencyInfo.popular.first { $0.code == journal.currency }?.symbol ?? journal.currency
    }

    // MARK: - Capture

    /// Text path — local, deterministic parse. No network, no API key.
    func submitText(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let id = session.enqueue(source: .text)
        let draft = DraftExtractor.parse(trimmed, currencyCode: journal.currency)
        _ = session.completeExtraction(cardID: id, draft: draft)
    }

    /// Photo path — one extraction call per image (demo mode needs no key).
    func submitPhotos(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        let settings = AppSettings.getOrCreate(context: modelContext)
        for image in images {
            let id = session.enqueue(source: .photo)
            sourceImages[id] = image
            guard session.beginExtraction(cardID: id) else {
                errorMessage = "Session limit reached — start a new session."
                continue
            }
            Task { await extract(image: image, cardID: id, settings: settings) }
        }
    }

    private func extract(image: UIImage, cardID: UUID, settings: AppSettings) async {
        let provider = settings.selectedProvider
        let model = settings.customModel.isEmpty ? provider.defaultModel : settings.customModel
        let aiService = AIService()   // stateless; created locally so it isn't sent from MainActor storage
        do {
            let result = try await aiService.recognizeBill(
                images: [image], provider: provider, model: model,
                apiKey: settings.apiKey, demoMode: settings.demoMode
            )
            let draft = AIRecognitionMapper.draft(from: result, currencyCode: journal.currency)
            _ = session.completeExtraction(cardID: cardID, draft: draft)
        } catch {
            _ = session.failExtraction(cardID: cardID)
            errorMessage = error.localizedDescription
        }
    }

    func retry(cardID: UUID) {
        guard let image = sourceImages[cardID] else { return }
        let settings = AppSettings.getOrCreate(context: modelContext)
        guard session.retryExtraction(cardID: cardID) else {
            errorMessage = "Session limit reached — start a new session."
            return
        }
        Task { await extract(image: image, cardID: cardID, settings: settings) }
    }

    // MARK: - Clarify / edit

    func answer(cardID: UUID, field: BillField, value: ClarificationValue) {
        _ = session.answer(cardID: cardID, field: field, value: value)
    }

    func edit(cardID: UUID, field: BillField, value: ClarificationValue) {
        _ = session.edit(cardID: cardID, field: field, value: value)
    }

    func setMerchant(cardID: UUID, _ merchant: String?) {
        session.setMerchant(cardID: cardID, merchant)
    }

    func skip(cardID: UUID) {
        _ = session.skipClarification(cardID: cardID)
    }

    func discard(cardID: UUID) {
        session.discard(cardID: cardID)
    }

    // MARK: - Confirm (the only write)

    /// Returns `.recorded` on success, or a reason the confirm was refused so the
    /// view can prompt (amount required / acknowledge gaps).
    enum ConfirmOutcome { case recorded, amountRequired, needsAcknowledgment, notReviewable }

    @discardableResult
    func confirm(cardID: UUID, acknowledging: Bool = false) -> ConfirmOutcome {
        do {
            let effect = try session.confirm(cardID: cardID, acknowledging: acknowledging)
            if case .persist(let id) = effect, let card = session.card(id) {
                persist(card)
            }
            return .recorded
        } catch let error as ConfirmError {
            switch error {
            case .amountRequired: return .amountRequired
            case .needsAcknowledgment: return .needsAcknowledgment
            case .notReviewable: return .notReviewable
            }
        } catch {
            return .notReviewable
        }
    }

    private func persist(_ card: AgentCard) {
        let draft = card.draft
        let bill = BillRecord(
            date: draft.date ?? Date(),
            amount: draft.amount ?? 0,
            originalCurrency: draft.currencyCode,
            category: BillCategory(rawValue: draft.categoryRaw ?? "") ?? .misc,
            merchant: draft.merchant,
            note: nil,
            status: .confirmed
        )
        bill.lineItems = draft.lineItems.map {
            BillLineItem(itemDescription: $0.label, amount: $0.amount)
        }
        bill.journal = journal
        modelContext.insert(bill)
        try? modelContext.save()
    }
}
