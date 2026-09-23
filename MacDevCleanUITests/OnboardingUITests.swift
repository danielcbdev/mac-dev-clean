import XCTest

/// First-run behaviour, driven through the real interface.
///
/// The folder picker is a fake that returns a synthetic root. This is not an
/// attempt to automate `NSOpenPanel`: the native panel's cancellation and
/// multi-selection are verified by hand and recorded in the verification notes.
final class OnboardingUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testNoScanStartsBeforeRootConsent() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--scenario", "first-run"]
        app.launch()

        XCTAssertTrue(app.buttons["roots.choose"].waitForExistence(timeout: 10))
        XCTAssertFalse(
            app.progressIndicators["scan.progress"].exists,
            "nothing may be scanned before the user accepts a scope")

        app.buttons["roots.choose"].click()
        app.buttons["roots.confirm"].click()

        XCTAssertTrue(app.buttons["scan.start"].waitForExistence(timeout: 10))
        XCTAssertFalse(
            app.progressIndicators["scan.progress"].exists,
            "accepting a scope must not start a scan on its own")
    }

    func testConfirmationStaysDisabledUntilSomethingIsChosen() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--scenario", "first-run"]
        app.launch()

        XCTAssertTrue(app.buttons["roots.confirm"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["roots.confirm"].isEnabled)

        app.buttons["roots.choose"].click()

        XCTAssertTrue(app.buttons["roots.confirm"].isEnabled)
    }

    func testTheSidebarOffersEveryDestinationAfterOnboarding() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--scenario", "mixed-results"]
        app.launch()

        for identifier in [
            "sidebar.overview", "sidebar.caches", "sidebar.largeFiles",
            "sidebar.history", "sidebar.exclusions", "sidebar.settings",
        ] {
            XCTAssertTrue(
                app.descendants(matching: .any)[identifier].waitForExistence(timeout: 10),
                "missing \(identifier)")
        }
    }
}
