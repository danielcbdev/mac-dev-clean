import SwiftUI

/// Color tokens from the approved redesign spec — see
/// `docs/references/redesign/design-tokens.md`. Every token is defined for
/// both `.aqua` and `.darkAqua`; SwiftUI resolves the right one when drawing.
enum Theme {
    static let background = Color(lightHex: 0xFFFFFF, darkHex: 0x1C1C1E)
    static let sidebarBackground = Color(lightHex: 0xEDEDF0, darkHex: 0x252528)
    static let cardBackground = Color(lightHex: 0xF7F7F9, darkHex: 0x232326)
    static let cardBorder = Color(
        light: NSColor.black.withAlphaComponent(0.09),
        dark: NSColor.white.withAlphaComponent(0.12))
    static let separator = Color(lightHex: 0xE3E3E7, darkHex: 0x3A3A3E)

    static let textPrimary = Color(lightHex: 0x1D1D1F, darkHex: 0xF2F2F5)
    static let textSecondary = Color(lightHex: 0x5F5F66, darkHex: 0xA6A6AC)
    static let textTertiary = Color(lightHex: 0x76767C, darkHex: 0x98989E)

    static let accentFill = Color(lightHex: 0x1565E0, darkHex: 0x3D8CF5)
    static let accentOn = Color(lightHex: 0xFFFFFF, darkHex: 0x08182C)
    static let accentText = Color(lightHex: 0x0F5FD6, darkHex: 0x7DB8FF)
    static let accentSoft = Color(lightHex: 0xE8F0FE, darkHex: 0x16263D)

    static let success = Color(lightHex: 0x16733A, darkHex: 0x5BD08A)
    static let successBackground = Color(lightHex: 0xE4F3E9, darkHex: 0x123324)
    static let warning = Color(lightHex: 0x8A5300, darkHex: 0xF2B04A)
    static let warningBackground = Color(lightHex: 0xFBEFDC, darkHex: 0x3A2A10)
    static let danger = Color(lightHex: 0xB02419, darkHex: 0xFF7B6E)
    static let dangerBackground = Color(lightHex: 0xFBE9E7, darkHex: 0x3B1C18)

    static let control = Color(lightHex: 0xFFFFFF, darkHex: 0x3A3A3E)
    static let controlBorder = Color(
        light: NSColor.black.withAlphaComponent(0.14),
        dark: NSColor.white.withAlphaComponent(0.16))
    static let controlSecondary = Color(lightHex: 0xF2F2F4, darkHex: 0x2E2E32)
    static let neutral = Color(lightHex: 0xEFEFF2, darkHex: 0x303034)

    /// Not present on any of the spec's 13 screen frames — the spec's only
    /// disabled control is in the light-mode "system swatch" demo block, and
    /// that block gives no dark hex. Approximated as `textTertiary`'s dark
    /// value so a disabled control still reads as muted, rather than
    /// inventing an unconfirmed hex. Revisit if a later screen shows a
    /// disabled control explicitly.
    static let textDisabled = Color(lightHex: 0xA0A0A6, darkHex: 0x98989E)
}
