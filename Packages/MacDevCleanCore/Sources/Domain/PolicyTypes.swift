import Foundation

/// Something the user has asked MacDevClean to leave alone.
///
/// Exclusions apply before size calculation and again before final cleanup
/// validation. An exclusion inside a proposed directory blocks cleaning that
/// ancestor as a whole; a root exclusion blocks its descendants.
public enum Exclusion: Codable, Sendable, Hashable {
    case path(URL)
    case category(CleanupCategory)
    case rule(CleanupRuleID)
}

/// The scope cleanup is allowed to act in, as of one policy revision.
public struct SafetyContext: Sendable, Equatable {
    public let home: URL
    public let projectRoots: [URL]
    /// Folders the user explicitly chose for Large Files analysis. Project
    /// roots do not grant Large Files scope and vice versa.
    public let largeFileRoots: [URL]
    /// Exact allowlisted locations per global cache rule.
    public let globalRuleRoots: [CleanupRuleID: [URL]]
    public let exclusions: [Exclusion]
    /// Incremented whenever roots, exclusions or supported rules change.
    public let revision: UInt64

    public init(
        home: URL,
        projectRoots: [URL],
        largeFileRoots: [URL],
        globalRuleRoots: [CleanupRuleID: [URL]],
        exclusions: [Exclusion],
        revision: UInt64
    ) {
        self.home = home
        self.projectRoots = projectRoots
        self.largeFileRoots = largeFileRoots
        self.globalRuleRoots = globalRuleRoots
        self.exclusions = exclusions
        self.revision = revision
    }
}

/// Domain-safe failure codes. These are localised for presentation and never
/// carry raw command output, paths or environment details.
public enum PolicyError: String, Error, Codable, Sendable {
    case protectedPath, outsideScope, excluded, changed, missing, symbolicLink
    case unknownCandidate, staleScan, consentRequired, expiredPlan, usedPlan
    case unsupported, unavailable, permissionDenied, cancelled, journalUnavailable
}

public protocol SafetyContextProviding: Sendable {
    func current() async throws -> SafetyContext
}

/// Actor-owned registry of scan snapshots.
///
/// The user interface presents candidates but submits only identifiers, so a
/// caller cannot forge a candidate value and have it accepted.
public protocol CandidateStore: Sendable {
    func save(_ snapshot: ScanSnapshot) async
    func lookup(scanID: UUID, candidateID: UUID) async throws
        -> (CleanupCandidate, CandidateEvidence, UInt64)
    func invalidate() async
}

/// Path policy: protected roots, scope containment, exclusions and symlinks.
public protocol PathPolicyChecking: Sendable {
    func check(_ url: URL, ruleID: CleanupRuleID, context: SafetyContext) async throws
    func matches(_ url: URL, exclusion: URL) async throws -> Bool
}

public protocol ClockProviding: Sendable {
    func now() -> Date
}

/// Re-verifies that the evidence recorded at scan time still holds.
///
/// Both validation and execution call this, so a directory that has since
/// become tracked content cannot be removed using a stale scan.
public protocol RuleEvidenceChecking: Sendable {
    func verify(_ candidate: CleanupCandidate, evidence: CandidateEvidence) async throws
}
