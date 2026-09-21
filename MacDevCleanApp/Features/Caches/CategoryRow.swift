import Domain
import SwiftUI

/// One category row, matching the reference's symbol tile, two-line label and
/// trailing size.
struct CategoryRow: View {
    let summary: ScanModel.CategorySummary
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: CategoryNaming.symbol(summary.category))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: Layout.symbolTile, height: Layout.symbolTile)
                    .background(
                        StorageSummaryView.color(for: summary.category),
                        in: .rect(cornerRadius: 10)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(CategoryNaming.title(summary.category))
                        .font(.body.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(CategoryNaming.detail(summary.category))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 2) {
                    ByteLabel(bytes: summary.knownBytes, style: .body.weight(.medium))
                    RiskBadge(risk: summary.highestRisk)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .frame(minHeight: Layout.rowMinimumHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("category.\(summary.category.rawValue)")
        .accessibilityLabel(
            "\(CategoryNaming.title(summary.category)), "
                + ByteLabel.accessibleText(summary.knownBytes) + ", "
                + RiskBadge.title(summary.highestRisk)
        )
    }
}
