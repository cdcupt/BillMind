import XCTest

/// End-to-end tests for the Record tab agent flow and the first-launch notice.
/// All use the text path (no API key) and `--uitesting-reset` for a clean store.
final class RecordTabUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    // MARK: - Helpers

    private func launchedApp(_ extraArgs: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset"] + extraArgs
        app.launch()
        return app
    }

    private func createJournal(_ app: XCUIApplication, named name: String) {
        let newJournal = app.buttons["newJournalButton"]
        XCTAssertTrue(newJournal.waitForExistence(timeout: 15))
        newJournal.tap()
        let nameField = app.textFields["journalNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)
        app.buttons["createJournalButton"].tap()
        XCTAssertTrue(app.staticTexts["No bills yet!"].waitForExistence(timeout: 15))
    }

    private func openRecordTab(_ app: XCUIApplication) {
        app.tabBars.buttons["Record"].tap()
        XCTAssertTrue(app.textFields["record-input"].waitForExistence(timeout: 10))
    }

    private func type(_ app: XCUIApplication, _ text: String) {
        let input = app.textFields["record-input"]
        input.tap()
        input.typeText(text)
        app.buttons["record-send"].tap()
    }

    private func openJournalAndAssertBill(_ app: XCUIApplication, journal: String, merchant: String, amountFragment: String) {
        app.tabBars.buttons["Journals"].tap()
        // We may already be in the journal's detail (the create flow navigates
        // there); if not, tap the journal card to open it.
        if !app.staticTexts[merchant].waitForExistence(timeout: 4),
           app.staticTexts[journal].firstMatch.exists {
            app.staticTexts[journal].firstMatch.tap()
        }
        XCTAssertTrue(app.staticTexts[merchant].waitForExistence(timeout: 8),
                      "Saved bill's merchant should appear in the journal")
        let amount = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", amountFragment)
        ).firstMatch
        XCTAssertTrue(amount.waitForExistence(timeout: 5), "Saved bill's amount should appear")
    }

    // MARK: - 1. Happy / clarify + category correction

    @MainActor
    func testRecordTextAnswerDateChangeCategorySaves() throws {
        let app = launchedApp()
        createJournal(app, named: "Osaka Trip")
        openRecordTab(app)

        type(app, "ramen 2840")

        // Card asks for the missing date — answer with the Today chip.
        XCTAssertTrue(app.buttons["clarify-Today"].waitForExistence(timeout: 10))
        app.buttons["clarify-Today"].tap()

        // Change the category via the edit drawer (recognition guessed Food → Transport).
        app.buttons["card-category"].tap()
        let transport = app.buttons["drawer-cat-transport"]
        XCTAssertTrue(transport.waitForExistence(timeout: 5))
        transport.tap()

        // Save the (now complete) card.
        let save = app.buttons["card-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        openJournalAndAssertBill(app, journal: "Osaka Trip", merchant: "Ramen", amountFragment: "2,840")
    }

    // MARK: - 2. Missing amount is blocked until entered (3-step)

    @MainActor
    func testMissingAmountBlockedUntilEntered() throws {
        let app = launchedApp()
        createJournal(app, named: "Kyoto Trip")
        openRecordTab(app)

        type(app, "ramen")    // no number → amount missing

        XCTAssertTrue(app.buttons["clarify-Today"].waitForExistence(timeout: 10))
        app.buttons["clarify-Today"].tap()

        // The card is in review but blocked: Save shows "Enter amount to save" and
        // tapping it opens the amount drawer rather than persisting.
        let save = app.buttons["card-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        let amountField = app.textFields["drawer-amount-field"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 5), "Tapping save with no amount should open the amount drawer")
        amountField.tap()
        amountField.typeText("980")
        app.buttons["drawer-set"].tap()

        // Now it persists.
        XCTAssertTrue(app.buttons["card-save"].waitForExistence(timeout: 5))
        app.buttons["card-save"].tap()

        openJournalAndAssertBill(app, journal: "Kyoto Trip", merchant: "Ramen", amountFragment: "980")
    }

    // MARK: - 3. Discard never reaches the journal

    @MainActor
    func testDiscardDoesNotPersist() throws {
        let app = launchedApp()
        createJournal(app, named: "Nara Trip")
        openRecordTab(app)

        type(app, "coffee 600")
        let discard = app.buttons["card-discard"]
        XCTAssertTrue(discard.waitForExistence(timeout: 10))
        discard.tap()

        app.tabBars.buttons["Journals"].tap()
        if !app.staticTexts["No bills yet!"].waitForExistence(timeout: 4),
           app.staticTexts["Nara Trip"].firstMatch.exists {
            app.staticTexts["Nara Trip"].firstMatch.tap()
        }
        XCTAssertTrue(app.staticTexts["No bills yet!"].waitForExistence(timeout: 8),
                      "A discarded card must not create a bill")
    }

    // MARK: - 4. First-launch notice shows once

    @MainActor
    func testFirstLaunchNoticeShowsOnce() throws {
        // Force the notice on this launch.
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset", "--uitesting-show-notice"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome to BillMind"].waitForExistence(timeout: 10))
        app.buttons["welcome-get-started"].tap()
        XCTAssertFalse(app.staticTexts["Welcome to BillMind"].waitForExistence(timeout: 2))

        // Relaunch with NO show-notice arg → the persisted flag suppresses it.
        app.terminate()
        let relaunch = XCUIApplication()
        relaunch.launchArguments = []
        relaunch.launch()
        XCTAssertFalse(relaunch.staticTexts["Welcome to BillMind"].waitForExistence(timeout: 5),
                       "The notice must not reappear after Get started")
    }
}
