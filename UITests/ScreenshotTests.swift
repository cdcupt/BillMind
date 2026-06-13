import XCTest

/// Drives the Record-tab flow and attaches screenshots of the key states for the
/// E2E report. Not an assertion test — a capture harness.
final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func grab(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testCaptureRecordFlow() throws {
        // 1. First-launch welcome notice.
        let welcome = XCUIApplication()
        welcome.launchArguments = ["--uitesting-reset", "--uitesting-show-notice"]
        welcome.launch()
        XCTAssertTrue(welcome.staticTexts["Welcome to BillMind"].waitForExistence(timeout: 10))
        grab(welcome, "01-welcome-notice")
        welcome.buttons["welcome-get-started"].tap()

        // Create a journal, then open the Record tab.
        welcome.buttons["newJournalButton"].tap()
        let nameField = welcome.textFields["journalNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap(); nameField.typeText("Osaka Trip")
        welcome.buttons["createJournalButton"].tap()
        XCTAssertTrue(welcome.staticTexts["No bills yet!"].waitForExistence(timeout: 15))

        welcome.tabBars.buttons["Record"].tap()
        XCTAssertTrue(welcome.textFields["record-input"].waitForExistence(timeout: 10))
        grab(welcome, "02-record-empty")

        // 2. Type a bill → card mid-clarify (date chips).
        let input = welcome.textFields["record-input"]
        input.tap(); input.typeText("ramen 2840")
        welcome.buttons["record-send"].tap()
        XCTAssertTrue(welcome.buttons["clarify-Today"].waitForExistence(timeout: 10))
        grab(welcome, "03-card-clarify")

        // 3. Edit drawer — category grid.
        welcome.buttons["card-category"].tap()
        XCTAssertTrue(welcome.buttons["drawer-cat-transport"].waitForExistence(timeout: 5))
        grab(welcome, "04-edit-drawer-category")
        welcome.buttons["drawer-cat-transport"].tap()

        // Answer the date and save.
        welcome.buttons["clarify-Today"].tap()
        let save = welcome.buttons["card-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        grab(welcome, "05-card-ready")
        save.tap()

        // 4. Saved bill in the journal.
        welcome.tabBars.buttons["Journals"].tap()
        XCTAssertTrue(welcome.staticTexts["Ramen"].waitForExistence(timeout: 10))
        grab(welcome, "06-bill-in-journal")
    }
}
