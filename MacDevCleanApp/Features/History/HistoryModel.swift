import Domain
import Foundation
import Observation

/// What MacDevClean has done, read back from durable storage.
///
/// This screen is read-only with respect to the filesystem. Clearing history
/// removes records; it never touches a file, and it never empties the Trash.
@MainActor
@Observable
final class HistoryModel {
    private(set) var sessions: [HistorySession] = []
    private(set) var isLoading = false
    private(set) var failureCode: String?
    var isConfirmingClear = false

    private let repository: any HistoryRepository
    private let workspace: any WorkspaceOpening
    private let fileManager: FileManager

    init(
        repository: any HistoryRepository,
        workspace: any WorkspaceOpening,
        fileManager: FileManager = .default
    ) {
        self.repository = repository
        self.workspace = workspace
        self.fileManager = fileManager
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // Anything left pending by a quit or a crash becomes explicitly
            // unknown before it is shown. It is never presented as a success.
            try await repository.recoverInterruptedSessions()
            sessions = try await repository.sessions()
            failureCode = nil
        } catch {
            failureCode = PolicyError.journalUnavailable.rawValue
        }
    }

    func clearConfirmed() async {
        do {
            try await repository.clear()
            sessions = []
            isConfirmingClear = false
        } catch {
            failureCode = PolicyError.journalUnavailable.rawValue
        }
    }

    /// "Show in Trash" is offered only when the recorded location still
    /// resolves. Trash names change, and items get emptied.
    func canRevealTrash(_ record: CleanupRecord) -> Bool {
        guard let url = record.resultingTrashURL else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    func revealTrash(recordID: UUID) {
        guard
            let record = sessions.flatMap(\.records).first(where: { $0.id == recordID }),
            let url = record.resultingTrashURL,
            fileManager.fileExists(atPath: url.path)
        else { return }
        workspace.reveal(url)
    }

    func openTrash() { workspace.openTrash() }

    // MARK: - Summaries

    func completedCount(_ session: HistorySession) -> Int {
        session.records.filter { $0.outcome == .movedToTrash || $0.outcome == .removed }.count
    }

    func unknownCount(_ session: HistorySession) -> Int {
        session.records.filter { $0.outcome == .indeterminate || $0.outcome == .pending }.count
    }

    func problemCount(_ session: HistorySession) -> Int {
        session.records.filter { $0.outcome == .failed || $0.outcome == .skipped }.count
    }
}
