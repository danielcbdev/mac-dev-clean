import Domain
import SwiftUI

/// Per-item detail for one recorded session.
struct HistoryDetailView: View {
    let session: HistorySession
    let model: HistoryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(session.records) { record in
                Divider()
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(displayName(record))
                            .font(.callout)
                        HStack(spacing: 8) {
                            Text(CategoryNaming.title(record.candidate.category))
                            Text(methodLabel(record))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if let code = record.errorCode {
                            Text(code)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 3) {
                        Text(outcomeLabel(record.outcome))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(outcomeTint(record.outcome))
                        RiskBadge(risk: record.candidate.risk)
                    }

                    if model.canRevealTrash(record) {
                        Button("Show in Trash") { model.revealTrash(recordID: record.id) }
                            .font(.caption)
                            .accessibilityIdentifier(
                                "history.record.\(record.id.uuidString).reveal")
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func displayName(_ record: CleanupRecord) -> String {
        if record.candidate.ruleID == "record.unreadable" {
            return String(localized: "Unreadable entry")
        }
        return ScanModel.displayName(record.candidate)
    }

    private func methodLabel(_ record: CleanupRecord) -> String {
        record.candidate.method == .trash
            ? String(localized: "Moved to the Trash")
            : String(localized: "Removed permanently")
    }

    private func outcomeLabel(_ outcome: ItemOutcome) -> String {
        switch outcome {
        case .movedToTrash: return String(localized: "In the Trash")
        case .removed: return String(localized: "Removed")
        case .skipped: return String(localized: "Skipped")
        case .failed: return String(localized: "Failed")
        case .cancelled: return String(localized: "Stopped")
        // Never shown as a failure, and never offered a retry: nobody knows.
        case .indeterminate: return String(localized: "Outcome unknown")
        case .pending: return String(localized: "Outcome unknown")
        }
    }

    private func outcomeTint(_ outcome: ItemOutcome) -> Color {
        switch outcome {
        case .movedToTrash, .removed: return .green
        case .failed: return .red
        case .skipped, .indeterminate, .pending: return .orange
        case .cancelled: return .secondary
        }
    }
}
