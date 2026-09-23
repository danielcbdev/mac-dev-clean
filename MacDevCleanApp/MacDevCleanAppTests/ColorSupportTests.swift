import AppKit
import SwiftUI
import XCTest

@testable import MacDevClean

final class ColorSupportTests: XCTestCase {
    func testHexInitializerMatchesComponents() {
        let color = NSColor(hex: 0x1565E0)
        XCTAssertEqual(color.redComponent, CGFloat(0x15) / 255, accuracy: 0.001)
        XCTAssertEqual(color.greenComponent, CGFloat(0x65) / 255, accuracy: 0.001)
        XCTAssertEqual(color.blueComponent, CGFloat(0xE0) / 255, accuracy: 0.001)
        XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.001)
    }

    func testDynamicColorResolvesLightAndDarkSeparately() {
        let color = Color(lightHex: 0xFFFFFF, darkHex: 0x1C1C1E)

        let light = Self.resolve(color, appearance: .aqua)
        XCTAssertEqual(light.redComponent, 1, accuracy: 0.01)

        let dark = Self.resolve(color, appearance: .darkAqua)
        XCTAssertEqual(dark.redComponent, CGFloat(0x1C) / 255, accuracy: 0.01)
    }

    /// Shared by every color test in this target: forces a specific
    /// `NSAppearance` while resolving a dynamic `Color` down to concrete
    /// RGBA, the way AppKit resolves it when actually drawing.
    static func resolve(_ color: Color, appearance name: NSAppearance.Name) -> NSColor {
        let appearance = NSAppearance(named: name)!
        var resolved = NSColor.clear
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        }
        return resolved
    }
}
