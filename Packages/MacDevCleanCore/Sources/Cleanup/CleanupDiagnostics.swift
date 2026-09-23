import Domain
import Foundation

/// Builds the copyable report offered on the completion screen.
///
/// Users paste diagnostics into issue trackers and chat, so this deliberately
/// contains nothing that identifies them or their work: no original path, no
/// Trash URL, no Docker resource name, no command output, no home directory.
///
/// What it does contain is what is actually useful for diagnosis — which rules
/// ran, how many items reached each outcome, and which error codes appeared.
public enum CleanupDiagnostics {

    public static func report(
        for summary: CleanupSummary,
        appVersion: String,
        systemVersion: String = ProcessInfo.processInfo.operatingSystemVersionString
    ) -> String {
        var lines: [String] = []
        lines.append("MacDevClean diagnostic report")
        lines.append("app: \(appVersion)")
        lines.append("system: \(systemVersion)")
        lines.append("items: \(summary.records.count)")

        let byOutcome = Dictionary(grouping: summary.records, by: \.outcome)
        for outcome in ItemOutcome.allCases where byOutcome[outcome] != nil {
            lines.append("outcome.\(outcome.rawValue): \(byOutcome[outcome]?.count ?? 0)")
        }

        let byRule = Dictionary(grouping: summary.records, by: \.candidate.ruleID)
        for rule in byRule.keys.sorted() {
            lines.append("rule.\(rule): \(byRule[rule]?.count ?? 0)")
        }

        let errors = summary.records.compactMap(\.errorCode)
        let byError = Dictionary(grouping: errors, by: { $0 })
        for code in byError.keys.sorted() {
            lines.append("error.\(code): \(byError[code]?.count ?? 0)")
        }

        // Moved, not freed. The distinction is the whole point.
        lines.append("bytesMovedToTrash: \(summary.bytesMovedToTrash)")
        lines.append(
            "observedFreeSpaceDelta: "
                + (summary.observedFreeSpaceDelta.map(String.init) ?? "unavailable")
        )
        lines.append("note: bytes moved to Trash are not bytes freed.")

        return lines.joined(separator: "\n")
    }
}

extension ItemOutcome: CaseIterable {
    public static var allCases: [ItemOutcome] {
        [.pending, .movedToTrash, .removed, .skipped, .failed, .cancelled, .indeterminate]
    }
}
