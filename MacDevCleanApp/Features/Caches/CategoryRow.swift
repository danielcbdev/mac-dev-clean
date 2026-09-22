import Domain
import SwiftUI

/// One category row, matching the reference's symbol tile, two-line label and
/// trailing size.
struct CategoryRow: View {
    @Environment(\.locale) private var locale

    let summary: ScanModel.CategorySummary
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: CategoryNaming.symbol(summary.category))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(
                        StorageSummaryView.color(for: summary.category),
                        in: .rect(cornerRadius: 7)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(CategoryNaming.title(summary.category))
                        .appFont(Typography.body)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(CategoryNaming.detail(summary.category))
                        .appFont(Typography.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 2) {
                    ByteLabel(bytes: summary.knownBytes, style: .body.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                    RiskBadge(risk: summary.highestRisk)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .frame(minHeight: Layout.rowMinimumHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("category.\(summary.category.rawValue)")
        .accessibilityLabel(
            LocalizedFormatters.text(
                "%1$@, %2$@, %3$@", locale: locale,
                CategoryNaming.title(summary.category),
                LocalizedFormatters.accessibleBytes(summary.knownBytes, locale: locale),
                RiskBadge.title(summary.highestRisk))
        )
    }
}
