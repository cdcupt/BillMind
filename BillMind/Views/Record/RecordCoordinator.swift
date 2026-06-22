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
    /// Per-card dedup signals supplied to untangle: a perceptual photoHash and/or
    /// the photo-library asset id for same-photo confirmation, and the raw note text
    /// for text cards. Merchant/amount/date already ride in the draft. Not observed.
    @ObservationIgnored private var photoHashes: [UUID: String] = [:]
    @ObservationIgnored private var photoAssetIDs: [UUID: String] = [:]
    @ObservationIgnored private var noteTexts: [UUID: String] = [:]

    /// User-facing extraction error (e.g. provider failure), shown then cleared.
    var errorMessage: String?
    /// A calm decline from moderation (intent isn't travel-and-money), shown then cleared.
    var declineMessage: String?
    /// Cards whose saved bill is still committing/syncing to the server — drives a
    /// transient "Saving…" state on the card until the sync round-trip completes.
    var savingCardIDs: Set<UUID> = []

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

    // MARK: - Held-batch surface (consumed by the review UI slice)

    /// The held-batch phase. `.adding` while inputs are still being dropped;
    /// `.untangling` during the round-trip; `.reviewing` once a plan (or degrade)
    /// is in. Drives the "Ollie is tidying…" overlay and the review surface.
    var batchPhase: BatchPhase { session.batchPhase }

    /// The untangle plan as views over held cards. The UI renders one row per group
    /// (`FuseProposalView` / `DuplicateGroupView`) and one per `plainReviewCardIDs`.
    var groups: [UntangleGroup] { session.groups }

    /// Held cards no group claims — rendered as plain `AgentCardView` review rows.
    var plainReviewCards: [AgentCard] {
        let ids = Set(session.plainReviewCardIDs)
        return session.cards.filter { ids.contains($0.id) }
    }

    /// True while a held batch exists — the per-card "Save" is paused (the user
    /// saves the whole reviewed batch via `confirmAll`). Single clean inputs stay
    /// `.adding` and keep their instant per-card Save (the A6 fast path).
    var isBatchActive: Bool { session.hasActiveBatch }

    /// Whether the UI should offer the instant per-card "Save" on a card. Held while
    /// a batch exists (save the whole reviewed batch instead); always on otherwise,
    /// which is what keeps single-capture byte-for-byte unchanged.
    var allowsPerCardSave: Bool { !session.hasActiveBatch }

    /// Whether the sticky "Done adding" bar should show — only with more than one
    /// held card still in `.adding`. A lone input never sees it (A6 fast path).
    var showsDoneAddingBar: Bool {
        session.batchPhase == .adding && cards.count > 1
    }

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
        noteTexts[id] = trimmed   // dedup/fusion signal for untangle
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
            photoHashes[id] = image.perceptualHashHex()   // same-photo dedup signal
            guard session.beginExtraction(cardID: id) else {
                errorMessage = "Session limit reached — start a new session."
                continue
            }
            Task { await extract(image: image, cardID: id, tripID: tripID) }
        }
    }

    private func extract(image: UIImage, cardID: UUID, tripID: UUID) async {
        // Bound the upload: a full-res sensor photo, base64-in-JSON, can exceed the
        // server's body limit (this was the "413 Payload Too Large"). Downscale to a
        // max edge before encoding — smaller/faster uploads and lower vision cost,
        // with no OCR-relevant detail loss.
        guard let data = image.downscaled(maxEdge: 2048).jpegData(compressionQuality: 0.8) else {
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

    // MARK: - Held batch (Done adding → untangle → review)

    /// Commit the held cards to a batch and run the untangle reasoning hop. Gathers
    /// each held card's draft + dedup signals (photoHash/assetID for photos, noteText
    /// for text) — no image bytes — calls `RecognitionAPI.untangle`, then builds the
    /// review groups. On error/timeout (or no synced trip) it degrades straight to
    /// review with plain held cards, where per-card Save still works.
    func markDoneAdding() {
        // Nothing to untangle (a lone clean input takes the fast path) → no-op.
        guard session.cards.filter({ !$0.state.isTerminal }).count > 1 else { return }
        guard let tripID = journal.serverID else {
            session.markDoneAdding()
            session.degradeToReview()      // can't reach the server → plain review
            return
        }
        let inputs = heldUntangleInputs()
        session.markDoneAdding()
        Task { await runUntangle(tripID: tripID, inputs: inputs) }
    }

    private func heldUntangleInputs() -> [APIUntangleInput] {
        session.cards.filter { !$0.state.isTerminal }.map { card in
            let d = card.draft
            return APIUntangleInput(
                cardID: card.id,
                draft: APIBillDraft(merchant: d.merchant, amount: d.amount,
                                    currencyCode: d.currencyCode, categoryRaw: d.categoryRaw,
                                    date: d.date, source: d.source.rawValue),
                hasPhoto: card.draft.source == .photo,
                noteText: noteTexts[card.id],
                photoHash: photoHashes[card.id],
                photoAssetID: photoAssetIDs[card.id])
        }
    }

    private func runUntangle(tripID: UUID, inputs: [APIUntangleInput]) async {
        do {
            let response = try await recognizer.untangle(
                APIUntangleRequest(tripID: tripID, inputs: inputs))
            if response.declined {
                declineMessage = response.message ?? "I can only help with travel and money."
                session.degradeToReview()
                return
            }
            session.applyUntangle(response)
        } catch {
            // Degrade: plain held cards, per-card Save still works; surface the error.
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            session.degradeToReview()
        }
    }

    // MARK: - Group resolution (each returns groups to plain review cards)

    func combine(groupID: UUID) { _ = session.combine(groupID: groupID) }
    func split(groupID: UUID) { session.split(groupID: groupID) }
    func keepOne(groupID: UUID, survivor: UUID) { session.keepOne(groupID: groupID, survivor: survivor) }
    func keepBoth(groupID: UUID) { session.keepBoth(groupID: groupID) }

    /// Save the whole reviewed batch: one `BillRecord` per plain review card and per
    /// accepted fuse (accepted fuses are already plain review cards by the time this
    /// runs), via the unchanged `persist` mapping. Set-aside duplicates are not
    /// persisted. Each row is gated by the existing amount/acknowledge guards; a row
    /// that can't save (e.g. a fused card with `amountTrace == nil` → amount nil) is
    /// left in review and reported, so the user resolves it without losing the rest.
    /// Returns the ids of rows that could NOT be saved (empty ⇒ all saved).
    @discardableResult
    func confirmAll(acknowledging: Bool = false) -> [UUID] {
        var blocked: [UUID] = []
        // Snapshot reviewable ids first; persist() mutates session state as it goes.
        let reviewableIDs = session.cards
            .filter { $0.state == .review }
            .map(\.id)
        for id in reviewableIDs {
            if confirm(cardID: id, acknowledging: acknowledging) != .recorded {
                blocked.append(id)
            }
        }
        return blocked
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
        // Push it now (creates the trip on the server first if needed). Mark the
        // card saving and clear it when the round-trip ends — success OR failure —
        // so the card never sticks on "Saving…". `SyncCoordinator.sync()` catches
        // its own errors and never throws, so `remove` always runs after the await.
        savingCardIDs.insert(card.id)
        Task {
            await sync?.sync()
            savingCardIDs.remove(card.id)
        }
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

// MARK: - Image downscale (bound upload payload + vision cost)

extension UIImage {
    /// Returns a copy whose longest edge is at most `maxEdge` px (no-op if already
    /// within bounds). Preserves aspect ratio and renders at scale 1, so the pixel
    /// dimensions match `maxEdge` and the base64 upload payload stays bounded.
    func downscaled(maxEdge: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxEdge, longest > 0 else { return self }
        let ratio = maxEdge / longest
        let newSize = CGSize(width: (size.width * ratio).rounded(),
                             height: (size.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// A 64-bit average-hash (aHash) perceptual fingerprint as a 16-char hex string.
    /// Downscales to 8×8 grayscale and marks each pixel above the mean — robust to
    /// re-encoding/scaling so two captures of the same receipt hash near-identically.
    /// This is a *signal only*: the server confirms same-photo; the client never
    /// decides a duplicate on its own. Returns `nil` if the image can't be rasterized.
    func perceptualHashHex() -> String? {
        let side = 8
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        guard let cg = small.cgImage else { return nil }

        let count = side * side
        var pixels = [UInt8](repeating: 0, count: count)
        let gray = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: &pixels, width: side, height: side,
                                  bitsPerComponent: 8, bytesPerRow: side,
                                  space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        let mean = pixels.reduce(0) { $0 + Int($1) } / count
        var bits: UInt64 = 0
        for (i, p) in pixels.enumerated() where Int(p) >= mean {
            bits |= (1 << UInt64(i))
        }
        return String(format: "%016llx", bits)
    }
}
