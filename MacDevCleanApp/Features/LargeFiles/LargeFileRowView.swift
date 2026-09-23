import Domain
import SwiftUI

/// One large file. Name, size, when it changed, what it is, and where it lives.
struct LargeFileRowView: View {
    let row: LargeFileRow
    let isSelected: Bool
    let onToggle: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(get: { isSelected }, set: { _ in onToggle() })) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(!row.canSelect)
            .accessibilityIdentifier("largeFile.\(row.id.uuidString).select")
            .accessibilityLabel("Select \(row.url.lastPathComponent)")

            VStack(alignment: .leading, spacing: 3) {
                Text(row.url.lastPathComponent)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text(row.url.deletingLastPathComponent().lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !row.canSelect {
                    Text("Shown for information only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                ByteLabel(bytes: row.logicalBytes, style: .callout)
                HStack(spacing: 8) {
                    Text(row.kindDescription)
                    Text(row.modifiedAt, format: .dateTime.year().month().day())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            if row.canSelect {
                RiskBadge(risk: .high)
            }
        }
        .padding(.vertical, 9)
        .frame(minHeight: Layout.rowMinimumHeight)
        .contextMenu {
            Button("Reveal in Finder", action: onReveal)
        }
        .accessibilityElement(children: .combine)
    }
}
