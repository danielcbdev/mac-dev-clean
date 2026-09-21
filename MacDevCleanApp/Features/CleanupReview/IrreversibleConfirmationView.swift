import Domain
import SwiftUI

/// The second confirmation, required before anything irreversible happens.
///
/// Both acknowledgments start unchecked every time the review's contents
/// change. An acknowledgment applies to what the user was actually looking at.
struct IrreversibleConfirmationView: View {
    @Bindable var coordinator: RootCoordinator
    @Bindable var review: ReviewModel
    let dockerItems: [CleanupCandidate]
    let highRiskItems: [CleanupCandidate]
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Layout.cardGap) {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("This cannot be undone", systemImage: "exclamationmark.octagon")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.red)

                            if dockerItems.contains(where: { $0.method == .docker(.volume) }) {
                                Text(
                                    """
                                    This may permanently delete databases and other data. \
                                    MacDevClean cannot restore it.
                                    """
                                )
                                .font(.title3)
                                .fixedSize(horizontal: false, vertical: true)
                            }

                            Text(
                                """
                                Docker resources do not go to the Trash. High-risk items may \
                                hold the only copy of something.
                                """
                            )
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if !dockerItems.isEmpty { list(title: "Docker", items: dockerItems) }
                    if !highRiskItems.isEmpty {
                        list(title: "High-risk items", items: highRiskItems)
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            if !dockerItems.isEmpty {
                                Toggle(isOn: $review.acknowledgeIrreversible) {
                                    Text(
                                        """
                                        I understand these removals are permanent and cannot \
                                        be undone.
                                        """
                                    )
                                    .fixedSize(horizontal: false, vertical: true)
                                }
                                .toggleStyle(.checkbox)
                                .accessibilityIdentifier("cleanup.irreversible.ack")
                            }
                            if !highRiskItems.isEmpty {
                                Toggle(isOn: $review.acknowledgeHighRisk) {
                                    Text(
                                        """
                                        I have reviewed the high-risk items and accept that \
                                        their contents may be lost.
                                        """
                                    )
                                    .fixedSize(horizontal: false, vertical: true)
                                }
                                .toggleStyle(.checkbox)
                                .accessibilityIdentifier("cleanup.highRisk.ack")
                            }
                        }
                    }
                }
                .padding(Layout.contentInset)
            }

            Divider()

            HStack {
                Button("Back", action: onBack)
                    .accessibilityIdentifier("cleanup.irreversible.back")
                Spacer()
                Button {
                    Task { await coordinator.confirmCleanup() }
                } label: {
                    Text(
                        """
                        Permanently remove ^[\(dockerItems.count + highRiskItems.count) \
                        item](inflect: true)
                        """
                    )
                    .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
                .disabled(
                    !review.canConfirm(
                        needsIrreversible: !dockerItems.isEmpty,
                        needsHighRisk: !highRiskItems.isEmpty)
                        || !coordinator.dependencies.cleanupEnabled
                )
                .accessibilityIdentifier("cleanup.permanentlyRemove")
            }
            .padding(.horizontal, Layout.contentInset)
            .padding(.vertical, 14)
        }
    }

    private func list(title: LocalizedStringKey, items: [CleanupCandidate]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                ForEach(items) { candidate in
                    HStack {
                        Text(ScanModel.displayName(candidate)).font(.body)
                        Spacer()
                        RiskBadge(risk: candidate.risk)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
