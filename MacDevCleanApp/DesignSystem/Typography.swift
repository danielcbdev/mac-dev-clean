import SwiftUI

/// One typographic style: a size and weight from the spec's scale, plus
/// whether it always carries tabular (monospaced) digits.
struct AppFont {
    let size: CGFloat
    let weight: Font.Weight
    let tabularNumbers: Bool

    init(size: CGFloat, weight: Font.Weight, tabularNumbers: Bool = false) {
        self.size = size
        self.weight = weight
        self.tabularNumbers = tabularNumbers
    }

    var font: Font { .system(size: size, weight: weight) }
}

/// The spec's type scale — see `docs/references/redesign/design-tokens.md`.
/// SwiftUI's `Font.Weight` only exposes stops at 400/500/600/700 near this
/// range, so the spec's "650" titles render at `.semibold` (600), the
/// nearest stop below 700.
enum Typography {
    static let hero = AppFont(size: 34, weight: .bold)
    static let metric = AppFont(size: 42, weight: .bold, tabularNumbers: true)
    static let title = AppFont(size: 17, weight: .semibold)
    static let body = AppFont(size: 13, weight: .regular)
    static let caption = AppFont(size: 11, weight: .medium)
}

extension View {
    /// Applies an `AppFont`, including tabular digits when the token calls
    /// for them — the spec asks for this on every number so totals don't
    /// visually jitter as they update.
    @ViewBuilder
    func appFont(_ token: AppFont) -> some View {
        if token.tabularNumbers {
            self.font(token.font).monospacedDigit()
        } else {
            self.font(token.font)
        }
    }
}
