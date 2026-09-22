import SwiftUI

/// The full-screen state shown before the first scan ever runs — spec
/// screen `1i`. Replaces the card layout entirely rather than showing an
/// empty ring, because there is nothing yet to summarize.
///
/// The message `Text` below is deliberately not `.fixedSize(vertical: true)`
/// — see `EmptyStateView.swift` and `docs/verification/10-defects.md` for
/// why that combination, at the root of the detail column, previously
/// emptied the sidebar (defect D3).
struct NeverScannedView: View {
    var startScan: () -> Void
    var chooseFolders: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
            Text("Nothing has been scanned yet")
                .appFont(Typography.title)
                .foregroundStyle(Theme.textPrimary)
            Text(
                """
                MacDevClean only reads the project folders you chose in Settings. A scan \
                measures sizes and explains what each item costs.
                """
            )
            .appFont(Typography.body)
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 460)

            HStack(spacing: 10) {
                Button("Start scan", action: startScan)
                    .buttonStyle(.macDevPrimary)
                    .accessibilityIdentifier("scan.start")
                Button("Choose folders…", action: chooseFolders)
                    .buttonStyle(.macDevSecondary)
            }
            .padding(.top, 2)

            Text("Scanning doesn't select or remove anything.")
                .appFont(Typography.caption)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(40)
    }
}
