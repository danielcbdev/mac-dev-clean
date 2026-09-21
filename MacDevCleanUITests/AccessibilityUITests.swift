import XCTest

final class AccessibilityUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testKeyboardCanSelectACandidateAndOpenReview() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--scenario", "mixed-results"]
        app.launch()

        let start = app.buttons["scan.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.click()

        app.descendants(matching: .any)["sidebar.caches"].click()
        let checkbox = app.checkBoxes["candidate.node.modules.select"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 10))
        checkbox.typeKey(.space, modifierFlags: [])

        let review = app.buttons["cleanup.review"]
        XCTAssertTrue(review.isEnabled)
        review.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(app.buttons["cleanup.moveToTrash"].waitForExistence(timeout: 10))
    }
}
