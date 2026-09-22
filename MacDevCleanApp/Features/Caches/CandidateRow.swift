import Domain
import SwiftUI

/// One selectable item.
///
/// High-risk items are not selectable here. They are selected from their own
/// expanded detail section, so choosing one is always a deliberate act rather
/// than a stray click in a long list.
struct CandidateRow: View {
    let candidate: CleanupCandidate
    let isSelected: Bool
    let isSelectable: Bool
    let onToggle: () -> Void
    var onReveal: (() -> Void)?
    var onExclude: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(get: { isSelected }, set: { _ in onToggle() })) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(!isSelectable)
            .accessibilityIdentifier(ScanModel.accessibilityID(candidate))
            .accessibilityLabel("Select \(ScanModel.displayName(candidate))")

            VStack(alignment: .leading, spacing: 3) {
                Text(ScanModel.displayName(candidate))
                    .appFont(Typography.body)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ConsequenceCopy.text(for: candidate.consequenceKey))
                    .appFont(Typography.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if candidate.method != .trash {
                    Text("Cannot be undone")
                        .appFont(Typography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.danger)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                ByteLabel(bytes: candidate.size, style: .callout)
                    .foregroundStyle(Theme.textPrimary)
                RiskBadge(risk: candidate.risk)
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: Layout.rowMinimumHeight)
        .contextMenu {
            if let onReveal, case .file = candidate.location {
                Button("Reveal in Finder", action: onReveal)
            }
            if let onExclude {
                Button("Always skip this", action: onExclude)
            }
        }
    }
}

/// Plain-language consequences, keyed by the rule's consequence key.
enum ConsequenceCopy {
    static func text(for key: String) -> String {
        switch key {
        case ConsequenceKey.reinstallDependencies:
            return String(
                localized:
                    """
                    Dependencies must be installed again. Any edits you made inside installed \
                    packages are lost.
                    """
            )
        case ConsequenceKey.rebuildOutput:
            return String(localized: "Rebuilt the next time you build.")
        case ConsequenceKey.redeployArtifact:
            return String(
                localized:
                    """
                    The built site is gone until you build it again. Redeploy if you were \
                    serving from here.
                    """
            )
        case ConsequenceKey.refetchPackages:
            return String(localized: "Packages are downloaded again next time.")
        case ConsequenceKey.rebuildSlowerNextTime:
            return String(localized: "Your next build will be slower while this is rebuilt.")
        case ConsequenceKey.redownloadTooling:
            return String(localized: "Downloads are fetched again next time.")
        case ConsequenceKey.loseArchivedBuilds:
            return String(
                localized:
                    """
                    Archived builds and their symbols are gone. Nothing regenerates them, and \
                    old crash reports may stop being readable.
                    """
            )
        case ConsequenceKey.reprocessDeviceSupport:
            return String(
                localized:
                    "Symbols are downloaded and processed again the next time you attach a device.")
        case ConsequenceKey.userSelectedFile:
            return String(localized: "You chose this item yourself. Check it before continuing.")
        default:
            return String(localized: "This item will be removed.")
        }
    }
}
