import SwiftUI

/// A byte count, or an explicit statement that it is unknown.
///
/// `nil` is never rendered as "0 bytes". A size that could not be measured is
/// shown as unavailable and is left out of every total, which is the only
/// honest way to present it.
struct ByteLabel: View {
    let bytes: UInt64?
    var style: Font = .body
    @Environment(\.locale) private var locale

    var body: some View {
        Text(LocalizedFormatters.bytes(bytes, locale: locale))
            .font(style)
            .monospacedDigit()
            .foregroundStyle(bytes == nil ? .secondary : .primary)
            .accessibilityLabel(LocalizedFormatters.bytes(bytes, locale: locale))
    }

    static func text(_ bytes: UInt64?) -> String {
        LocalizedFormatters.bytes(bytes, locale: .autoupdatingCurrent)
    }

    static func accessibleText(_ bytes: UInt64?) -> String {
        guard let bytes else { return String(localized: "Size could not be measured") }
        return format(bytes)
    }

    /// Locale-aware, via Foundation. Never a hand-rolled divide-by-1024.
    static func format(_ bytes: UInt64) -> String {
        LocalizedFormatters.bytes(bytes, locale: .autoupdatingCurrent)
    }
}
