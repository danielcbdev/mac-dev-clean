import XCTest

/// Large Files, driven through the real interface against a temporary folder
/// the process created for itself.
final class LargeFilesUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testNothingIsScannedUntilAFolderIsChosen() {
        let app = Self.launch()

        app.descendants(matching: .any)["sidebar.largeFiles"].click()

        XCTAssertTrue(app.buttons["largeFiles.choose"].waitForExistence(timeout: 10))
        XCTAssertFalse(
            app.otherElements["largeFiles.results"].exists,
            "Large Files looks only where it is pointed")
    }

    func testLargeFilesRequireSelectionAndReview() {
        let app = Self.launch()
        app.descendants(matching: .any)["sidebar.largeFiles"].click()

        app.buttons["largeFiles.choose"].click()
        XCTAssertTrue(
            app.descendants(matching: .any)["largeFiles.results"]
                .waitForExistence(timeout: 15))

        let review = app.buttons["largeFiles.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        XCTAssertFalse(review.isEnabled, "a scan selects nothing")

        let checkbox = app.checkBoxes.matching(
            NSPredicate(format: "identifier BEGINSWITH 'largeFile.'")
        ).firstMatch
        XCTAssertTrue(checkbox.waitForExistence(timeout: 10))
        checkbox.click()

        XCTAssertTrue(review.isEnabled)
        review.click()

        // Large files are high risk, so the shared review demands an
        // acknowledgment before anything can happen.
        XCTAssertTrue(
            app.buttons["cleanup.irreversible.review"].waitForExistence(timeout: 10))
    }

    func testTheFooterWarnsThatBigDoesNotMeanDisposable() {
        let app = Self.launch()
        app.descendants(matching: .any)["sidebar.largeFiles"].click()

        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "value CONTAINS[c] 'not necessarily disposable'")
            ).firstMatch.waitForExistence(timeout: 10)
                || app.staticTexts[
                    "Large files are not necessarily disposable. Review their contents before "
                        + "moving them to the Trash."
                ].waitForExistence(timeout: 10)
        )
    }

    private static func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--scenario", "large-files"]
        app.launch()
        return app
    }
}
