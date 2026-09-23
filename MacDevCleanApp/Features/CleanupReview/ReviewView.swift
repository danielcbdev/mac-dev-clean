import Domain
import SwiftUI

/// The authoritative confirmation surface.
///
/// The primary action says exactly what it will do — "Move 12 items to the
/// Trash" — rather than "Continue". Irreversible operations are a separate
/// group with their own wording, and reaching them needs a second screen.
struct ReviewView: View {
    @Bindable var coordinator: RootCoordinator
    @Bindable var model: ScanModel
    @Bindable var review: ReviewModel

    @Environment(\.locale) private var locale

    @State private var showingIrreversibleStep = false

    /// Everything under review, wherever it was selected. Caches fills this
    /// from the scan snapshot; Large Files fills it from its own.
    private var reviewed: [CleanupCandidate] {
        coordinator.reviewedCandidates
    }
    private var trashItems: [CleanupCandidate] {
        reviewed.filter { $0.method == .trash }
    }
    private var dockerItems: [CleanupCandidate] {
        reviewed.filter { $0.method != .trash }
    }

    var body: some View {
        VStack(spacing: 0) {
            if review.summary != nil {
                CleanupResultsView(coordinator: coordinator, review: review)
            } else if showingIrreversibleStep {
                IrreversibleConfirmationView(
                    coordinator: coordinator,
                    review: review,
                    dockerItems: dockerItems,
                    highRiskItems: reviewed.filter { $0.risk == .high },
                    onBack: { showingIrreversibleStep = false }
                )
            } else {
                content
            }
        }
        .navigationTitle(Text("Review cleanup"))
        .onAppear { review.contentChanged(to: coordinator.activeSelection) }
        .onChange(of: coordinator.activeSelection) { _, new in review.contentChanged(to: new) }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Layout.cardGap) {
                    if !review.validationIssues.isEmpty { issuesCard }

                    if !trashItems.isEmpty {
                        group(
                            title: "Files to move to the Trash",
                            symbol: "arrow.up.trash",
                            tint: .green,
                            note:
                                """
                                These go to the Trash. Space comes back when you empty it in \
                                Finder. MacDevClean never empties it for you.
                                """,
                            items: trashItems
                        )
                    }

                    if !dockerItems.isEmpty {
                        group(
                            title: "Irreversible Docker actions",
                            symbol: "exclamationmark.octagon",
                            tint: .red,
                            note:
                                """
                                There is no Trash for Docker resources. Once removed, they are \
                                gone. These need a separate confirmation.
                                """,
                            items: dockerItems
                        )
                    }

                    if !coordinator.dependencies.cleanupEnabled { unavailableCard }
                }
                .padding(Layout.contentInset)
            }

            Divider()
            footer
        }
    }

    private func group(
        title: LocalizedStringKey,
        symbol: String,
        tint: Color,
        note: LocalizedStringKey,
        items: [CleanupCandidate]
    ) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(title, systemImage: symbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tint)
                    Spacer()
                    Text(
                        LocalizedFormatters.text(
                            "%1$@ · %2$@", locale: locale,
                            LocalizedFormatters.count("%lld item", items.count, locale: locale),
                            LocalizedFormatters.bytes(
                                items.compactMap(\.size).reduce(0, +), locale: locale))
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(items) { candidate in
                    Divider()
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ScanModel.displayName(candidate)).font(.body)
                            Text(ConsequenceCopy.text(for: candidate.consequenceKey))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        VStack(alignment: .trailing, spacing: 2) {
                            ByteLabel(bytes: candidate.size, style: .callout)
                            RiskBadge(risk: candidate.risk)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var issuesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "Some items can no longer be cleaned", systemImage: "exclamationmark.triangle"
                )
                .font(.headline)
                .foregroundStyle(.orange)
                Text(
                    """
                    Something changed since the scan. Nothing was removed. Scan again to see \
                    the current state.
                    """
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                ForEach(review.validationIssues, id: \.candidateID) { issue in
                    Text(
                        LocalizedFormatters.text(
                            "• %@", locale: locale, IssueCopy.text(for: issue.code))
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Button("Scan again") {
                    coordinator.closeReview()
                    coordinator.startScan()
                }
                .accessibilityIdentifier("cleanup.rescan")
            }
        }
    }

    private var unavailableCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Label("Cleanup is not available yet", systemImage: "lock")
                    .font(.headline)
                Text(
                    """
                    MacDevClean will not remove anything until it can record what it did \
                    somewhere that survives quitting the app. Scanning and explaining work \
                    normally.
                    """
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("cleanup.unavailable")
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Button("Back") { coordinator.closeReview() }
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityIdentifier("cleanup.back")

            Spacer()

            if !dockerItems.isEmpty || reviewed.contains(where: { $0.risk == .high }) {
                Button("Review irreversible actions") { showingIrreversibleStep = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!coordinator.dependencies.cleanupEnabled)
                    .accessibilityIdentifier("cleanup.irreversible.review")
            } else {
                Button {
                    Task { await coordinator.confirmCleanup() }
                } label: {
                    CountText("Move %lld item to the Trash", trashItems.count)
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(
                    review.isRunning || trashItems.isEmpty
                        || !coordinator.dependencies.cleanupEnabled
                )
                .accessibilityIdentifier("cleanup.moveToTrash")
            }
        }
        .padding(.horizontal, Layout.contentInset)
        .padding(.vertical, 14)
    }
}

/// Plain-language text for a policy failure code.
enum IssueCopy {
    static func text(for code: PolicyError) -> String {
        switch code {
        case .changed: return String(localized: "The item changed after the scan.")
        case .missing: return String(localized: "The item is no longer there.")
        case .excluded: return String(localized: "The item is now excluded.")
        case .staleScan: return String(localized: "The scan is out of date.")
        case .consentRequired:
            return String(localized: "This needs an acknowledgment that was not given.")
        case .protectedPath, .outsideScope:
            return String(localized: "The item is outside the folders you allowed.")
        case .symbolicLink: return String(localized: "The item is a symbolic link.")
        case .expiredPlan, .usedPlan:
            return String(localized: "This confirmation is no longer valid.")
        case .permissionDenied: return String(localized: "MacDevClean cannot read the item.")
        case .unavailable, .unsupported:
            return String(localized: "MacDevClean cannot act on this item.")
        case .cancelled: return String(localized: "The action was stopped.")
        case .unknownCandidate: return String(localized: "The item is no longer in the results.")
        case .journalUnavailable: return String(localized: "The history could not be recorded.")
        }
    }
}
