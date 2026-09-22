import XCTest

final class LocalizationUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testPortugueseOverviewReviewActionIsTranslated() {
        let app = launch(language: "pt-BR", locale: "pt_BR")

        let review = app.buttons["cleanup.reviewFromOverview"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        XCTAssertEqual(review.label, "Revisar limpeza")
    }

    func testEnglishOverviewReviewActionIsTranslated() {
        let app = launch(language: "en", locale: "en_US")

        let review = app.buttons["cleanup.reviewFromOverview"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        XCTAssertEqual(review.label, "Review cleanup")
    }

    private func launch(language: String, locale: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--scenario", "mixed-results",
            "-AppleLanguages", "(\(language))", "-AppleLocale", locale,
        ]
        app.launch()
        app.activate()
        return app
    }
}
