import AppKit
import Domain
import SwiftUI
import XCTest

@testable import MacDevClean

final class RiskBadgeTests: XCTestCase {
    func testTitlesAreUnchanged() {
        let english = Locale(identifier: "en")
        XCTAssertEqual(RiskBadge.title(.low, locale: english), "Low risk")
        XCTAssertEqual(RiskBadge.title(.medium, locale: english), "Medium risk")
        XCTAssertEqual(RiskBadge.title(.high, locale: english), "High risk")
    }

    func testSymbolsMatchTheSpecShapes() {
        XCTAssertEqual(RiskBadge.symbol(.low), "checkmark.shield")
        XCTAssertEqual(RiskBadge.symbol(.medium), "exclamationmark.triangle")
        // The spec's high-risk icon is a circle with an exclamation mark, not
        // an octagon — deliberately changed from the prior implementation to
        // match it exactly.
        XCTAssertEqual(RiskBadge.symbol(.high), "exclamationmark.circle")
    }

    func testEachRiskLevelUsesItsOwnTokenPairNotAnother() {
        let pairs: [(RiskLevel, Color, Color)] = [
            (.low, Theme.success, Theme.successBackground),
            (.medium, Theme.warning, Theme.warningBackground),
            (.high, Theme.danger, Theme.dangerBackground),
        ]
        for (risk, expectedForeground, expectedBackground) in pairs {
            let foreground = ColorSupportTests.resolve(
                RiskBadge.foreground(risk), appearance: .aqua)
            let expectedFg = ColorSupportTests.resolve(expectedForeground, appearance: .aqua)
            XCTAssertEqual(foreground, expectedFg, "\(risk) foreground")

            let background = ColorSupportTests.resolve(
                RiskBadge.background(risk), appearance: .aqua)
            let expectedBg = ColorSupportTests.resolve(expectedBackground, appearance: .aqua)
            XCTAssertEqual(background, expectedBg, "\(risk) background")
        }
    }
}
