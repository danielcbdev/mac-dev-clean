import Domain
import SwiftUI

/// The Overview, following the approved reference with its wording corrected.
struct OverviewView: View {
    @Bindable var coordinator: RootCoordinator
    @Bindable var model: ScanModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.cardGap) {
                header

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Layout.cardGap) {
                        summaryColumn.frame(maxWidth: .infinity)
                        categoriesColumn.frame(maxWidth: .infinity)
                    }
                    VStack(spacing: Layout.cardGap) {
                        summaryColumn
                        categoriesColumn
                    }
                }

                if !model.dockerSummaries.isEmpty {
                    dockerCard
                }

                informationCards
            }
            .padding(Layout.contentInset)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.isScanning)
        .navigationTitle(Text("Overview"))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: Layout.cardGap) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Clean with confidence")
                    .font(.system(size: 34, weight: .semibold))
                    .accessibilityIdentifier("app.title")
                Text(
                    """
                    Find developer caches and build artifacts, understand what removing each \
                    one costs you, then decide.
                    """
                )
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Layout.cardGap)

            trustIndicator
                .frame(maxWidth: 300)
        }
    }

    /// The reference's "Safe cleanup — only removes cache files" badge, made
    /// accurate: this app moves things to the Trash, which is recoverable but
    /// not a guarantee, and Docker removals are not recoverable at all.
    private var trustIndicator: some View {
        Card {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trash first").font(.headline)
                    Text("Files go to the Trash, never straight to deletion")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Summary

    private var summaryColumn: some View {
        Card {
            VStack(spacing: 16) {
                StorageSummaryView(
                    summaries: model.filesystemSummaries,
                    knownBytes: model.knownFilesystemBytes,
                    unknownCount: model.unknownFilesystemCount
                )

                if model.isScanning {
                    VStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .accessibilityIdentifier("scan.progress")
                            .accessibilityLabel("Scanning")
                        Text("Looking through your folders. \(model.visited) entries so far.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Button("Stop scanning") { coordinator.cancelScan() }
                            .accessibilityIdentifier("scan.cancel")
                    }
                } else {
                    Button {
                        coordinator.openReview()
                    } label: {
                        Label("Review cleanup", systemImage: "arrow.right")
                            .labelStyle(.titleAndIcon)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.snapshot == nil)
                    .accessibilityIdentifier("cleanup.reviewFromOverview")

                    Button(model.hasScanned ? "Scan again" : "Start scan") {
                        coordinator.startScan()
                    }
                    .disabled(!coordinator.canScan)
                    .accessibilityIdentifier("scan.start")

                    Text(statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("scan.status")
                }
            }
        }
    }

    private var statusMessage: String {
        if let failureCode = model.failureCode {
            return String(localized: "The scan could not finish (\(failureCode)).")
        }
        if model.wasCancelled && model.snapshot == nil {
            return String(localized: "Scan stopped. Nothing was changed.")
        }
        guard model.hasScanned else {
            return String(localized: "Nothing has been scanned yet.")
        }
        let count = model.candidates.count
        guard count > 0 else {
            return String(localized: "Nothing to clean up in the folders you added.")
        }
        return LocalizedFormatters.text(
            "Found %1$@ across %2$@.", locale: locale,
            LocalizedFormatters.count("%lld item", count, locale: locale),
            LocalizedFormatters.count(
                "%lld category", model.filesystemSummaries.count, locale: locale))
    }

    // MARK: - Categories

    private var categoriesColumn: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Cache categories").font(.title3.weight(.semibold))
                    Spacer()
                    Text(
                        LocalizedFormatters.text(
                            "%1$@ · %2$@", locale: locale,
                            LocalizedFormatters.count(
                                "%lld category", model.filesystemSummaries.count,
                                locale: locale),
                            LocalizedFormatters.bytes(
                                model.knownFilesystemBytes, locale: locale))
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
                .padding(.bottom, 8)

                if model.filesystemSummaries.isEmpty {
                    EmptyStateView(
                        symbol: "tray",
                        title: model.hasScanned ? "Nothing found" : "No results yet",
                        message: model.hasScanned
                            ? "MacDevClean found no removable artifacts in the folders you added."
                            : "Run a scan to see what is taking up space."
                    )
                } else {
                    ForEach(model.filesystemSummaries) { summary in
                        Divider().opacity(summary.id == model.filesystemSummaries.first?.id ? 0 : 1)
                        CategoryRow(summary: summary) {
                            coordinator.scanModel.ecosystemFilter = summary.category
                            coordinator.destination = .caches
                        }
                    }
                }
            }
        }
    }

    /// Docker is summarised on its own. Its bytes are a different kind of
    /// number — layers are shared — so they are never added to the ring.
    private var dockerCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Docker resources", systemImage: "shippingbox.fill")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("about " + ByteLabel.format(model.estimatedDockerBytes))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(
                    """
                    Estimated separately. Docker image layers are shared between images, so \
                    removing two images does not free the sum of their sizes. Docker removals \
                    cannot be undone.
                    """
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Button("Show Docker details") {
                    coordinator.scanModel.ecosystemFilter = .docker
                    coordinator.destination = .caches
                }
                .accessibilityIdentifier("docker.details")
            }
        }
    }

    // MARK: - Information

    private var informationCards: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Layout.cardGap) { cards }
            VStack(spacing: Layout.cardGap) { cards }
        }
    }

    @ViewBuilder
    private var cards: some View {
        InfoCard(
            symbol: "arrow.up.trash",
            tint: .green,
            title: "Trash first",
            message:
                """
                Files are moved to the Trash, so a mistake is usually recoverable. Space comes \
                back when you empty the Trash in Finder.
                """
        )
        InfoCard(
            symbol: "bolt",
            tint: .blue,
            title: "Know the impact",
            message:
                """
                Removing a cache means it gets rebuilt or downloaded again. Your next build \
                will be slower, not faster.
                """
        )
        InfoCard(
            symbol: "hand.raised",
            tint: .purple,
            title: "You stay in control",
            message:
                """
                Nothing is preselected and nothing is removed until you confirm. High-risk \
                items need a separate, explicit acknowledgment.
                """
        )
    }
}
