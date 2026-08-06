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
    /// Set when the "Done adding" untangle hop can't run (trip not synced, or the
    /// server call failed/offline) and we fall back to saving each card on its own.
    /// Surfaced in Ollie's calm voice through the same notice banner as the others,
    /// so the degrade is visible — not silent — without an alarming alert. Shown then
    /// cleared. See `Self.untangleOfflineNote` / `Self.untangleUnsyncedNote`.
    var degradeMessage: String?

    /// The trip isn't on the server yet, so there's no plan to reason over — the cards
    /// still save individually.
    static let untangleUnsyncedNote = "This trip isn't synced yet, so I kept these as separate bills."
    /// The untangle round-trip failed or we're offline — the cards still save individually.
    static let untangleOfflineNote = "Couldn't tidy these right now — saved as separate bills."
    /// Cards whose saved bill is still committing/syncing to the server — drives a
    /// transient "Saving…" state on the card until the sync round-trip completes.
    var savingCardIDs: Set<UUID> = []

    /// `llmCallBudget` is forwarded to the session's per-session extraction-call cap.
    /// It defaults to `nil` so production uses the session's own default budget
    /// (byte-for-byte unchanged); tests inject a small budget to reach the limit
    /// deterministically and exercise the session-limit rejection path.
    init(journal: Journal, modelContext: ModelContext, recognizer: RecognitionAPI,
         sync: SyncCoordinator? = nil, llmCallBudget: Int? = nil) {
        self.journal = journal
        self.modelContext = modelContext
        self.recognizer = recognizer
        self.sync = sync
        let validator = BillValidator(
            knownCategoryRaws: Set(BillCategory.allCases.map(\.rawValue)),
            journalCurrencyCode: journal.currency,
            today: Date()
        )
        self.session = llmCallBudget.map { RecordingSession(validator: validator, llmCallBudget: $0) }
            ?? RecordingSession(validator: validator)
    }

    /// Visible cards in the Record input, newest last. Terminal cards are hidden:
    /// `.discarded` (set aside, never saved) and `.recorded` (already persisted to the
    /// trip). Hiding `.recorded` is what keeps the single-input fast path clean — once a
    /// lone card is saved it leaves the input immediately, so a stale "saved" card never
    /// lingers in the "Tell Ollie about a bill" list. The batch path additionally resets
    /// the whole session via `resetAfterFullSave()`; this filter covers the per-card case.
    var cards: [AgentCard] { session.cards.filter { !$0.state.isTerminal } }

    // MARK: - Held-batch surface (consumed by the review UI slice)

    /// The held-batch phase. `.adding` while inputs are still being dropped;
    /// `.untangling` during the round-trip; `.reviewing` once a plan (or degrade)
    /// is in. Drives the "Ollie is tidying…" overlay and the review surface.
    var batchPhase: BatchPhase { session.batchPhase }

    /// The untangle plan as views over held cards. The UI renders one row per group
    /// (`FuseProposalView` / `DuplicateGroupView`) and one per `plainReviewCardIDs`.
    var groups: [UntangleGroup] { session.groups }

    /// Held cards no group claims that are in `.review` — the SAVABLE set. Drives the
    /// "Save all · N bills" count and `confirmAll` (you can only save a `.review` card).
    var plainReviewCards: [AgentCard] {
        let ids = Set(session.plainReviewCardIDs)
        return session.cards.filter { ids.contains($0.id) }
    }

    /// Held cards no group claims that the review surface must RENDER — every
    /// non-terminal card, including `.clarifying`/`.validating`/`.failed` ones that
    /// `plainReviewCards` (savable-only) excludes. This is what the user SEES so a
    /// batch with unfinished cards never collapses to a blank "0 bills" screen; each
    /// card shows its own state UI and becomes savable once resolved into `.review`.
    var reviewSurfaceCards: [AgentCard] {
        let ids = Set(session.reviewSurfaceCardIDs)
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
        // No date stated → device-local today. An ambiguous date the extractor
        // refused to guess (rawDateText, e.g. "05/08/2026") is NOT "no date" —
        // stamping today would silently discard what the user typed; the date
        // clarify asks instead.
        if draft.date == nil && draft.rawDateText == nil { draft.date = Date() }
        _ = session.completeExtraction(cardID: cardID, draft: draft)
    }

    /// When the user didn't state a date, default it to the device's local **today**
    /// — not the model's guess (which is anchored to the server's clock and can land
    /// on yesterday for non-UTC users). An explicitly stated date is kept as-is.
    private func draftWithDefaultDate(_ serverDraft: APIBillDraft, dateStated: Bool) -> BillDraft {
        var draft = BillDraft(serverDraft: serverDraft, fallbackCurrency: journal.currency)
        if !dateStated && draft.rawDateText == nil { draft.date = Date() }
        return draft
    }

    /// Did the note mention a date at all — an explicit date, an ambiguous slash
    /// date the extractor refused to guess (both handled by the extractor), or a
    /// relative day word the model resolves server-side?
    static func textMentionsDate(_ text: String) -> Bool {
        if DraftExtractor.date(in: text) != nil { return true }
        if DraftExtractor.rawDateText(in: text) != nil { return true }
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
                // Same enqueue-before-guard rollback as submitComposed: drop the phantom
                // card + its image so a session-limit rejection strands nothing.
                rollbackEnqueued(cardID: id)
                errorMessage = "Session limit reached — start a new session."
                continue
            }
            Task { await extract(image: image, cardID: id, tripID: tripID) }
        }
    }

    /// Recognize one image (optionally with a `caption` from the compose path). When a
    /// caption is present it rides in the SAME request as the image (both fields set), so
    /// the server reads the photo + sentence as one bill — that is the only difference
    /// from the plain photo-only path.
    private func extract(image: UIImage, caption: String? = nil, cardID: UUID, tripID: UUID) async {
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
                text: caption, tripID: tripID, imageBase64: data.base64EncodedString(), mimeType: "image/jpeg"))
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
            // Unreadable receipt date → today; but a date the model READ and we
            // refused to guess (rawDateText, e.g. a "05/08/2026" print) must
            // reach the clarify, not be silently replaced with today.
            if draft.date == nil && draft.rawDateText == nil { draft.date = Date() }
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

    /// Compose path — the user staged a photo and attached a caption to it, then sent
    /// both as **one** input. Mirrors `submitPhotos`' single-image path exactly, but
    /// carries the caption into the same `APICaptureRequest` (both `imageBase64` AND
    /// `text` set), so the server reads the picture and the sentence as one bill and the
    /// caption fills the photo's gaps. One request → one `.photo` card. An empty caption
    /// degrades to the byte-for-byte photo-only path. The money rule is unchanged: the
    /// amount stays nil if neither OCR nor the caption yields one (never invented), and
    /// the local validator's "amount required" gate still applies.
    ///
    /// Returns `true` when the photo+caption was accepted (enqueued and extraction
    /// started), `false` when it was rejected — unsynced trip (`serverID == nil`) or the
    /// session limit was reached. The caller relies on this to know whether the staged
    /// chip was actually consumed: a rejected send must keep its chip + caption so the
    /// user can retry, never silently dropping the photo behind the surfaced error.
    @discardableResult
    func submitComposed(image: UIImage, caption: String) -> Bool {
        let note = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let tripID = journal.serverID else {
            errorMessage = "This trip isn't synced yet — pull to refresh, then try again."
            return false
        }
        let id = session.enqueue(source: .photo)
        sourceImages[id] = image
        photoHashes[id] = image.perceptualHashHex()        // same-photo dedup signal
        if !note.isEmpty { noteTexts[id] = note }           // caption rides as the fuse/dedup note
        guard session.beginExtraction(cardID: id) else {
            // Session-limit guard failed AFTER the enqueue — roll back the phantom card
            // and its image/metadata so nothing is stranded. The caller keeps the staged
            // chip on `false`, so without this rollback a retry would enqueue a duplicate.
            rollbackEnqueued(cardID: id)
            errorMessage = "Session limit reached — start a new session."
            return false
        }
        Task { await extract(image: image, caption: note.isEmpty ? nil : note, cardID: id, tripID: tripID) }
        return true
    }

    /// Undo a just-enqueued photo input when its extraction never started (the session
    /// LLM-call budget was exhausted, so `beginExtraction` returned `false`). Removes
    /// the phantom `.intake` card from the session AND clears the in-memory image and
    /// dedup metadata keyed to it, so a rejected send leaves no trace and a later retry
    /// enqueues exactly one card — never a duplicate. Mirrors the enqueue side effects
    /// in `submitPhotos` / `submitComposed` so the two paths stay consistent.
    private func rollbackEnqueued(cardID: UUID) {
        session.cancelEnqueued(cardID: cardID)
        sourceImages[cardID] = nil
        photoHashes[cardID] = nil
        noteTexts[cardID] = nil
        photoAssetIDs[cardID] = nil
    }

    // MARK: - Held batch (Done adding → untangle → review)

    /// Commit the held cards to a batch and run the untangle reasoning hop. Gathers
    /// each held card's draft + dedup signals (photoHash/assetID for photos, noteText
    /// for text) — no image bytes — calls `RecognitionAPI.untangle`, then builds the
    /// review groups. On error/timeout (or no synced trip) it degrades straight to
    /// review with plain held cards, where per-card Save still works.
    func markDoneAdding() {
        // Untangle reasons only over cards that actually reached `.review` (recognized
        // + held). Placeholder/in-flight cards (intake/extracting/clarifying) and
        // terminal ones (failed/discarded/recorded) are excluded so a plan is never
        // built from incomplete drafts. A lone reviewed input takes the fast path → no-op.
        // (If extractions are still in flight when Done-adding is tapped, only the
        // already-review cards are sent — acceptable for v1; we don't block on in-flight.)
        guard session.cards.filter({ $0.state == .review }).count > 1 else { return }
        guard let tripID = journal.serverID else {
            session.markDoneAdding()
            session.degradeToReview()      // no synced trip → plain review, cards still save
            degradeMessage = Self.untangleUnsyncedNote   // make the degrade visible, not silent
            return
        }
        let inputs = heldUntangleInputs()
        session.markDoneAdding()
        Task { await runUntangle(tripID: tripID, inputs: inputs) }
    }

    private func heldUntangleInputs() -> [APIUntangleInput] {
        // Only fully-recognized, held cards feed untangle — never a placeholder/in-flight
        // draft (intake/extracting/clarifying) or a terminal one (failed/discarded).
        session.cards.filter { $0.state == .review }.map { card in
            let d = card.draft
            return APIUntangleInput(
                cardID: card.id,
                draft: APIBillDraft(merchant: d.merchant, amount: d.amount,
                                    currencyCode: d.currencyCode, categoryRaw: d.categoryRaw,
                                    date: d.date, rawDateText: d.rawDateText,
                                    source: d.source.rawValue),
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
            // Degrade: plain held cards, per-card Save still works. Surface it calmly in
            // Ollie's voice (not the raw API error) so the lost tidy-up is visible, not silent.
            session.degradeToReview()
            degradeMessage = Self.untangleOfflineNote
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
    ///
    /// Crucially, cards still **claimed by a pending fuse/duplicate group are never
    /// persisted** — the money rule (nothing saved/dropped without resolution). Until
    /// the user resolves a group (combine/split/keepOne/keepBoth), its member cards are
    /// reported as blocked, so "Save all" effectively blocks until every group is
    /// touched. Only plain review cards (unclaimed + cards materialized by an accepted
    /// combine/keepOne/keepBoth) are written here.
    /// Returns the ids of rows that could NOT be saved (empty ⇒ all saved).
    @discardableResult
    func confirmAll(acknowledging: Bool = false) -> [UUID] {
        var blocked: [UUID] = []
        // Member cards of any still-pending group are NOT saved — block until resolved.
        // (A discarded/set-aside member is already excluded by activeCardIDs.)
        let claimed = Set(session.groups.flatMap { $0.memberCardIDs })
        let claimedReviewable = session.cards
            .filter { $0.state == .review && claimed.contains($0.id) }
            .map(\.id)
        blocked.append(contentsOf: claimedReviewable)
        // Snapshot the unclaimed plain review ids first; persist() mutates session
        // state as it goes. `plainReviewCardIDs` is exactly the set no group owns.
        let plainReviewIDs = Set(session.plainReviewCardIDs)
        let reviewableIDs = session.cards
            .filter { $0.state == .review && plainReviewIDs.contains($0.id) }
            .map(\.id)
        for id in reviewableIDs {
            if confirm(cardID: id, acknowledging: acknowledging) != .recorded {
                blocked.append(id)
            }
        }
        // Clean, complete save → return the Record tab to its fresh "Tell Ollie about a
        // bill" input. The batch is fully resolved only when nothing was blocked, no
        // group is still pending, and no non-terminal card lingers (a clarifying/failed/
        // still-extracting card means the user has more to finish — stay in `.reviewing`
        // so it never collapses to a blank "Save all · 0 bills" screen). The saved bills
        // are already persisted via `confirm`/`persist`; this only resets session state.
        if blocked.isEmpty && session.groups.isEmpty
            && !session.cards.contains(where: { !$0.state.isTerminal }) {
            session.resetAfterFullSave()
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
        // Money rule: the per-card Save must NOT bypass the batch's group protections.
        // A card claimed by any still-pending fuse/duplicate group is never persisted
        // here — the only way to save a grouped member is to resolve its group first
        // (combine/split/keepOne/keepBoth), which returns it (or a new card) to plain
        // review. While a batch is active, only current plain-review cards may save via
        // this path; everything else mirrors how `confirmAll` skips claimed members.
        // The single-input fast path (no active batch) is unaffected.
        if session.hasActiveBatch {
            let claimed = Set(session.groups.flatMap { $0.memberCardIDs })
            if claimed.contains(cardID) || !session.plainReviewCardIDs.contains(cardID) {
                return .notReviewable
            }
        }
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

// MARK: - Preview seeding (DEBUG only)

#if DEBUG
extension RecordCoordinator {
    /// A no-op recognizer for previews — the seeded reviewing state never calls it.
    private struct PreviewRecognizer: RecognitionAPI {
        func recognize(_ req: APICaptureRequest) async throws -> APICaptureResponse {
            APICaptureResponse(declined: false, message: nil, card: nil, cards: [])
        }
        func untangle(_ req: APIUntangleRequest) async throws -> APIUntangleResponse {
            APIUntangleResponse(declined: false, message: nil,
                                fuseGroups: [], duplicateGroups: [], cleanCardIDs: [])
        }
    }

    /// Drive the real session transitions to land in `.reviewing` with one fuse
    /// proposal, one duplicate group, and one plain card — so a `#Preview` (and
    /// snapshot capture) exercises the review surface the coordinator produces,
    /// using the same `applyUntangle` path the live flow uses.
    static func previewReviewing(modelContext: ModelContext) -> RecordCoordinator {
        let journal = Journal(name: "Kyoto Spring", currency: "JPY", coverAnimal: .owl)
        let coordinator = RecordCoordinator(
            journal: journal, modelContext: modelContext, recognizer: PreviewRecognizer())

        func draft(_ merchant: String?, _ amount: Decimal?, _ cat: String, _ source: DraftSource) -> BillDraft {
            BillDraft(merchant: merchant, amount: amount, currencyCode: "JPY",
                      date: Date(), categoryRaw: cat, source: source)
        }
        func review(_ d: BillDraft) -> UUID {
            let id = coordinator.session.enqueue(source: d.source)
            _ = coordinator.session.beginExtraction(cardID: id)
            _ = coordinator.session.completeExtraction(cardID: id, draft: d)
            return id
        }

        // Fuse pair: an amountless taxi photo completed by a "it was 240" note.
        let photoID = review(draft("Kyoto MK Taxi", nil, "transport", .photo))
        let noteID  = review(draft(nil, 240, "transport", .text))
        // Duplicate pair: the same ramen bill, once from a photo and once typed.
        let ramenPhoto = review(draft("Ichiran Ramen", 1480, "food", .photo))
        let ramenTyped = review(draft("Ramen (typed)", 1480, "food", .text))
        // A plain clean card that simply flows through.
        _ = review(draft("Blue Bottle Coffee", 520, "food", .text))

        let fuseGroup = APIFuseGroup(
            groupID: UUID(),
            sourceCardIDs: [photoID, noteID],
            resolvedDraft: APIBillDraft(merchant: "Kyoto MK Taxi", amount: 240,
                                        currencyCode: "JPY", categoryRaw: "transport",
                                        date: Date(), source: "photo"),
            amountTrace: APIAmountTrace(sourceCardID: noteID, field: "amount"),
            reason: "A receipt missing its total, completed by your note.",
            confidence: 0.9)
        let dupGroup = APIDuplicateGroup(
            groupID: UUID(),
            memberCardIDs: [ramenPhoto, ramenTyped],
            survivorCardID: ramenPhoto,
            tier: "sameDetails",
            reason: "Same merchant, amount & date.")

        coordinator.session.markDoneAdding()
        coordinator.session.applyUntangle(APIUntangleResponse(
            declined: false, message: nil,
            fuseGroups: [fuseGroup], duplicateGroups: [dupGroup], cleanCardIDs: []))
        return coordinator
    }
}
#endif

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
            rawDateText: d.rawDateText,
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
