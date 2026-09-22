import XCTest

/// Walks every destination and checks that the sidebar survives the trip.
///
/// This suite is the one that would have caught D2, D3 and D5, and it is the
/// one that has never run: XCUITest does not launch an inspectable app on the
/// development machine. It is written to run on CI. Until it has, every
/// assertion here is a claim about what should happen, not evidence that it
/// does — see docs/verification/10-defects.md.
final class NavigationUITests: XCTestCase {
    private static let destinations = [
        "sidebar.overview",
        "sidebar.caches",
        "sidebar.largeFiles",
        "sidebar.history",
        "sidebar.exclusions",
        "sidebar.settings",
    ]

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--scenario", "mixed-results"]
        app.launch()
        return app
    }

    /// The defect in one assertion: after visiting a destination, can the user
    /// still leave it?
    func testTheSidebarSurvivesVisitingEveryDestination() {
        let app = launch()
        XCTAssertTrue(
            app.buttons["sidebar.overview"].waitForExistence(timeout: 10)
                || app.staticTexts["sidebar.overview"].waitForExistence(timeout: 1),
            "the sidebar is not present at launch")

        for identifier in Self.destinations {
            app.descendants(matching: .any)[identifier].firstMatch.click()

            for other in Self.destinations {
                XCTAssertTrue(
                    app.descendants(matching: .any)[other].firstMatch.exists,
                    "\(other) left the sidebar after visiting \(identifier)")
            }
        }
    }

    /// Large Files was offered for four milestones while showing a message
    /// saying it did not exist. Nothing may say that again.
    func testLargeFilesOpensItsOwnScreenAndNotAPlaceholder() {
        let app = launch()
        XCTAssertTrue(
            app.descendants(matching: .any)["sidebar.largeFiles"]
                .firstMatch.waitForExistence(timeout: 10))
        app.descendants(matching: .any)["sidebar.largeFiles"].firstMatch.click()

        XCTAssertTrue(
            app.descendants(matching: .any)["largeFiles.choose"]
                .firstMatch.waitForExistence(timeout: 5),
            "Large Files did not open its own screen")
        XCTAssertFalse(
            app.descendants(matching: .any)["upcoming.largeFiles"].firstMatch.exists,
            "a built feature is still advertising itself as missing")
    }

    /// The Caches toolbar overflowed the window minimum: its controls were
    /// laid out above the top edge. Every one of them must be inside the
    /// window.
    func testTheCachesToolbarFitsInsideTheMinimumWindow() {
        let app = launch()
        XCTAssertTrue(
            app.descendants(matching: .any)["sidebar.caches"]
                .firstMatch.waitForExistence(timeout: 10))
        app.descendants(matching: .any)["sidebar.caches"].firstMatch.click()

        let window = app.windows.firstMatch
        let controls = [
            "filter.ecosystem", "filter.risk", "filter.sort", "selection.selectAll",
        ]
        for identifier in controls {
            let control = app.descendants(matching: .any)[identifier].firstMatch
            XCTAssertTrue(
                control.waitForExistence(timeout: 5), "\(identifier) is missing")
            XCTAssertTrue(
                window.frame.contains(control.frame),
                "\(identifier) at \(control.frame) is outside the window \(window.frame)")
        }
    }
}
