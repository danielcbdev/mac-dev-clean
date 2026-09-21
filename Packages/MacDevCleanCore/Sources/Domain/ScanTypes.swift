import Foundation

/// Logical or allocated size in bytes.
public typealias ByteCount = UInt64

/// Stable identifier of a rule in the cleanup catalog, for example `node.modules`.
public typealias CleanupRuleID = String

/// How much is at stake if an item is removed.
///
/// Risk is never conveyed by colour alone; every presentation pairs it with an
/// icon, a label and explanatory copy.
public enum RiskLevel: String, Codable, Sendable, CaseIterable {
    /// Regenerable cache or build output with no expected data loss.
    case low
    /// Regenerable or replaceable content whose removal affects workflows,
    /// archives or download time.
    case medium
    /// Potentially user-authored or otherwise unrecoverable data.
    case high
}

/// The ecosystem a candidate belongs to.
public enum CleanupCategory: String, Codable, Sendable, CaseIterable {
    case node, webBuild, flutter, xcode, simulator, cocoaPods, homebrew
    case gradle, python, rust, yarn, pnpm, bun, docker, largeFiles
}

/// A class of Docker resource the integration can inspect and remove.
public enum DockerOperation: String, Codable, Sendable, Hashable, CaseIterable {
    case container, image, volume, buildCache
}

/// How an item is removed.
///
/// Filesystem items always go to the Trash. Docker operations are irreversible
/// and are labelled as such wherever they appear.
public enum CleanupMethod: Codable, Sendable, Hashable {
    case trash
    case docker(DockerOperation)
}

/// Where a candidate lives: on disk, or inside a local Docker daemon.
public enum CleanupLocation: Codable, Sendable, Hashable {
    case file(URL)
    case docker(context: String, builder: String?, kind: DockerOperation, id: String)
}

/// A directory the user has authorised for scanning.
public struct ScanRoot: Codable, Sendable, Hashable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}

/// One scan request: which roots, and whether registered global caches are included.
public struct ScanRequest: Sendable, Equatable {
    public let roots: [ScanRoot]
    public let includeGlobalCaches: Bool

    public init(roots: [ScanRoot], includeGlobalCaches: Bool) {
        self.roots = roots
        self.includeGlobalCaches = includeGlobalCaches
    }
}

/// `lstat`-derived identity used to detect that a target changed between the
/// scan and the moment of execution.
public struct FileIdentity: Codable, Sendable, Hashable {
    public let device: UInt64
    public let inode: UInt64
    public let modifiedNanoseconds: Int64

    public init(device: UInt64, inode: UInt64, modifiedNanoseconds: Int64) {
        self.device = device
        self.inode = inode
        self.modifiedNanoseconds = modifiedNanoseconds
    }
}

/// Something the scanner found and believes is removable.
///
/// A candidate is a presentation value. It carries no authority: the cleanup
/// executor accepts only validated items built inside the `Cleanup` target.
public struct CleanupCandidate: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let ruleID: CleanupRuleID
    public let location: CleanupLocation
    public let category: CleanupCategory
    /// Logical size, or `nil` when the size could not be measured.
    public let size: ByteCount?
    /// Allocated size where the filesystem reports it, otherwise `nil`.
    public let allocatedSize: ByteCount?
    public let risk: RiskLevel
    public let method: CleanupMethod
    /// Localisation key for the consequence copy shown before cleanup.
    public let consequenceKey: String

    public init(
        id: UUID,
        ruleID: CleanupRuleID,
        location: CleanupLocation,
        category: CleanupCategory,
        size: ByteCount?,
        allocatedSize: ByteCount?,
        risk: RiskLevel,
        method: CleanupMethod,
        consequenceKey: String
    ) {
        self.id = id
        self.ruleID = ruleID
        self.location = location
        self.category = category
        self.size = size
        self.allocatedSize = allocatedSize
        self.risk = risk
        self.method = method
        self.consequenceKey = consequenceKey
    }
}

/// What the scanner observed about a candidate, kept out of the user interface
/// so policy can be rechecked at validation and again at execution time.
public struct CandidateEvidence: Sendable, Equatable {
    public let identity: FileIdentity?
    public let allowedRoot: URL?
    public let contextFingerprint: String?
    public let ruleEvidenceDigest: String

    public init(
        identity: FileIdentity?,
        allowedRoot: URL?,
        contextFingerprint: String?,
        ruleEvidenceDigest: String
    ) {
        self.identity = identity
        self.allowedRoot = allowedRoot
        self.contextFingerprint = contextFingerprint
        self.ruleEvidenceDigest = ruleEvidenceDigest
    }
}

/// The result of one scan. A new scan always produces a new snapshot identifier.
public struct ScanSnapshot: Sendable {
    public let id: UUID
    /// Policy revision the snapshot was taken under. A later change to roots,
    /// exclusions or supported rules invalidates it.
    public let policyRevision: UInt64
    public let candidates: [CleanupCandidate]
    public let evidence: [UUID: CandidateEvidence]

    public init(
        id: UUID,
        policyRevision: UInt64,
        candidates: [CleanupCandidate],
        evidence: [UUID: CandidateEvidence]
    ) {
        self.id = id
        self.policyRevision = policyRevision
        self.candidates = candidates
        self.evidence = evidence
    }
}

/// Incremental scan output. Progress is a visited count, never a fabricated
/// completion percentage.
public enum ScanEvent: Sendable {
    case progress(visited: Int)
    case issue(code: String, relativePath: String?)
    case completed(ScanSnapshot)
}

public protocol ScanService: Sendable {
    func scan(_ request: ScanRequest) -> AsyncThrowingStream<ScanEvent, Error>
}
