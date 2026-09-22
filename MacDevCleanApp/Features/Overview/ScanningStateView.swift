import SwiftUI

/// The full-screen state shown while a scan is running — spec screen `1j`,
/// adapted to the data `ScanModel` actually has mid-scan (a running entry
/// count, nothing else). See the redesign-overview plan's Global
/// Constraints for why the spec's fraction/path/partial-total are not
/// reproduced here: `ScanModel` doesn't know a total until the scan ends,
/// and inventing one would misreport progress.
struct ScanningStateView: View {
    let visited: Int
    var cancel: () -> Void

    var body: some View {
        VStack(spacing: Layout.space16) {
            VStack(alignment: .leading, spacing: Layout.space16) {
                Text("Scanning")
                    .appFont(Typography.title)
                    .foregroundStyle(Theme.textPrimary)

                ProgressView()
                    .progressViewStyle(.linear)
                    .accessibilityIdentifier("scan.progress")
                    .accessibilityLabel("Scanning")

                Text("Looking through your folders. \(visited) entries so far.")
                    .appFont(Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()

                Divider().overlay(Theme.separator)

                HStack(spacing: Layout.space12) {
                    Button("Stop scanning", action: cancel)
                        .buttonStyle(.macDevSecondary)
                        .accessibilityIdentifier("scan.cancel")
                    Text("Stopping keeps what's already been measured and removes nothing.")
                        .appFont(Typography.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(22)
            .frame(maxWidth: 520)
            .background(Theme.cardBackground, in: .rect(cornerRadius: Layout.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Layout.cardRadius)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(40)
    }
}
