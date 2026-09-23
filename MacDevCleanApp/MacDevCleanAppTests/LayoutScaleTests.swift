import XCTest

@testable import MacDevClean

final class LayoutScaleTests: XCTestCase {
    func testSpacingScaleMatchesSpec() {
        XCTAssertEqual(Layout.space4, 4)
        XCTAssertEqual(Layout.space8, 8)
        XCTAssertEqual(Layout.space12, 12)
        XCTAssertEqual(Layout.space16, 16)
        XCTAssertEqual(Layout.space20, 20)
        XCTAssertEqual(Layout.space24, 24)
        XCTAssertEqual(Layout.space32, 32)
    }

    func testRadiusScaleMatchesSpec() {
        XCTAssertEqual(Layout.cardRadius, 12)
        XCTAssertEqual(Layout.controlRadius, 8)
        XCTAssertEqual(Layout.badgeRadius, 6)
    }
}
