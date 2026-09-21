import Domain
import Foundation

/// Holds the scan snapshots that are currently live.
///
/// The user interface shows candidates but submits identifiers. Cleanup looks
/// those identifiers up here, so a caller cannot hand the executor a candidate
/// value it made up, and cannot reuse one from a scan taken under a different
/// policy revision.
public actor InMemoryCandidateStore: CandidateStore {
    private var snapshots: [UUID: ScanSnapshot] = [:]

    public init() {}

    public func save(_ snapshot: ScanSnapshot) {
        snapshots[snapshot.id] = snapshot
    }

    public func lookup(
        scanID: UUID,
        candidateID: UUID
    ) throws -> (CleanupCandidate, CandidateEvidence, UInt64) {
        guard let snapshot = snapshots[scanID] else { throw PolicyError.staleScan }
        guard let candidate = snapshot.candidates.first(where: { $0.id == candidateID }),
            let evidence = snapshot.evidence[candidateID]
        else {
            throw PolicyError.unknownCandidate
        }
        return (candidate, evidence, snapshot.policyRevision)
    }

    /// Drops every snapshot. Called when roots, exclusions or supported rules
    /// change, because results taken under the old scope no longer mean what
    /// they meant.
    public func invalidate() {
        snapshots.removeAll()
    }
}
