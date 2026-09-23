import AppKit
import SwiftUI

extension NSColor {
    /// A solid color from a `0xRRGGBB` value, as the design spec writes its
    /// tokens.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
    }
}

extension Color {
    /// A color that resolves differently under `.aqua` and `.darkAqua` — the
    /// way the design spec pairs a light and a dark value for every token.
    init(light: NSColor, dark: NSColor) {
        self.init(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            })
    }

    /// Convenience for the common case: both sides are solid hex colors.
    init(lightHex: UInt32, darkHex: UInt32, alpha: CGFloat = 1) {
        self.init(
            light: NSColor(hex: lightHex, alpha: alpha),
            dark: NSColor(hex: darkHex, alpha: alpha))
    }
}
