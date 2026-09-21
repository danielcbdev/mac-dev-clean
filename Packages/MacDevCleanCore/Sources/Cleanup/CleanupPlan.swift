import Domain
import Foundation

/// What the user picked, expressed only as identifiers.
///
/// There is no path here and no risk level. The interface cannot describe an
/// item; it can only point at one the scanner registered. Everything else is
/// looked up from the candidate store, so a caller cannot dress an arbitrary
/// path up as a low-risk cache.
public struct CleanupSelection: Sendable, Equatable {
    public let scanID: UUID
    public let candidateIDs: Set<UUID>
    /// The user acknowledged that some operations cannot be undone.
    public let acknowledgedIrreversible: Bool
    /// The user acknowledged the high-risk items specifically.
    public let acknowledgedHighRisk: Bool

    public init(
        scanID: UUID,
        candidateIDs: Set<UUID>,
        acknowledgedIrreversible: Bool,
        acknowledgedHighRisk: Bool
    ) {
        self.scanID = scanID
        self.candidateIDs = candidateIDs
        self.acknowledgedIrreversible = acknowledgedIrreversible
        self.acknowledgedHighRisk = acknowledgedHighRisk
    }
}

/// One item that has passed every policy check.
///
/// The initialiser is internal to this target on purpose. Code outside
/// `Cleanup` — including the application — cannot construct one, so the
/// executor's input can only have come from the validator. There is no
/// `Codable` conformance either: a plan cannot be decoded into existence.
public struct ValidatedCleanupItem: Sendable {
    public let candidate: CleanupCandidate
    let evidence: CandidateEvidence

    init(candidate: CleanupCandidate, evidence: CandidateEvidence) {
        self.candidate = candidate
        self.evidence = evidence
    }
}

/// A short-lived authorisation to perform one specific set of operations.
///
/// It carries the policy revision it was built under, so a change to roots or
/// exclusions invalidates it, and it expires, so a review screen left open all
/// afternoon cannot be confirmed against a world that has moved on.
///
/// The executor consumes a plan exactly once. Confirming twice does not act
/// twice.
public struct ValidatedCleanupPlan: Sendable {
    public let id: UUID
    public let items: [ValidatedCleanupItem]
    public let expiresAt: Date
    let policyRevision: UInt64

    init(id: UUID, items: [ValidatedCleanupItem], expiresAt: Date, policyRevision: UInt64) {
        self.id = id
        self.items = items
        self.expiresAt = expiresAt
        self.policyRevision = policyRevision
    }
}

/// How long an authorisation stays usable after validation.
public let cleanupPlanLifetime: TimeInterval = 60
