import Foundation

/// What actually happened to one item.
///
/// `indeterminate` exists because a side effect may succeed while journalling
/// fails, or the app may be interrupted mid-session. A pending record is never
/// assumed successful on restart.
public enum ItemOutcome: String, Codable, Sendable {
    case pending, movedToTrash, removed, skipped, failed, cancelled, indeterminate
}

/// One item's result within a cleanup session.
public struct CleanupRecord: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let candidate: CleanupCandidate
    public let outcome: ItemOutcome
    /// Where the item landed in the Trash. Names can change, so this is the URL
    /// the Trash API returned, and it may no longer resolve later.
    public let resultingTrashURL: URL?
    /// Domain-safe code, never raw output.
    public let errorCode: String?
    public let finishedAt: Date?

    public init(
        id: UUID,
        candidate: CleanupCandidate,
        outcome: ItemOutcome,
        resultingTrashURL: URL?,
        errorCode: String?,
        finishedAt: Date?
    ) {
        self.id = id
        self.candidate = candidate
        self.outcome = outcome
        self.resultingTrashURL = resultingTrashURL
        self.errorCode = errorCode
        self.finishedAt = finishedAt
    }
}

/// The result of one cleanup session.
///
/// `bytesMovedToTrash` is what was moved, not what was freed. Moving an item to
/// the Trash on the same volume keeps its data on that volume. The free-space
/// delta is a separate observation and is never presented as causal proof.
public struct CleanupSummary: Codable, Sendable, Equatable {
    public let sessionID: UUID
    public let records: [CleanupRecord]
    public let bytesMovedToTrash: UInt64
    public let observedFreeSpaceDelta: Int64?

    public init(
        sessionID: UUID,
        records: [CleanupRecord],
        bytesMovedToTrash: UInt64,
        observedFreeSpaceDelta: Int64?
    ) {
        self.sessionID = sessionID
        self.records = records
        self.bytesMovedToTrash = bytesMovedToTrash
        self.observedFreeSpaceDelta = observedFreeSpaceDelta
    }
}
