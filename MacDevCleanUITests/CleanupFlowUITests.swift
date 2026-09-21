import XCTest

/// The scan → select → review → confirm flow, driven through the real
/// interface against fixture data.
///
/// Every destructive adapter behind this is a fake: the Trash records and moves
/// nothing, Docker is in memory, and the artifacts live in a temporary tree the
/// process created for itself.
final class CleanupFlowUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Selection

    func testSelectionEnablesReview() {
        let app = Self.launch(scenario: "mixed-results")
        Self.scan(app)

        app.descendants(matching: .any)["sidebar.caches"].click()

        let review = app.buttons["cleanup.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        XCTAssertFalse(review.isEnabled, "nothing is selected after a scan")

        let checkbox = app.checkBoxes["candidate.node.modules.select"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 10))
        checkbox.click()

        XCTAssertTrue(review.isEnabled)
    }

    func testAScanSelectsNothingAndTheOverviewSaysWhatItFound() {
        let app = Self.launch(scenario: "mixed-results")
        Self.scan(app)

        let status = app.staticTexts["scan.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))

        app.descendants(matching: .any)["sidebar.caches"].click()
        let count = app.staticTexts["selection.count"]
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        XCTAssertTrue(
            count.label.contains("0"), "a scan must not select anything: \(count.label)")
    }

    func testFilteringKeepsSelectionsThatAreNoLongerVisible() {
        let app = Self.launch(scenario: "mixed-results")
        Self.scan(app)
        app.descendants(matching: .any)["sidebar.caches"].click()

        let checkbox = app.checkBoxes["candidate.node.modules.select"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 10))
        checkbox.click()

        let before = app.staticTexts["selection.count"].label

        // Filter to a different ecosystem, so the selected row is not shown.
        let filter = app.popUpButtons["filter.ecosystem"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.click()
        app.menuItems["Homebrew cache"].click()

        XCTAssertEqual(
            app.staticTexts["selection.count"].label, before,
            "changing a filter must not change what is selected")
        XCTAssertTrue(app.buttons["cleanup.review"].isEnabled)
    }

    func testBulkSelectionNeverReachesHighRiskItems() {
        let app = Self.launch(scenario: "docker-volume")
        Self.scan(app)
        app.descendants(matching: .any)["sidebar.caches"].click()

        let selectAll = app.buttons["selection.selectAll"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 10))
        selectAll.click()

        let volume = app.checkBoxes["docker.volume.select"]
        if volume.exists {
            XCTAssertEqual(
                volume.value as? Int, 0,
                "a bulk action must never select something irreversible")
        }
    }

    // MARK: - Irreversible confirmation

    func testDockerVolumeRequiresAcknowledgment() {
        let app = Self.launch(scenario: "docker-volume")
        Self.scan(app)
        app.descendants(matching: .any)["sidebar.caches"].click()

        let details = app.descendants(matching: .any)["docker.volume.details"]
        XCTAssertTrue(details.waitForExistence(timeout: 10))
        details.click()

        let volume = app.checkBoxes["docker.volume.select"]
        XCTAssertTrue(volume.waitForExistence(timeout: 10))
        volume.click()

        app.buttons["cleanup.review"].click()
        let irreversible = app.buttons["cleanup.irreversible.review"]
        XCTAssertTrue(irreversible.waitForExistence(timeout: 10))
        irreversible.click()

        let confirm = app.buttons["cleanup.permanentlyRemove"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        XCTAssertFalse(confirm.isEnabled)

        app.checkBoxes["cleanup.irreversible.ack"].click()
        app.checkBoxes["cleanup.highRisk.ack"].click()

        XCTAssertTrue(confirm.isEnabled)
    }

    // MARK: - Completing a cleanup against fakes

    func testConfirmingMovesItemsAndExplainsWhatHappened() {
        let app = Self.launch(scenario: "mixed-results")
        Self.scan(app)
        app.descendants(matching: .any)["sidebar.caches"].click()

        let checkbox = app.checkBoxes["candidate.node.modules.select"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 10))
        checkbox.click()
        app.buttons["cleanup.review"].click()

        let confirm = app.buttons["cleanup.moveToTrash"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.click()

        XCTAssertTrue(app.staticTexts["results.bytesMoved"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["results.openTrash"].exists)
        // The results screen must say space is not yet freed.
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "value CONTAINS[c] 'Empty the Trash'")
            ).firstMatch.exists
                || app.staticTexts["Moved to Trash. Empty the Trash in Finder to reclaim space."]
                    .exists,
            "the results must not imply space was reclaimed")
    }

    // MARK: - Visual evidence

    func testCaptureReferenceScreens() {
        let app = Self.launch(scenario: "mixed-results")
        Self.scan(app)

        add(Self.screenshot(app, named: "overview"))

        app.descendants(matching: .any)["sidebar.caches"].click()
        _ = app.buttons["cleanup.review"].waitForExistence(timeout: 10)
        add(Self.screenshot(app, named: "caches"))
    }

    // MARK: - Helpers

    private static func launch(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--scenario", scenario]
        app.launch()
        return app
    }

    private static func scan(_ app: XCUIApplication) {
        let start = app.buttons["scan.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.click()
        // The scan finishes when the start button offers a rescan again.
        let finished = NSPredicate(format: "exists == true AND isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: finished, object: start)
        _ = XCTWaiter.wait(for: [expectation], timeout: 30)
    }

    private static func screenshot(_ app: XCUIApplication, named name: String) -> XCTAttachment {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        return attachment
    }
}
