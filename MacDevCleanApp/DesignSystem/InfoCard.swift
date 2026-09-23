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
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.14), in: .rect(cornerRadius: Layout.controlRadius))
                    .accessibilityHidden(true)
                Text(title)
                    .appFont(Typography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .appFont(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
