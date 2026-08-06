import XCTest

/// End-to-end tests for the Record capture flow + the first-launch notice, on the
/// Voyage 4-tab structure. All use the text path (local DraftExtractor, no server)
/// and the DEBUG signed-in bypass for a clean, gated launch. Persistence is
/// verified via the journal chip's live bill count ("1 bill in trip · …") — a
/// saved card leaves the input immediately by design, so the chip's tick-up is
/// the observable proof the save landed.
final class RecordTabUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    // MARK: - Helpers

    private func launchedApp(_ extraArgs: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset", "--uitesting-signedin"] + extraArgs
        app.launch()
        return app
    }

    /// Create a trip from the Record empty state; lands on its capture surface.
    private func createTrip(_ app: XCUIApplication, named name: String) {
        let create = app.buttons["record-create-journal"]
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        create.tap()
        let nameField = app.textFields["journalNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)
        app.buttons["createJournalButton"].tap()
        XCTAssertTrue(app.textFields["record-input"].waitForExistence(timeout: 15),
                      "Creating a trip should open its Record capture surface")
    }

    private func type(_ app: XCUIApplication, _ text: String) {
        let input = app.textFields["record-input"]
        input.tap()
        input.typeText(text)
        app.buttons["record-send"].tap()
    }

    /// The journal chip's bill count proves persistence without leaving Record:
    /// it reads the journal's live bills, so it only ticks up when a BillRecord
    /// was actually written. Matched by label prefix (the suffix carries the
    /// journal currency, which varies with the device locale default).
    private func recordedChip(_ app: XCUIApplication, count: Int = 1) -> XCUIElement {
        let label = count == 1 ? "1 bill in trip" : "\(count) bills in trip"
        let predicate = NSPredicate(format: "label CONTAINS %@", label)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    private func assertRecorded(_ app: XCUIApplication, count: Int = 1) {
        XCTAssertTrue(recordedChip(app, count: count).waitForExistence(timeout: 10),
                      "The journal chip should show \(count) recorded bill(s)")
    }

    // MARK: - 1. Happy / category correction (date defaults to today, no clarify)

    @MainActor
    func testRecordTextAnswerDateChangeCategorySaves() throws {
        let app = launchedApp()
        createTrip(app, named: "Osaka Trip")

        type(app, "ramen 2840")

        // No date stated → defaults to today (no clarify); change the category.
        let categoryButton = app.buttons["card-category"]
        XCTAssertTrue(categoryButton.waitForExistence(timeout: 10))
        categoryButton.tap()
        let transport = app.buttons["drawer-cat-transport"]
        XCTAssertTrue(transport.waitForExistence(timeout: 5))
        transport.tap()

        // Save the (now complete) card.
        let save = app.buttons["card-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        assertRecorded(app)
    }

    // MARK: - 2. Missing amount is blocked until entered

    @MainActor
    func testMissingAmountBlockedUntilEntered() throws {
        let app = launchedApp()
        createTrip(app, named: "Kyoto Trip")

        type(app, "ramen")    // no number → amount missing (date defaults to today)

        // Tapping save with no amount opens the amount drawer instead of persisting.
        let save = app.buttons["card-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()

        let amountField = app.textFields["drawer-amount-field"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 5), "Tapping save with no amount should open the amount drawer")
        XCTAssertFalse(recordedChip(app).exists, "A no-amount card must not persist on the blocked save")
        amountField.tap()
        amountField.typeText("980")
        app.buttons["drawer-set"].tap()

        // Now it persists.
        XCTAssertTrue(app.buttons["card-save"].waitForExistence(timeout: 5))
        app.buttons["card-save"].tap()
        assertRecorded(app)
    }

    // MARK: - 3. Discard removes the card (never persists)

    @MainActor
    func testDiscardDoesNotPersist() throws {
        let app = launchedApp()
        createTrip(app, named: "Nara Trip")

        type(app, "coffee 600")
        let discard = app.buttons["card-discard"]
        XCTAssertTrue(discard.waitForExistence(timeout: 10))
        discard.tap()

        // The discarded card (and its save button) is gone; nothing recorded.
        XCTAssertFalse(app.buttons["card-save"].waitForExistence(timeout: 3),
                       "A discarded card must be removed")
        XCTAssertFalse(recordedChip(app).exists, "A discarded card must not persist")
    }

    // MARK: - 3b. Voice mic toggle must not crash (regression)

    /// Tapping the mic used to trap on a background queue: a @MainActor closure
    /// passed to the Speech/AVFoundation permission callbacks inherited MainActor
    /// isolation but was invoked off-main (EXC_BREAKPOINT in the TCC callback).
    /// This taps the mic, auto-allows the permission alerts so the completion
    /// callbacks actually fire, and asserts the app is still alive.
    @MainActor
    func testVoiceMicButtonDoesNotCrash() throws {
        let app = launchedApp()
        createTrip(app, named: "Voice Trip")

        addUIInterruptionMonitor(withDescription: "speech + mic permission") { alert in
            for label in ["Allow", "OK", "Allow While Using App"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }

        let mic = app.buttons["record-mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 10))
        mic.tap()

        // Nudge the run loop so the interruption monitor can dismiss any alert,
        // which is what fires the permission completion callbacks.
        app.tap()
        sleep(2)

        XCTAssertEqual(app.state, .runningForeground,
                       "Tapping the mic must not crash the app")
        XCTAssertTrue(app.textFields["record-input"].waitForExistence(timeout: 5),
                      "The Record input bar should still be present after toggling voice")
    }

    // MARK: - 3c. Amount drawer pre-fills the card's current amount (PR #19 regression)

    /// Tapping a card's existing amount opens the "Enter amount" drawer pre-filled
    /// with that amount — a correction edits the value rather than re-typing from
    /// an empty "0.00". Captures before/after screenshots for the E2E report.
    @MainActor
    func testAmountDrawerPrefillsCurrentValue() throws {
        let app = launchedApp()
        createTrip(app, named: "Prefill Trip")

        type(app, "ramen 2840")

        // The review card shows its amount; tap it to open the amount drawer.
        let amount = app.buttons["card-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10), "Card should render a tappable amount")
        amount.tap()

        let field = app.textFields["drawer-amount-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Tapping the amount should open the amount drawer")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "amount-drawer-prefilled"
        shot.lifetime = .keepAlways
        add(shot)

        // The drawer must be seeded with the card's current amount (2840), not empty.
        let value = (field.value as? String) ?? ""
        XCTAssertTrue(value.contains("2840"),
                      "Amount drawer should pre-fill the card's current amount, got '\(value)'")
        XCTAssertNotEqual(value, "0.00", "Amount drawer must not open empty")
    }

    // MARK: - 4. First-launch notice shows once

    @MainActor
    func testFirstLaunchNoticeShowsOnce() throws {
        // Force the notice on this (signed-in) launch.
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset", "--uitesting-signedin", "--uitesting-show-notice"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome to BillOwl"].waitForExistence(timeout: 10))
        app.buttons["welcome-get-started"].tap()
        XCTAssertFalse(app.staticTexts["Welcome to BillOwl"].waitForExistence(timeout: 2))

        // Relaunch signed-in WITHOUT reset/show-notice → the persisted flag suppresses it.
        app.terminate()
        let relaunch = XCUIApplication()
        relaunch.launchArguments = ["--uitesting-signedin"]
        relaunch.launch()
        XCTAssertFalse(relaunch.staticTexts["Welcome to BillOwl"].waitForExistence(timeout: 5),
                       "The notice must not reappear after Get started")
    }
}
