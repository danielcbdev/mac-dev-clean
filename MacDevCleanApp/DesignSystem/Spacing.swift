import SwiftUI

/// The layout constants the approved reference implies, in one place.
enum Layout {
    static let windowMinimumWidth: CGFloat = 1_100
    static let windowMinimumHeight: CGFloat = 720
    static let windowDefaultWidth: CGFloat = 1_280
    static let windowDefaultHeight: CGFloat = 840

    static let sidebarIdeal: CGFloat = 220
    static let sidebarMinimum: CGFloat = 200
    static let sidebarMaximum: CGFloat = 260

    /// Inset around the content column, and the gap between cards.
    static let contentInset: CGFloat = 28
    static let cardGap: CGFloat = 20
    static let cardPadding: CGFloat = 20
    static let cardRadius: CGFloat = 12

    static let ringMinimum: CGFloat = 220
    static let ringMaximum: CGFloat = 280
    static let ringStroke: CGFloat = 18

    static let rowMinimumHeight: CGFloat = 64
    static let symbolTile: CGFloat = 40
}

extension Layout {
    /// The redesign spec's spacing scale, in ascending order.
    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32

    /// `cardRadius` above already equals the spec's card radius (12).
    static let controlRadius: CGFloat = 8
    static let badgeRadius: CGFloat = 6
}

/// A surface with a semantic background and a restrained border.
///
/// No heavy shadow: depth here comes from the separator and the background,
/// which keeps it legible with Reduce Transparency and Increase Contrast.
struct Card<Content: View>: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(Layout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: Layout.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Layout.cardRadius)
                    .strokeBorder(.separator, lineWidth: 1)
            )
    }
}
