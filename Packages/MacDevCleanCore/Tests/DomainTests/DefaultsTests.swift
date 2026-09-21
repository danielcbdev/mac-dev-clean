import XCTest

import Domain

final class DefaultsTests: XCTestCase {
    func testNoAutomaticScanOrDeletion() {
        let preferences = AppPreferences()
        XCTAssertFalse(preferences.scanOnLaunch)
        XCTAssertEqual(preferences.largeFileThreshold, 1_000_000_000)
        XCTAssertEqual(preferences.language, .system)
        XCTAssertEqual(preferences.retention, .forever)
    }
}
