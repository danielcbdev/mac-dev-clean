import SwiftUI

/// A byte count, or an explicit statement that it is unknown.
///
/// `nil` is never rendered as "0 bytes". A size that could not be measured is
/// shown as unavailable and is left out of every total, which is the only
/// honest way to present it.
struct ByteLabel: View {
    let bytes: UInt64?
    var style: Font = .body

    var body: some View {
        Text(Self.text(bytes))
            .font(style)
            .monospacedDigit()
            .foregroundStyle(bytes == nil ? .secondary : .primary)
            .accessibilityLabel(Self.accessibleText(bytes))
    }

    static func text(_ bytes: UInt64?) -> String {
        guard let bytes else { return String(localized: "Size unavailable") }
        return format(bytes)
    }

    static func accessibleText(_ bytes: UInt64?) -> String {
        guard let bytes else { return String(localized: "Size could not be measured") }
        return format(bytes)
    }

    /// Locale-aware, via Foundation. Never a hand-rolled divide-by-1024.
    static func format(_ bytes: UInt64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}
