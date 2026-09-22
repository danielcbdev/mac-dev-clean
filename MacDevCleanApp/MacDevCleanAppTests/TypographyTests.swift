import SwiftUI
import XCTest

@testable import MacDevClean

final class TypographyTests: XCTestCase {
    func testHeroIsThirtyFourBold() {
        XCTAssertEqual(Typography.hero.size, 34)
        XCTAssertEqual(Typography.hero.weight, .bold)
        XCTAssertFalse(Typography.hero.tabularNumbers)
    }

    func testMetricIsFortyTwoBoldWithTabularDigits() {
        XCTAssertEqual(Typography.metric.size, 42)
        XCTAssertEqual(Typography.metric.weight, .bold)
        XCTAssertTrue(Typography.metric.tabularNumbers)
    }

    func testTitleIsSeventeenSemibold() {
        XCTAssertEqual(Typography.title.size, 17)
        XCTAssertEqual(Typography.title.weight, .semibold)
        XCTAssertFalse(Typography.title.tabularNumbers)
    }

    func testBodyIsThirteenRegular() {
        XCTAssertEqual(Typography.body.size, 13)
        XCTAssertEqual(Typography.body.weight, .regular)
    }

    func testCaptionIsElevenMedium() {
        XCTAssertEqual(Typography.caption.size, 11)
        XCTAssertEqual(Typography.caption.weight, .medium)
    }
}
