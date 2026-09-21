import Domain
import SwiftUI

#if canImport(AppKit)
    import AppKit
#endif

/// What actually happened, separated by outcome and stated without promises.
struct CleanupResultsView: View {
    @Bindable var coordinator: RootCoordinator
    @Bindable var review: ReviewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.cardGap) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Cleanup finished").font(.title.weight(.semibold))

                        if let summary = review.summary {
                            Text(
                                ByteLabel.format(summary.bytesMovedToTrash) + " moved to the Trash"
                            )
                            .font(.title2)
                            .monospacedDigit()
                            .accessibilityIdentifier("results.bytesMoved")

                            Text(
                                "Moved to Trash. Empty Trash in Finder to reclaim space."
                            )
                            .font(.callout)
                            .foregroundStyle(.secondary)

                            Text(freeSpaceSentence(summary))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("results.freeSpace")
                        }

                        HStack {
                            Button("Open Trash") { coordinator.openTrash() }
                                .accessibilityIdentifier("results.openTrash")
                            Button("Copy diagnostics") {
                                Clipboard.write(review.diagnosticReport)
                            }
                            .accessibilityIdentifier("results.copyDiagnostics")
                            Spacer()
                            Button("Done") {
                                coordinator.reviewModel.reset()
                                coordinator.closeReview()
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("results.done")
                        }
                    }
                }

                section(
                    "Moved to the Trash", review.recoverable, tint: .green,
                    note:
                        """
                        You may be able to put these back from the Trash, but that is not \
                        guaranteed.
                        """
                )
                section(
                    "Permanently removed", review.irreversiblyRemoved, tint: .red,
                    note: "These cannot be restored.")
                section(
                    "Skipped", review.skipped, tint: .orange,
                    note: "Something changed, so these were left alone.")
                section("Failed", review.failed, tint: .red, note: nil)
                section("Stopped", review.cancelled, tint: .secondary, note: nil)
                section(
                    "Outcome unknown", review.indeterminate, tint: .orange,
                    note:
                        """
                        MacDevClean could not confirm what happened to these. They were not \
                        retried.
                        """
                )
            }
            .padding(Layout.contentInset)
        }
    }

    private func freeSpaceSentence(_ summary: CleanupSummary) -> String {
        guard let delta = summary.observedFreeSpaceDelta else {
            return String(localized: "Free space could not be measured.")
        }
        let formatted = ByteLabel.format(UInt64(abs(delta)))
        if delta > 0 {
            return String(
                localized:
                    """
                    Free space changed by +\(formatted) while this ran. That is an \
                    observation, not a result of this cleanup.
                    """
            )
        }
        if delta < 0 {
            return String(
                localized:
                    """
                    Free space changed by −\(formatted) while this ran, because other things \
                    on your Mac were writing at the same time.
                    """
            )
        }
        return String(
            localized:
                """
                Free space did not change, which is expected: trashed items still occupy the \
                volume.
                """
        )
    }

    @ViewBuilder
    private func section(
        _ title: LocalizedStringKey,
        _ records: [CleanupRecord],
        tint: Color,
        note: LocalizedStringKey?
    ) -> some View {
        if !records.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(title).font(.headline).foregroundStyle(tint)
                        Spacer()
                        Text("^[\(records.count) item](inflect: true)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(records) { record in
                        HStack {
                            Text(ScanModel.displayName(record.candidate)).font(.callout)
                            Spacer()
                            if let code = record.errorCode {
                                Text(code).font(.caption).foregroundStyle(.secondary)
                            }
                            ByteLabel(bytes: record.candidate.size, style: .caption)
                        }
                    }
                }
            }
        }
    }
}

/// Small wrapper so views do not reach into AppKit directly.
enum Clipboard {
    @MainActor
    static func write(_ text: String) {
        #if canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
