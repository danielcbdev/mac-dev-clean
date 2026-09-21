import SwiftUI

/// A destination whose feature is owned by a later milestone.
///
/// It says plainly that the screen is not built yet rather than showing an
/// empty list, which would read as "you have no history" when the truth is "no
/// history is being kept".
struct UpcomingFeatureView: View {
    let destination: Destination
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        EmptyStateView(symbol: symbol, title: title, message: message)
            .navigationTitle(Text(destination.title))
            .accessibilityIdentifier("upcoming.\(destination.rawValue)")
    }
}
