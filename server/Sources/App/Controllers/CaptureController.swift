import Vapor
import Fluent
import BillMindCore

/// `POST /v1/recognition` — capture entry for text, a photo, OR a photo + caption:
/// text → local DraftExtractor; image → Gemini vision → AIRecognitionMapper;
/// image + text → compose: recognize the photo, then let the caption fill the
/// photo's gaps (a stated amount/merchant/date overrides an unreadable photo value),
/// returning ONE card. All paths run the moderation gate first and return the same
/// CardDTO. Amount is never guessed (the validator flags a missing amount; canSave
/// gates on it) — and the caption is read as a hint, never invented money.
struct CaptureController: RouteCollection {
    let moderation: ModerationService
    let recognizer: Recognizer
    let textRecognizer: TextRecognizer

    init(moderation: ModerationService, recognizer: Recognizer,
         textRecognizer: TextRecognizer = LocalTextRecognizer()) {
        self.moderation = moderation
        self.recognizer = recognizer
        self.textRecognizer = textRecognizer
    }

    func boot(routes: RoutesBuilder) throws {
        let group = routes.grouped("v1").grouped(UserAuthMiddleware())
        // Receipt photos arrive base64-in-JSON; a single phone photo easily clears
        // the 1mb global cap and used to 413. Give just this route a 10mb ceiling
        // (the client also downscales before upload). Other routes keep the tight
        // global limit set in configure.swift.
        group.on(.POST, "recognition", body: .collect(maxSize: "10mb"), use: recognize)
    }

    func recognize(_ req: Request) async throws -> CaptureResponse {
        let user = try req.auth.require(User.self)
        let uid = try user.requireID()
        let body = try req.content.decode(CaptureRequest.self)

        guard let trip = try await Trip.query(on: req.db)
            .filter(\.$id == body.tripID).filter(\.$owner.$id == uid).first()
        else { throw Abort(.notFound, reason: "trip not found") }

        let drafts: [BillDraft]

        let composeImage = body.imageBase64.flatMap { $0.isEmpty ? nil : $0 }
        let composeCaption = body.text.flatMap { $0.isEmpty ? nil : $0 }

        if let imageBase64 = composeImage, let caption = composeCaption {
            // Compose path — a staged photo with an accompanying caption arrive as ONE
            // request. The caption is user free-text, so moderate it first (same gate
            // the text path uses). Then recognize the photo and let the caption fill
            // the photo's gaps: a clearly-stated amount/merchant/date in the caption
            // fills a missing one and OVERRIDES an unreadable photo value — but money is
            // never invented, so if neither yields a total the card comes back amount-less
            // and the validator's "amount required" gate handles it. ONE card out.
            if let declined = try await guardModeration(caption, uid: uid, req: req,
                                                        expenseShaped: DraftExtractor.firstAmount(in: caption) != nil) {
                return declined
            }
            let result = try await recognizer.recognize(imageBase64: imageBase64,
                                                         mimeType: body.mimeType ?? "image/jpeg", on: req)
            let photoDraft = AIRecognitionMapper.draft(from: result, currencyCode: trip.currencyCode)
            let today = Self.validClientDate(body.clientDate) ?? LocalTextRecognizer.utcTodayString()
            drafts = [Self.compose(photoDraft: photoDraft, caption: caption,
                                   currencyCode: trip.currencyCode, today: today)]

        } else if let imageBase64 = body.imageBase64, !imageBase64.isEmpty {
            // Photo path — server-side recognition (one bill per receipt).
            let result = try await recognizer.recognize(imageBase64: imageBase64,
                                                         mimeType: body.mimeType ?? "image/jpeg", on: req)
            // Moderate the recognized text (treated as untrusted), catastrophic-only.
            let recognizedText = [result.merchant, result.notes].compactMap { $0 }.joined(separator: " ")
            if let declined = try await guardModeration(recognizedText.isEmpty ? "receipt" : recognizedText,
                                                        uid: uid, req: req) { return declined }
            drafts = [AIRecognitionMapper.draft(from: result, currencyCode: trip.currencyCode)]

        } else if let text = body.text, !text.isEmpty {
            // Text path — AI (Gemini) with a deterministic local fallback. One
            // sentence can yield SEVERAL bills. Moderate first (untrusted input),
            // then recognize; the validator still guards money downstream (a missing
            // amount blocks Save, never guessed).
            if let declined = try await guardModeration(text, uid: uid, req: req,
                                                        expenseShaped: DraftExtractor.firstAmount(in: text) != nil) {
                return declined
            }
            let today = Self.validClientDate(body.clientDate) ?? LocalTextRecognizer.utcTodayString()
            drafts = await textRecognizer.recognize(text: text, currencyCode: trip.currencyCode, today: today, on: req)

        } else {
            throw Abort(.badRequest, reason: "provide text or imageBase64")
        }

        let tripID = try trip.requireID()
        let cards = drafts.map { makeCardDTO($0, tripID: tripID, currencyCode: trip.currencyCode) }
        return .cardsResponse(cards)
    }

    /// Accept the client's date only if it's a strict yyyy-MM-dd in a sane range —
    /// it's interpolated into the prompt, so an unvalidated value is an injection
    /// surface. Returns the validated string, or nil to fall back to UTC today.
    static func validClientDate(_ raw: String?) -> String? {
        guard let raw, raw.count == 10 else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.isLenient = false
        guard let date = f.date(from: raw), f.string(from: date) == raw else { return nil }
        // Reject absurd dates (clock-skew / tampering): within ~2 days of UTC now.
        let drift = abs(date.timeIntervalSince(Date()))
        return drift < 60 * 60 * 24 * 2 ? raw : nil
    }

    /// Merge a recognized photo draft with its accompanying caption into ONE draft.
    ///
    /// The caption is parsed locally (deterministic, no network) and read as a
    /// gap-fill on top of what the photo gave. Precedence is calibrated to what the
    /// extractor can state with confidence vs. what it merely scrapes:
    ///
    /// - **Amount** is the decisive field: a clearly-stated caption total fills a
    ///   missing photo total AND overrides an unreadable one — never invented, so when
    ///   the caption has no number the photo's amount (possibly nil) is kept as-is and
    ///   an amount-less draft stays gap-blocked.
    /// - **Merchant / category / date** are fill-only: they're taken from the caption
    ///   ONLY when the photo couldn't read them. A gap-fill caption like "total was 240,
    ///   lunch with the team" scrapes a noisy merchant/category out of leftover words,
    ///   so it must not clobber a merchant/category the receipt actually carried. (An
    ///   explicit calendar date is the one date signal the extractor is sure of, but a
    ///   read photo date is still authoritative, so date is fill-only too.)
    ///
    /// Pure/static so the merge is unit-tested without a network or Gemini.
    static func compose(photoDraft: BillDraft, caption: String,
                        currencyCode: String, today: String) -> BillDraft {
        let cap = DraftExtractor.parse(caption, currencyCode: currencyCode,
                                       reference: LocalTextRecognizer.referenceDate(from: today))
        var merged = photoDraft

        // Amount: a stated caption total fills/overrides; never invent when absent.
        if let captionAmount = cap.amount { merged.amount = captionAmount }

        // Merchant: fill only when the photo read none (avoid scraped-name noise).
        if (merged.merchant?.isEmpty ?? true), let captionMerchant = cap.merchant, !captionMerchant.isEmpty {
            merged.merchant = captionMerchant
        }

        // Date: fill only when the photo couldn't read one. DraftExtractor only yields
        // a date for an explicit calendar date (relative words stay nil), so this never
        // guesses a day.
        if merged.date == nil, let captionDate = cap.date {
            merged.date = captionDate
            merged.rawDateText = nil
        } else if merged.date == nil, merged.rawDateText == nil, let captionRaw = cap.rawDateText {
            // The caption stated a date we refused to guess (ambiguous slash
            // form) — carry it so the client's date clarify asks instead of the
            // date silently defaulting.
            merged.rawDateText = captionRaw
        }

        // Category: fill only when the photo gave none — a generic "misc" from the
        // caption must not clobber a category the receipt actually carried.
        if (merged.categoryRaw?.isEmpty ?? true), let captionCategory = cap.categoryRaw {
            merged.categoryRaw = captionCategory
        }

        return merged
    }

    /// Runs the gate; returns a decline response if blocked, else nil (proceed).
    private func guardModeration(_ text: String, uid: UUID, req: Request,
                                 expenseShaped: Bool = true) async throws -> CaptureResponse? {
        let verdict = try await moderation.evaluate(text, surface: .recognition, expenseShaped: expenseShaped, on: req)
        try await moderation.logEvent(verdict, raw: text, surface: .recognition, userID: uid,
                                      requestID: req.id, on: req.db)
        guard verdict.decision == .block else { return nil }
        return .declinedResponse("I can't help with that one — I'm your travel-and-money agent.")
    }

    private func makeCardDTO(_ draft: BillDraft, tripID: UUID, currencyCode: String) -> CardDTO {
        let validator = BillValidator(
            knownCategoryRaws: Set(BillCategory.allCases.map(\.rawValue)),
            journalCurrencyCode: currencyCode, today: Date()
        )
        let gaps = validator.validate(draft).map {
            GapDTO(field: $0.field.rawValue, reason: $0.reason,
                   prompt: $0.question.prompt, options: $0.question.options.map(\.label))
        }
        return CardDTO(tripID: tripID, draft: BillDraftDTO(draft), gaps: gaps, canSave: draft.amount != nil)
    }
}
