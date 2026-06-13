import XCTest
@testable import BillMind

// Tests for the Foundation-only recording-agent core: the validator, the card
// state machine, budgets, and the single-writer confirm rule. These mirror the
// logic verified standalone with `swiftc`; here they run in the app test target.

private let knownCategories: Set<String> = Set(BillCategory.allCases.map(\.rawValue))

private func makeValidator(journal: String = "JPY") -> BillValidator {
    BillValidator(
        knownCategoryRaws: knownCategories,
        journalCurrencyCode: journal,
        today: Date(timeIntervalSince1970: 1_775_000_000)
    )
}

private func dec(_ s: String) -> Decimal { Decimal(string: s)! }

// MARK: - Validator

final class BillValidatorTests: XCTestCase {
    func testCleanDraftHasNoGaps() {
        let v = makeValidator()
        let draft = BillDraft(
            merchant: "Ichiran", amount: dec("2840"), currencyCode: "JPY",
            date: Date(), categoryRaw: "food",
            lineItems: [DraftLineItem(label: "Ramen", amount: dec("2160")),
                        DraftLineItem(label: "Beer", amount: dec("680"))],
            source: .photo
        )
        XCTAssertTrue(v.validate(draft).isEmpty)
    }

    func testAmountMismatchIsFlagged() {
        let v = makeValidator()
        let draft = BillDraft(
            amount: dec("320"), currencyCode: "JPY", date: Date(), categoryRaw: "transport",
            lineItems: [DraftLineItem(label: "Meter", amount: dec("3200"))], source: .photo
        )
        let gaps = v.validate(draft)
        XCTAssertEqual(gaps.map(\.field), [.amount])
        XCTAssertEqual(gaps.first?.question.options.count, 2)
    }

    func testMissingDateRaisesAnswerableGap() {
        let v = makeValidator()
        let draft = BillDraft(amount: dec("10"), currencyCode: "JPY", date: nil, categoryRaw: "food", source: .text)
        let gaps = v.validate(draft)
        XCTAssertEqual(gaps.map(\.field), [.date])
        XCTAssertFalse(gaps[0].question.options.isEmpty)
    }

    func testCurrencyMismatchWithJournalIsFlagged() {
        let v = makeValidator(journal: "JPY")
        let draft = BillDraft(amount: dec("6"), currencyCode: "EUR", date: Date(), categoryRaw: "food", source: .photo)
        XCTAssertTrue(v.validate(draft).contains { $0.field == .currency })
    }

    func testUnknownCategoryIsFlagged() {
        let v = makeValidator()
        let draft = BillDraft(amount: dec("6"), currencyCode: "JPY", date: Date(), categoryRaw: "spaceship", source: .photo)
        XCTAssertTrue(v.validate(draft).contains { $0.field == .category })
    }

    func testPinnedFieldIsNotReQuestioned() {
        let v = makeValidator()
        var draft = BillDraft(
            amount: dec("320"), currencyCode: "JPY", date: Date(), categoryRaw: "transport",
            lineItems: [DraftLineItem(label: "x", amount: dec("3200"))], source: .photo
        )
        XCTAssertTrue(v.validate(draft).contains { $0.field == .amount })
        draft.pinnedFields.insert(.amount)
        XCTAssertFalse(v.validate(draft).contains { $0.field == .amount })
    }
}

// MARK: - Session state machine

final class RecordingSessionTests: XCTestCase {
    func testCleanReceiptGoesToReviewThenPersistsOnConfirm() throws {
        var s = RecordingSession(validator: makeValidator())
        let id = s.enqueue(source: .photo)
        XCTAssertTrue(s.beginExtraction(cardID: id))
        let draft = BillDraft(
            id: id, merchant: "Ichiran", amount: dec("2840"), currencyCode: "JPY",
            date: Date(), categoryRaw: "food",
            lineItems: [DraftLineItem(label: "Ramen", amount: dec("2160")),
                        DraftLineItem(label: "Beer", amount: dec("680"))],
            source: .photo
        )
        XCTAssertEqual(s.completeExtraction(cardID: id, draft: draft), [.readyForReview(cardID: id)])
        XCTAssertEqual(s.card(id)?.state, .review)
        XCTAssertEqual(try s.confirm(cardID: id), .persist(cardID: id))
        XCTAssertEqual(s.card(id)?.state, .recorded)
        XCTAssertEqual(s.recordedCards.count, 1)
    }

    func testClarifyThenAnswerReachesReview() throws {
        var s = RecordingSession(validator: makeValidator())
        let id = s.enqueue(source: .photo)
        _ = s.beginExtraction(cardID: id)
        let draft = BillDraft(
            id: id, amount: dec("320"), currencyCode: "JPY", date: Date(), categoryRaw: "transport",
            lineItems: [DraftLineItem(label: "Meter", amount: dec("3200"))], source: .photo
        )
        guard case .askQuestions(let qs, let cid, let round)? = s.completeExtraction(cardID: id, draft: draft).first else {
            return XCTFail("expected a clarification round")
        }
        XCTAssertEqual(cid, id)
        XCTAssertEqual(round, 1)
        XCTAssertEqual(qs.first?.field, .amount)
        XCTAssertThrowsError(try s.confirm(cardID: id)) { XCTAssertEqual($0 as? ConfirmError, .notReviewable) }
        XCTAssertEqual(s.answer(cardID: id, field: .amount, value: .amount(dec("3200"))), [.readyForReview(cardID: id)])
        XCTAssertEqual(s.card(id)?.draft.amount, dec("3200"))
        XCTAssertTrue(s.card(id)?.draft.pinnedFields.contains(.amount) == true)
    }

    func testThirdGapOpensSecondRound() {
        var s = RecordingSession(validator: makeValidator(journal: "JPY"))
        let id = s.enqueue(source: .photo)
        _ = s.beginExtraction(cardID: id)
        // amount mismatch + currency mismatch + missing date = 3 gaps; 2 per turn
        let draft = BillDraft(
            id: id, amount: dec("10"), currencyCode: "EUR", date: nil, categoryRaw: "food",
            lineItems: [DraftLineItem(label: "Espresso", amount: dec("6.5"))], source: .photo
        )
        guard case .askQuestions(let qs1, _, let r1)? = s.completeExtraction(cardID: id, draft: draft).first else {
            return XCTFail("expected round 1")
        }
        XCTAssertEqual(r1, 1)
        XCTAssertEqual(qs1.count, 2)
        var last: [SessionEffect] = []
        for q in qs1 { last = s.answer(cardID: id, field: q.field, value: q.options[0].value) }
        guard case .askQuestions(_, _, let r2)? = last.first else { return XCTFail("expected round 2") }
        XCTAssertEqual(r2, 2)
    }

    func testSkipCarriesGapsAndConfirmNeedsAcknowledgment() throws {
        var s = RecordingSession(validator: makeValidator())
        let id = s.enqueue(source: .text)
        _ = s.beginExtraction(cardID: id)
        let draft = BillDraft(id: id, amount: dec("1850"), currencyCode: "JPY", date: nil, categoryRaw: "food", source: .text)
        _ = s.completeExtraction(cardID: id, draft: draft)
        XCTAssertEqual(s.skipClarification(cardID: id), [.readyForReview(cardID: id)])
        XCTAssertNil(s.card(id)?.draft.date, "skip must not backfill a date")
        XCTAssertEqual(s.card(id)?.carriedGaps, [.date])
        XCTAssertThrowsError(try s.confirm(cardID: id)) { XCTAssertEqual($0 as? ConfirmError, .needsAcknowledgment) }
        XCTAssertEqual(try s.confirm(cardID: id, acknowledging: true), .persist(cardID: id))
    }

    func testMissingAmountCanNeverConfirm() {
        var s = RecordingSession(validator: makeValidator())
        let id = s.enqueue(source: .voice)
        _ = s.beginExtraction(cardID: id)
        let draft = BillDraft(id: id, amount: nil, currencyCode: "JPY", date: Date(), categoryRaw: "transport", source: .voice)
        _ = s.completeExtraction(cardID: id, draft: draft)
        XCTAssertEqual(s.card(id)?.state, .review)
        XCTAssertThrowsError(try s.confirm(cardID: id, acknowledging: true)) {
            XCTAssertEqual($0 as? ConfirmError, .amountRequired)
        }
    }

    func testExtractionFailureIsRetryable() {
        var s = RecordingSession(validator: makeValidator())
        let id = s.enqueue(source: .photo)
        _ = s.beginExtraction(cardID: id)
        XCTAssertEqual(s.failExtraction(cardID: id), .extractionFailed(cardID: id))
        XCTAssertEqual(s.card(id)?.state, .failed)
        XCTAssertTrue(s.retryExtraction(cardID: id))
        XCTAssertEqual(s.card(id)?.state, .extracting)
    }

    func testLLMBudgetIsEnforced() {
        var s = RecordingSession(validator: makeValidator(), llmCallBudget: 2)
        let a = s.enqueue(source: .photo), b = s.enqueue(source: .photo), c = s.enqueue(source: .photo)
        XCTAssertTrue(s.beginExtraction(cardID: a))
        XCTAssertTrue(s.beginExtraction(cardID: b))
        XCTAssertFalse(s.beginExtraction(cardID: c))
        XCTAssertEqual(s.remainingLLMCalls, 0)
    }

    func testDiscardNeverRecords() {
        var s = RecordingSession(validator: makeValidator())
        let id = s.enqueue(source: .photo)
        s.discard(cardID: id)
        XCTAssertEqual(s.card(id)?.state, .discarded)
        XCTAssertTrue(s.recordedCards.isEmpty)
    }
}

// MARK: - File cleanup

final class BillFileCleanupTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testCleanUpRemovesBillImagesAndMindDirButKeepsOthers() {
        let fm = FileManager.default
        let jid = UUID()
        fm.createFile(atPath: root.appendingPathComponent("a.jpg").path, contents: Data("x".utf8))
        fm.createFile(atPath: root.appendingPathComponent("keep.jpg").path, contents: Data("z".utf8))
        let mindDir = root.appendingPathComponent("minds/\(jid.uuidString)", isDirectory: true)
        try? fm.createDirectory(at: mindDir, withIntermediateDirectories: true)
        fm.createFile(atPath: mindDir.appendingPathComponent("mind.jpg").path, contents: Data("m".utf8))

        BillFileCleanup.cleanUp(billImagePaths: ["a.jpg"], journalID: jid, in: root)

        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("a.jpg").path))
        XCTAssertTrue(fm.fileExists(atPath: root.appendingPathComponent("keep.jpg").path))
        XCTAssertFalse(fm.fileExists(atPath: mindDir.path))
    }

    func testPathTraversalNamesAreIgnored() {
        let fm = FileManager.default
        let outside = root.appendingPathComponent("outside.jpg")
        fm.createFile(atPath: outside.path, contents: Data("o".utf8))
        BillFileCleanup.removeBillImages(["../outside.jpg"], in: root)
        XCTAssertTrue(fm.fileExists(atPath: outside.path), "a traversal filename must not delete files above the directory")
    }
}
