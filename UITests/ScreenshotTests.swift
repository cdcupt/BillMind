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
        app.buttons["createJournalButton"].tap()

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
}
