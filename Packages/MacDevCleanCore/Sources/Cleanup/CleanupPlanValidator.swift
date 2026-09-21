import Domain
import Foundation

/// Turns a set of identifiers into an authorisation, or refuses.
///
/// Nothing the caller supplies except the identifiers is trusted. The
/// candidate's path, rule, risk and method all come from the registered scan
/// snapshot, so a caller cannot present an arbitrary path as a low-risk cache.
///
/// Every check runs again here even though the scanner already ran it, because
/// the world moves between a scan and a confirmation: an exclusion may have been
/// added, a directory replaced, a project's manifest changed.
public struct CleanupPlanValidator: CleanupPlanValidating {
    private let store: any CandidateStore
    private let context: any SafetyContextProviding
    private let pathPolicy: any PathPolicyChecking
    private let files: any FileSystemClient
    private let rules: any RuleEvidenceChecking
    private let docker: any DockerClient
    private let clock: any ClockProviding

    public init(
        store: any CandidateStore,
        context: any SafetyContextProviding,
        pathPolicy: any PathPolicyChecking,
        files: any FileSystemClient,
        rules: any RuleEvidenceChecking,
        docker: any DockerClient,
        clock: any ClockProviding
    ) {
        self.store = store
        self.context = context
        self.pathPolicy = pathPolicy
        self.files = files
        self.rules = rules
        self.docker = docker
        self.clock = clock
    }

    public func validate(_ selection: CleanupSelection) async throws -> ValidatedCleanupPlan {
        guard !selection.candidateIDs.isEmpty else { throw PolicyError.unsupported }

        let safety = try await context.current()
        var items: [ValidatedCleanupItem] = []

        for id in selection.candidateIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            // A partially valid selection never becomes a partial plan. The
            // first refusal stops the whole thing, so nothing is dropped
            // quietly and the user is told to look again.
            let (candidate, evidence, _) = try await resolve(
                id, selection: selection, safety: safety)
            items.append(ValidatedCleanupItem(candidate: candidate, evidence: evidence))
        }

        // Deterministic order: by location, then identifier. Two validations of
        // the same selection produce the same plan.
        items.sort {
            let left = Self.sortKey($0.candidate)
            let right = Self.sortKey($1.candidate)
            return left == right
                ? $0.candidate.id.uuidString < $1.candidate.id.uuidString
                : left < right
        }

        return ValidatedCleanupPlan(
            id: UUID(),
            items: items,
            expiresAt: clock.now().addingTimeInterval(cleanupPlanLifetime),
            policyRevision: safety.revision
        )
    }

    public func inspect(_ selection: CleanupSelection) async -> [ValidationIssue] {
        guard let safety = try? await context.current() else {
            return selection.candidateIDs.map {
                ValidationIssue(candidateID: $0, code: .unavailable)
            }
        }

        var issues: [ValidationIssue] = []
        for id in selection.candidateIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            do {
                _ = try await resolve(id, selection: selection, safety: safety)
            } catch let error as PolicyError {
                issues.append(ValidationIssue(candidateID: id, code: error))
            } catch {
                issues.append(ValidationIssue(candidateID: id, code: .unavailable))
            }
        }
        return issues
    }

    // MARK: - One candidate

    private func resolve(
        _ id: UUID,
        selection: CleanupSelection,
        safety: SafetyContext
    ) async throws -> (CleanupCandidate, CandidateEvidence, UInt64) {
        let (candidate, evidence, revision) = try await store.lookup(
            scanID: selection.scanID,
            candidateID: id
        )

        // Roots, exclusions or supported rules changed since the scan. The
        // snapshot describes a world that no longer exists.
        guard revision == safety.revision else { throw PolicyError.staleScan }

        if candidate.risk == .high, !selection.acknowledgedHighRisk {
            throw PolicyError.consentRequired
        }
        if case .docker = candidate.method, !selection.acknowledgedIrreversible {
            throw PolicyError.consentRequired
        }

        // Category exclusions live here rather than in the path policy, which
        // is given a rule identifier and cannot see a category.
        if safety.exclusions.contains(.category(candidate.category)) {
            throw PolicyError.excluded
        }

        switch candidate.location {
        case .file(let url):
            try await pathPolicy.check(url, ruleID: candidate.ruleID, context: safety)
            let entry = try await files.entry(at: url)
            guard let recorded = evidence.identity, entry.identity == recorded else {
                // Something else is at this path now.
                throw PolicyError.changed
            }
            try await rules.verify(candidate, evidence: evidence)

        case .docker:
            try await docker.revalidate(candidate, evidence: evidence)
        }

        return (candidate, evidence, revision)
    }

    private static func sortKey(_ candidate: CleanupCandidate) -> String {
        switch candidate.location {
        case .file(let url): return url.standardizedFileURL.path
        case .docker(let context, _, let kind, let id):
            return "docker:\(context):\(kind.rawValue):\(id)"
        }
    }
}
