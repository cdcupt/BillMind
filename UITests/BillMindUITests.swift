import XCTest

/// End-to-end UI test on the simulator for the BillMind 2.0 (Voyage) structure:
/// it signs in via the DEBUG bypass, lands on the Record home, creates a trip,
/// and captures a bill by text — exercising the auth gate, the 4-tab IA, the
/// create-trip sheet, and the local DraftExtractor capture path (no server).
final class BillMindUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCreateTripAndCaptureEntry() throws {
        let app = XCUIApplication()
        // Reset the store + enter the signed-in shell directly (Sign in with Apple
        // can't complete on the simulator).
        app.launchArguments = ["--uitesting-reset", "--uitesting-signedin"]
        app.launch()

        // 1. Signed in → Record is the home, with the empty-trips state.
        XCTAssertTrue(
            app.staticTexts["No trips yet!"].waitForExistence(timeout: 15),
            "Expected the empty-trips state on the Record home"
        )

        // 2. Create a trip from the Record empty state.
        let create = app.buttons["record-create-journal"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()

        let nameField = app.textFields["journalNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "New Trip sheet should present a name field")
        nameField.tap()
        nameField.typeText("Osaka Trip")
        app.buttons["createJournalButton"].tap()

        // 3. We land on the trip's Record capture surface.
        let input = app.textFields["record-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15), "Creating a trip should open its Record capture surface")

        // 4. Text capture (local, offline) turns a phrase into a card with the amount.
        input.tap()
        input.typeText("ramen 2840")
        app.buttons["record-send"].tap()

        let amountShown = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS '2,840' OR label CONTAINS '2840'")
        ).firstMatch
        XCTAssertTrue(amountShown.waitForExistence(timeout: 10), "The captured card should show the parsed amount")

        add(XCTAttachment(screenshot: app.screenshot()))
    }
}
