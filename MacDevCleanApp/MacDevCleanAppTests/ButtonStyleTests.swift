import XCTest

@testable import MacDevClean

final class ButtonStyleTests: XCTestCase {
    func testPrimaryMetricsMatchSpec() {
        XCTAssertEqual(PrimaryButtonStyle.height, 32)
        // The spec pads primary buttons 18pt horizontally — a one-off, not
        // on the 4/8/12/16/20/24/32 spacing scale.
        XCTAssertEqual(PrimaryButtonStyle.horizontalPadding, 18)
    }

    func testSecondaryMetricsMatchSpec() {
        XCTAssertEqual(SecondaryButtonStyle.height, 32)
        XCTAssertEqual(SecondaryButtonStyle.horizontalPadding, 16)
    }

    func testDestructiveMetricsMatchSpec() {
        XCTAssertEqual(DestructiveButtonStyle.height, 32)
        XCTAssertEqual(DestructiveButtonStyle.horizontalPadding, 16)
    }
}
