import XCTest

@testable import MacDevClean

@MainActor
final class LaunchTests: XCTestCase {
    func testCompositionRootDefaultsToProductionMode() {
        let dependencies = AppDependencies.live(arguments: ["/path/to/MacDevClean"])

        XCTAssertFalse(dependencies.isUITesting)
    }

    func testCompositionRootDetectsTheUITestingLaunchArgument() {
        let dependencies = AppDependencies.live(
            arguments: ["/path/to/MacDevClean", "--ui-testing"]
        )

        XCTAssertTrue(dependencies.isUITesting)
    }

    func testBundleTargetsTheSupportedMinimumSystemVersion() throws {
        let bundle = Bundle(for: LaunchTests.self)
        let minimum = try XCTUnwrap(
            bundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String
        )

        XCTAssertEqual(minimum, "14.0")
    }
}
