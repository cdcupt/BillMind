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
    /// Pushes a newly-recorded bill to the server right away (and creates the trip
    /// if it isn't synced yet). Without this, recorded bills sit local-only until
    /// some other sync event — so Minds/Stats (which read the server) see nothing.
    @ObservationIgnored private let sync: SyncCoordinator?
    /// Source images kept in memory for retry; not persisted, not observed.
    @ObservationIgnored private var sourceImages: [UUID: UIImage] = [:]

    /// User-facing extraction error (e.g. provider failure), shown then cleared.
    var errorMessage: String?
    /// A calm decline from moderation (intent isn't travel-and-money), shown then cleared.
    var declineMessage: String?

    init(journal: Journal, modelContext: ModelContext, recognizer: RecognitionAPI,
         sync: SyncCoordinator? = nil) {
        self.journal = journal
        self.modelContext = modelContext
        self.recognizer = recognizer
        self.sync = sync
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

    /// Text path — **AI-first**: server-side recognition (Gemini) when the trip is
    /// synced + online, with the local `DraftExtractor` as a fallback only (offline,
    /// pre-sync, or on error). The AI is the product; the local parser is never the
    /// primary path — it just keeps capture working when the AI is unreachable.
    func submitText(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let id = session.enqueue(source: .text)
        // No synced trip → can't reach the server; deterministic local fallback.
        guard let tripID = journal.serverID else {
            completeLocally(text: trimmed, cardID: id)
            return
        }
        guard session.beginExtraction(cardID: id) else {
            errorMessage = "Session limit reached — start a new session."
            return
        }
        Task { await extractText(trimmed, cardID: id, tripID: tripID) }
    }

    private func extractText(_ text: String, cardID: UUID, tripID: UUID) async {
        do {
            let response = try await recognizer.recognize(APICaptureRequest(
                text: text, tripID: tripID, imageBase64: nil, mimeType: nil))
            if response.declined {
                _ = session.failExtraction(cardID: cardID)
                declineMessage = response.message ?? "I can only help with travel and money."
                return
            }
            let cards = response.allCards
            guard let first = cards.first else {
                completeLocally(text: text, cardID: cardID)   // unexpected empty → fallback
                return
            }
            // First bill fills the card we already enqueued; each additional bill
            // (one sentence → several bills) gets its own new card.
            let stated = Self.textMentionsDate(text)
            _ = session.completeExtraction(cardID: cardID,
                draft: draftWithDefaultDate(first.draft, dateStated: stated))
            for extra in cards.dropFirst() {
                let extraID = session.enqueue(source: .text)
                _ = session.completeExtraction(cardID: extraID,
                    draft: draftWithDefaultDate(extra.draft, dateStated: stated))
            }
        } catch {
            // Offline / server error → graceful local fallback so capture never breaks.
            completeLocally(text: text, cardID: cardID)
        }
    }

    /// Deterministic local fallback (offline / pre-sync / AI error).
    private func completeLocally(text: String, cardID: UUID) {
        var draft = DraftExtractor.parse(text, currencyCode: journal.currency)
        if draft.date == nil { draft.date = Date() }   // no date stated → device-local today
        _ = session.completeExtraction(cardID: cardID, draft: draft)
    }

    /// When the user didn't state a date, default it to the device's local **today**
    /// — not the model's guess (which is anchored to the server's clock and can land
    /// on yesterday for non-UTC users). An explicitly stated date is kept as-is.
    private func draftWithDefaultDate(_ serverDraft: APIBillDraft, dateStated: Bool) -> BillDraft {
        var draft = BillDraft(serverDraft: serverDraft, fallbackCurrency: journal.currency)
        if !dateStated { draft.date = Date() }
        return draft
    }

    /// Did the note mention a date at all — an explicit date (handled by the
    /// extractor) or a relative day word the model resolves server-side?
    static func textMentionsDate(_ text: String) -> Bool {
        if DraftExtractor.date(in: text) != nil { return true }
        let lower = text.lowercased()
        let words = ["today", "yesterday", "tomorrow", "tonight", "last ", "this ", " ago",
                     "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        return words.contains { lower.contains($0) }
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
            var draft = BillDraft(serverDraft: card.draft, fallbackCurrency: journal.currency)
            if draft.date == nil { draft.date = Date() }   // unreadable receipt date → today
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
        bill.syncState = .local        // mark pending so the next push sends it
        modelContext.insert(bill)
        try? modelContext.save()
        // Push it now (creates the trip on the server first if needed).
        Task { await sync?.sync() }
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
