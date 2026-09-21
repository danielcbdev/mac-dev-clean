import Domain
import Foundation

/// Re-derives the evidence for a candidate and compares it with what the scan
/// recorded.
///
/// A scan is a photograph. By the time the user confirms, the project may have
/// changed: somebody may have committed the contents of `dist`, or switched a
/// Flutter app to a plain Dart package. This runs at validation *and* again
/// immediately before the side effect, so a stale snapshot cannot authorise a
/// target that no longer means what it meant.
///
/// Docker candidates are not this type's business: `DockerClient.revalidate`
/// re-checks the daemon and the resource identity.
public struct RuleEvidenceChecker: RuleEvidenceChecking {
    private let files: any FileSystemClient
    private let git: any GitStatusChecking
    private let catalog: RuleCatalog

    public init(files: any FileSystemClient, git: any GitStatusChecking, catalog: RuleCatalog) {
        self.files = files
        self.git = git
        self.catalog = catalog
    }

    public func verify(_ candidate: CleanupCandidate, evidence: CandidateEvidence) async throws {
        guard case .file(let url) = candidate.location else {
            // A Docker resource. Revalidated by the Docker client.
            return
        }

        if candidate.ruleID == manualLargeFileRuleID {
            // The user picked this file themselves; there is no manifest to
            // re-read. Scope and provenance are enforced separately by the
            // candidate store and the path policy.
            return
        }

        if let global = GlobalCacheRules.byID[candidate.ruleID] {
            try verifyGlobalCache(candidate, url: url, evidence: evidence, rule: global)
            return
        }

        guard projectRuleIDs.contains(candidate.ruleID) else {
            throw PolicyError.unsupported
        }
        try await verifyProjectArtifact(candidate, url: url, evidence: evidence)
    }

    // MARK: - Global caches

    private func verifyGlobalCache(
        _ candidate: CleanupCandidate,
        url: URL,
        evidence: CandidateEvidence,
        rule: GlobalCacheRule
    ) throws {
        guard let registeredRoot = evidence.allowedRoot else { throw PolicyError.outsideScope }

        let target = Self.components(url)
        let root = Self.components(registeredRoot)
        guard target == root || Self.isDescendant(target, of: root) else {
            throw PolicyError.outsideScope
        }

        let expected = RuleCatalog.digest(
            ruleID: candidate.ruleID,
            registeredRoot: registeredRoot
        )
        guard evidence.ruleEvidenceDigest == expected else { throw PolicyError.changed }
    }

    // MARK: - Project artifacts

    private func verifyProjectArtifact(
        _ candidate: CleanupCandidate,
        url: URL,
        evidence: CandidateEvidence
    ) async throws {
        guard let project = evidence.allowedRoot else { throw PolicyError.outsideScope }

        let current = try await catalog.matches(in: project, files: files, git: git)
        guard
            let match = current.first(where: {
                $0.ruleID == candidate.ruleID
                    && $0.url.standardizedFileURL == url.standardizedFileURL
            })
        else {
            // The catalog no longer offers this artifact. Something about the
            // project changed; refuse rather than reason about what.
            throw PolicyError.changed
        }
        guard match.evidenceDigest == evidence.ruleEvidenceDigest else {
            throw PolicyError.changed
        }
    }

    // MARK: - Paths

    private static func components(_ url: URL) -> [String] {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.pathComponents
            .map { $0.lowercased() }
    }

    private static func isDescendant(_ candidate: [String], of root: [String]) -> Bool {
        candidate.count > root.count && Array(candidate.prefix(root.count)) == root
    }
}
