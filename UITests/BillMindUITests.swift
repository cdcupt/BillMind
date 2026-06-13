import XCTest

/// End-to-end UI test driving the real app on the simulator: it creates a
/// journal and adds a manual bill, then verifies the bill is persisted and shown.
/// This exercises the full SwiftUI navigation + SwiftData write path (through the
/// versioned-schema container) that unit tests can't reach.
///
/// The agent capture flow is intentionally not covered here — it has no UI yet
/// (logic + unit tests only). Add agent E2E once the Record tab ships.
final class BillMindUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCreateJournalAndAddBillEndToEnd() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-reset"]
        app.launch()

        // 1. Fresh launch shows the empty Journals state.
        XCTAssertTrue(
            app.staticTexts["No journals yet!"].waitForExistence(timeout: 15),
            "Expected the empty-journals state on a reset launch"
        )

        // 2. Create a journal.
        let newJournal = app.buttons["newJournalButton"]
        XCTAssertTrue(newJournal.waitForExistence(timeout: 5))
        newJournal.tap()

        let nameField = app.textFields["journalNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "New Journal sheet should present a name field")
        nameField.tap()
        nameField.typeText("Osaka Trip")

        app.buttons["createJournalButton"].tap()

        // 3. We navigate into the new journal, which has no bills yet.
        XCTAssertTrue(
            app.staticTexts["No bills yet!"].waitForExistence(timeout: 15),
            "Creating a journal should navigate to its (empty) detail view"
        )

        // 4. Open the add menu and choose manual entry.
        app.buttons["addBillMenu"].tap()
        tapMenuItem(named: "Add Manually", in: app)

        // 5. Fill the bill form.
        let amountField = app.textFields["billAmountField"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 5), "Manual bill form should present an amount field")
        amountField.tap()
        amountField.typeText("2840")

        // Tapping a category also dismisses the decimal keypad.
        app.buttons["Food"].firstMatch.tap()

        let merchantField = app.textFields["billMerchantField"]
        merchantField.tap()
        merchantField.typeText("Ichiran Ramen")

        // Dismiss the keyboard before reaching the Save button.
        app.staticTexts["Add Bill"].firstMatch.tap()

        scrollToAndTap(app.buttons["saveBillButton"], in: app)

        // 6. The bill is persisted and rendered in the journal: merchant + amount.
        XCTAssertTrue(
            app.staticTexts["Ichiran Ramen"].waitForExistence(timeout: 15),
            "Saved bill's merchant should appear in the journal"
        )
        let amountShown = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS '2,840' OR label CONTAINS '2840'")
        ).firstMatch
        XCTAssertTrue(amountShown.waitForExistence(timeout: 5), "Saved bill's amount should appear")

        // 7. The journal's count widget reflects the new bill.
        XCTAssertTrue(
            app.staticTexts["1 bills"].waitForExistence(timeout: 5),
            "Journal bill count should update to 1"
        )

        add(XCTAttachment(screenshot: app.screenshot()))
    }

    // MARK: - Helpers

    /// SwiftUI `Menu` items surface as either `.buttons` or `.menuItems` depending
    /// on the OS; try both so the test is robust across versions.
    private func tapMenuItem(named label: String, in app: XCUIApplication) {
        let asButton = app.buttons[label]
        if asButton.waitForExistence(timeout: 3) {
            asButton.tap()
            return
        }
        let asMenuItem = app.menuItems[label]
        XCTAssertTrue(asMenuItem.waitForExistence(timeout: 3), "Menu item \"\(label)\" not found")
        asMenuItem.tap()
    }

    /// Scroll the form up until the target button is hittable, then tap it.
    private func scrollToAndTap(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Element never appeared")
        var attempts = 0
        while !element.isHittable && attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
        element.tap()
    }
}
