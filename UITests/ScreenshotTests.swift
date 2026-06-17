import XCTest

/// Drives the Voyage Record flow and attaches screenshots of the key states for
/// the E2E report. A capture harness — assertions are kept light + tolerant.
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
        // Signed-in shell + force the first-launch welcome notice.
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset", "--uitesting-signedin", "--uitesting-show-notice"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Welcome to BillMind"].waitForExistence(timeout: 10))
        grab(app, "01-welcome-notice")
        app.buttons["welcome-get-started"].tap()

        // Record home → create a trip from the empty state.
        let create = app.buttons["record-create-journal"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()
        let nameField = app.textFields["journalNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap(); nameField.typeText("Osaka Trip")
        // Dismiss the keyboard so the bottom "Create Trip" button is reachable on tall devices (Pro Max).
        if app.keyboards.element.waitForExistence(timeout: 2) { app.swipeUp() }
        let createBtn = app.buttons["createJournalButton"]
        XCTAssertTrue(createBtn.waitForExistence(timeout: 10))
        if !createBtn.isHittable { app.swipeUp() }
        createBtn.tap()

        // The trip's capture surface.
        let input = app.textFields["record-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        grab(app, "02-record-capture")

        // Type a bill → a card appears (best-effort clarify/screenshot).
        input.tap(); input.typeText("ramen 2840")
        app.buttons["record-send"].tap()
        _ = app.buttons["clarify-Today"].waitForExistence(timeout: 10)
        grab(app, "03-card")
    }

    /// Capture the redesigned Minds + trimmed Settings tabs for visual review.
    @MainActor
    func testMindsAndSettingsScreens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset", "--uitesting-signedin"]
        app.launch()

        // Create a trip so the tabs are usable.
        let create = app.buttons["record-create-journal"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()
        let nameField = app.textFields["journalNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap(); nameField.typeText("Osaka Trip")
        // Dismiss the keyboard so the bottom "Create Trip" button is reachable on tall devices (Pro Max).
        if app.keyboards.element.waitForExistence(timeout: 2) { app.swipeUp() }
        let createBtn = app.buttons["createJournalButton"]
        XCTAssertTrue(createBtn.waitForExistence(timeout: 10))
        if !createBtn.isHittable { app.swipeUp() }
        createBtn.tap()
        XCTAssertTrue(app.textFields["record-input"].waitForExistence(timeout: 15))

        app.tabBars.buttons["Minds"].tap()
        XCTAssertTrue(app.staticTexts["Select a Trip"].waitForExistence(timeout: 10))
        grab(app, "04-minds")

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["delete-account"].waitForExistence(timeout: 10))
        grab(app, "05-settings")
    }
}
