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
    private let recognizer: RecognitionAPI
    /// Source images kept in memory for retry; not persisted, not observed.
    @ObservationIgnored private var sourceImages: [UUID: UIImage] = [:]

    /// User-facing extraction error (e.g. provider failure), shown then cleared.
    var errorMessage: String?
    /// A calm decline from moderation (intent isn't travel-and-money), shown then cleared.
    var declineMessage: String?

    init(journal: Journal, modelContext: ModelContext, recognizer: RecognitionAPI) {
        self.journal = journal
        self.modelContext = modelContext
        self.recognizer = recognizer
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

    /// Photo path — server-side recognition (Gemini vision + moderation). The
    /// user's own API key is no longer needed; the trip must exist on the server.
    func submitPhotos(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        guard let tripID = journal.serverID else {
            errorMessage = "This trip isn't synced yet — pull to refresh, then try again."
            return
        }
        for image in images {
            let id = session.enqueue(source: .photo)
            sourceImages[id] = image
            guard session.beginExtraction(cardID: id) else {
                errorMessage = "Session limit reached — start a new session."
                continue
            }
            Task { await extract(image: image, cardID: id, tripID: tripID) }
        }
    }

    private func extract(image: UIImage, cardID: UUID, tripID: UUID) async {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            _ = session.failExtraction(cardID: cardID)
            errorMessage = "Could not read that image."
            return
        }
        do {
            let response = try await recognizer.recognize(APICaptureRequest(
                text: nil, tripID: tripID, imageBase64: data.base64EncodedString(), mimeType: "image/jpeg"))
            if response.declined {
                _ = session.failExtraction(cardID: cardID)
                declineMessage = response.message ?? "I can only help with travel and money."
                return
            }
            guard let card = response.card else {
                _ = session.failExtraction(cardID: cardID)
                errorMessage = "Recognition returned nothing — try again."
                return
            }
            // Seed the local clarify-loop from the server card (the local
            // BillValidator re-derives gaps; amount stays nil if unread).
            let draft = BillDraft(serverDraft: card.draft, fallbackCurrency: journal.currency)
            _ = session.completeExtraction(cardID: cardID, draft: draft)
        } catch {
            _ = session.failExtraction(cardID: cardID)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func retry(cardID: UUID) {
        guard let image = sourceImages[cardID], let tripID = journal.serverID else { return }
        guard session.retryExtraction(cardID: cardID) else {
            errorMessage = "Session limit reached — start a new session."
            return
        }
        Task { await extract(image: image, cardID: cardID, tripID: tripID) }
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

// MARK: - Server card → local draft

extension BillDraft {
    /// Seed a draft from the server's recognized card. Amount stays nil if the
    /// server couldn't read it (never guessed); the local validator then asks.
    init(serverDraft d: APIBillDraft, fallbackCurrency: String) {
        self.init(
            merchant: d.merchant,
            amount: d.amount,
            currencyCode: d.currencyCode.isEmpty ? fallbackCurrency : d.currencyCode,
            date: d.date,
            categoryRaw: d.categoryRaw,
            lineItems: [],
            source: DraftSource(rawValue: d.source) ?? .photo
        )
    }
}
