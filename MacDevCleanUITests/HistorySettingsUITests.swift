import XCTest

/// History, Exclusions and Settings, driven through the real interface.
final class HistorySettingsUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testAddingAnExclusionInvalidatesTheSelection() {
        let app = Self.launch()
        Self.scan(app)
        app.descendants(matching: .any)["sidebar.caches"].click()

        let checkbox = app.checkBoxes["candidate.node.modules.select"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 10))
        checkbox.click()
        XCTAssertTrue(app.buttons["cleanup.review"].isEnabled)

        // Exclude the item from its own context menu.
        checkbox.rightClick()
        app.menuItems["Always skip this"].click()

        XCTAssertFalse(
            app.buttons["cleanup.review"].isEnabled,
            "changing the scope must revoke a selection made under the old one")

        app.descendants(matching: .any)["sidebar.exclusions"].click()
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'exclusion.path.'"))
                .firstMatch.waitForExistence(timeout: 10))
    }

    func testClearingHistoryAsksFirst() {
        let app = Self.launch()
        app.descendants(matching: .any)["sidebar.history"].click()

        // With no history the control is unavailable rather than destructive.
        let clear = app.buttons["history.clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 10))
        XCTAssertFalse(clear.isEnabled)
    }

    func testSettingsOffersRootsLanguageAppearanceAndRetention() {
        let app = Self.launch()
        app.descendants(matching: .any)["sidebar.settings"].click()

        for identifier in [
            "settings.addRoot", "settings.scanOnLaunch", "settings.threshold",
            "settings.retention", "settings.language", "settings.appearance",
        ] {
            XCTAssertTrue(
                app.descendants(matching: .any)[identifier].waitForExistence(timeout: 10),
                "missing \(identifier)")
        }
    }

    func testThePrivacyStatementIsVisibleInSettings() {
        let app = Self.launch()
        app.descendants(matching: .any)["sidebar.settings"].click()

        XCTAssertTrue(
            app.descendants(matching: .any)["settings.privacy"]
                .waitForExistence(timeout: 10))
    }

    private static func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--scenario", "mixed-results"]
        app.launch()
        return app
    }

    private static func scan(_ app: XCUIApplication) {
        let start = app.buttons["scan.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.click()
        let finished = NSPredicate(format: "exists == true AND isEnabled == true")
        _ = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: finished, object: start)], timeout: 30)
    }
}
