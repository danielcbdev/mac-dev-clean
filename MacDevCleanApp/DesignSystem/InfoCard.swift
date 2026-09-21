import SwiftUI

/// One of the three explanatory cards along the bottom of the Overview.
struct InfoCard: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.14), in: .rect(cornerRadius: 8))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
