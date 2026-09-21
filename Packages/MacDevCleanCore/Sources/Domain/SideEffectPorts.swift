import Foundation

/// The only filesystem removal mechanism in production.
///
/// Implementations wrap `FileManager.trashItem(at:resultingItemURL:)` and
/// return the resulting Trash URL. Production code never calls `rm`, `rmdir` or
/// `removeItem` for user-selected cleanup, and never empties the Trash.
public protocol TrashClient: Sendable {
    func moveToTrash(_ url: URL) async throws -> URL
}

/// Failures a Trash implementation can report that are not policy decisions.
public enum TrashOutcomeError: Error, Sendable, Equatable {
    /// The move succeeded but the Trash did not report where the item landed.
    ///
    /// The item **has moved**. This is never a reason to move it again; the
    /// outcome is recorded as indeterminate and the session stops scheduling.
    case movedButResultingLocationUnknown
}

/// Observes free space on a volume.
///
/// Free-space deltas are observations, never causal proof. Other processes,
/// APFS clones, snapshots, hard links and Docker's virtual machine all move
/// this number. It is reported alongside bytes moved, never as the same thing.
public protocol FreeSpaceObserving: Sendable {
    func availableBytes(on url: URL) async -> Int64?
}

/// Durable record of a cleanup session, written around each side effect.
///
/// A journal failure *before* a side effect aborts execution. If recording
/// fails *after* a side effect, execution stops scheduling and the result is
/// exposed as potentially unrecorded. The side effect is never repeated to
/// "fix" history.
public protocol CleanupJournal: Sendable {
    func begin(sessionID: UUID, candidates: [CleanupCandidate], at: Date) async throws
    func record(sessionID: UUID, record: CleanupRecord) async throws
    func finish(_ summary: CleanupSummary, at: Date) async throws
}

/// A point-in-time reading of the local Docker daemon.
public struct DockerInventory: Sendable {
    /// Identity of the daemon and context the reading came from. A write is
    /// rejected if the fingerprint no longer matches.
    public let fingerprint: String
    public let candidates: [CleanupCandidate]
    public let evidence: [UUID: CandidateEvidence]

    public init(
        fingerprint: String,
        candidates: [CleanupCandidate],
        evidence: [UUID: CandidateEvidence]
    ) {
        self.fingerprint = fingerprint
        self.candidates = candidates
        self.evidence = evidence
    }
}

/// Read and removal operations against an explicitly selected local daemon.
///
/// Implementations build an executable URL plus an argument array and never a
/// shell string, remove resources by reviewed identifier rather than by broad
/// prune, and revalidate the endpoint and daemon identity before each write.
public protocol DockerClient: Sendable {
    func inventory() async throws -> DockerInventory
    func revalidate(_ item: CleanupCandidate, evidence: CandidateEvidence) async throws
    func remove(_ item: CleanupCandidate) async throws
}
