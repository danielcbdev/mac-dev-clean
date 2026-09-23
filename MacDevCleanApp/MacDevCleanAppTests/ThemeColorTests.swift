import AppKit
import SwiftUI
import XCTest

@testable import MacDevClean

final class ThemeColorTests: XCTestCase {
    private struct Token {
        let name: String
        let color: Color
        let light: UInt32
        let dark: UInt32
    }

    private static let tokens: [Token] = [
        Token(name: "background", color: Theme.background, light: 0xFFFFFF, dark: 0x1C1C1E),
        Token(
            name: "sidebarBackground", color: Theme.sidebarBackground, light: 0xEDEDF0,
            dark: 0x252528),
        Token(name: "cardBackground", color: Theme.cardBackground, light: 0xF7F7F9, dark: 0x232326),
        Token(name: "separator", color: Theme.separator, light: 0xE3E3E7, dark: 0x3A3A3E),
        Token(name: "textPrimary", color: Theme.textPrimary, light: 0x1D1D1F, dark: 0xF2F2F5),
        Token(name: "textSecondary", color: Theme.textSecondary, light: 0x5F5F66, dark: 0xA6A6AC),
        Token(name: "textTertiary", color: Theme.textTertiary, light: 0x76767C, dark: 0x98989E),
        Token(name: "accentFill", color: Theme.accentFill, light: 0x1565E0, dark: 0x3D8CF5),
        Token(name: "accentOn", color: Theme.accentOn, light: 0xFFFFFF, dark: 0x08182C),
        Token(name: "accentText", color: Theme.accentText, light: 0x0F5FD6, dark: 0x7DB8FF),
        Token(name: "accentSoft", color: Theme.accentSoft, light: 0xE8F0FE, dark: 0x16263D),
        Token(name: "success", color: Theme.success, light: 0x16733A, dark: 0x5BD08A),
        Token(
            name: "successBackground", color: Theme.successBackground, light: 0xE4F3E9,
            dark: 0x123324),
        Token(name: "warning", color: Theme.warning, light: 0x8A5300, dark: 0xF2B04A),
        Token(
            name: "warningBackground", color: Theme.warningBackground, light: 0xFBEFDC,
            dark: 0x3A2A10),
        Token(name: "danger", color: Theme.danger, light: 0xB02419, dark: 0xFF7B6E),
        Token(
            name: "dangerBackground", color: Theme.dangerBackground, light: 0xFBE9E7, dark: 0x3B1C18
        ),
        Token(name: "control", color: Theme.control, light: 0xFFFFFF, dark: 0x3A3A3E),
        Token(
            name: "controlSecondary", color: Theme.controlSecondary, light: 0xF2F2F4, dark: 0x2E2E32
        ),
        Token(name: "neutral", color: Theme.neutral, light: 0xEFEFF2, dark: 0x303034),
    ]

    func testEveryTokenMatchesTheSpecHexInBothAppearances() {
        for token in Self.tokens {
            assertHex(token.color, hex: token.light, appearance: .aqua, name: "\(token.name) light")
            assertHex(
                token.color, hex: token.dark, appearance: .darkAqua, name: "\(token.name) dark")
        }
    }

    func testCardBorderIsBlackNinePercentOnLightAndWhiteTwelvePercentOnDark() {
        let light = ColorSupportTests.resolve(Theme.cardBorder, appearance: .aqua)
        XCTAssertEqual(light.redComponent, 0, accuracy: 0.01)
        XCTAssertEqual(light.alphaComponent, 0.09, accuracy: 0.005)

        let dark = ColorSupportTests.resolve(Theme.cardBorder, appearance: .darkAqua)
        XCTAssertEqual(dark.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(dark.alphaComponent, 0.12, accuracy: 0.005)
    }

    func testControlBorderIsBlackFourteenPercentOnLightAndWhiteSixteenPercentOnDark() {
        let light = ColorSupportTests.resolve(Theme.controlBorder, appearance: .aqua)
        XCTAssertEqual(light.alphaComponent, 0.14, accuracy: 0.005)

        let dark = ColorSupportTests.resolve(Theme.controlBorder, appearance: .darkAqua)
        XCTAssertEqual(dark.alphaComponent, 0.16, accuracy: 0.005)
    }

    func testTextDisabledIsDocumentedAsAnApproximationNotASpecValue() {
        // The spec never shows a disabled control on a live screen, and its
        // one demo swatch gives no dark value. This just locks the chosen
        // approximation so nobody swaps it silently.
        let light = ColorSupportTests.resolve(Theme.textDisabled, appearance: .aqua)
        assertComponents(light, hex: 0xA0A0A6, name: "textDisabled light")
        let dark = ColorSupportTests.resolve(Theme.textDisabled, appearance: .darkAqua)
        assertComponents(dark, hex: 0x98989E, name: "textDisabled dark")
    }

    // MARK: - Helpers

    private func assertHex(
        _ color: Color, hex: UInt32, appearance: NSAppearance.Name, name: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let resolved = ColorSupportTests.resolve(color, appearance: appearance)
        assertComponents(resolved, hex: hex, name: name, file: file, line: line)
    }

    private func assertComponents(
        _ resolved: NSColor, hex: UInt32, name: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(
            resolved.redComponent, CGFloat((hex >> 16) & 0xFF) / 255, accuracy: 0.01,
            "\(name) red", file: file, line: line)
        XCTAssertEqual(
            resolved.greenComponent, CGFloat((hex >> 8) & 0xFF) / 255, accuracy: 0.01,
            "\(name) green", file: file, line: line)
        XCTAssertEqual(
            resolved.blueComponent, CGFloat(hex & 0xFF) / 255, accuracy: 0.01,
            "\(name) blue", file: file, line: line)
    }
}
