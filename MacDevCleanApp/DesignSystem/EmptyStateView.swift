import SwiftUI

/// The state shown when there is nothing to show, which is a result rather than
/// a failure.
struct EmptyStateView: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title).font(.headline)
            // No `fixedSize(horizontal: false, vertical: true)` here, and that
            // omission is the fix for the defect the owner reported as "the
            // sidebar disappears".
            //
            // `fixedSize(vertical: true)` proposes `nil` width to the text,
            // which then reports its *ideal* size — for a sentence of this
            // length, its full unwrapped single-line width, several hundred
            // points. `frame(maxWidth: 420)` below does not clamp that,
            // because a maximum only binds a proposal that exists. Used as the
            // root of a NavigationSplitView detail column, the ideal width of
            // this view ballooned, the split view sized itself from it, and the
            // sidebar column kept its width while drawing no rows at all: a
            // window with no way out.
            //
            // Isolated by bisection on 2026-09-22 — restoring the long message
            // reproduced it, removing this one modifier fixed it, with nothing
            // else changed. The text still wraps: the frame below bounds it,
            // and a VStack in a vertically free container lets it grow.
            // See docs/verification/10-defects.md.
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: 420)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
}
