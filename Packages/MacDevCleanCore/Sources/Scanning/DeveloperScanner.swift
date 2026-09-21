import CleanupRules
import Domain
import Foundation

/// Finds supported developer artifacts inside approved roots and measures them.
///
/// The scan streams: progress arrives while work continues, cancellation stops
/// the work rather than merely hiding it, and a subtree that cannot be read
/// costs only that subtree.
///
/// Two traversals happen, with deliberately different rules:
///
/// - **Discovery** looks for project manifests and never enters dependency
///   trees, generated output, `.git`, bundles, mounts or symbolic links.
/// - **Measurement** walks a candidate that is already approved, so it counts
///   everything that would really move to the Trash. It still refuses to follow
///   a symbolic link, cross onto another volume, or materialise a cloud
///   placeholder — the last is recorded as an unknown size instead.
///
/// Only regular files contribute bytes. Directory metadata is not counted, so
/// the figure is an estimate of content and is never presented as a prediction
/// of reclaimed space.
public struct DeveloperScanner: ScanService {
    /// Progress is reported at most this often, so a scan of a large tree does
    /// not spend its time publishing events.
    private static let progressEntryInterval = 256
    private static let progressTimeInterval: TimeInterval = 0.1

    private let files: any FileSystemClient
    private let catalog: RuleCatalog
    private let git: any GitStatusChecking
    private let context: any SafetyContextProviding
    private let store: any CandidateStore

    public init(
        files: any FileSystemClient,
        catalog: RuleCatalog,
        git: any GitStatusChecking,
        context: any SafetyContextProviding,
        store: any CandidateStore
    ) {
        self.files = files
        self.catalog = catalog
        self.git = git
        self.context = context
        self.store = store
    }

    public func scan(_ request: ScanRequest) -> AsyncThrowingStream<ScanEvent, Error> {
        // Unbounded on purpose. A bounded buffer would drop events under
        // pressure, and the completed snapshot is the one event that must never
        // be lost. Volume is controlled at the source instead: progress is
        // throttled, so the number of events stays small however large the tree.
        AsyncThrowingStream(ScanEvent.self, bufferingPolicy: .unbounded) { continuation in
            let work = Task {
                do {
                    try await run(request, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    // MARK: - The scan

    private func run(
        _ request: ScanRequest,
        into continuation: AsyncThrowingStream<ScanEvent, Error>.Continuation
    ) async throws {
        let safety = try await context.current()
        let policy = PathPolicy(files: files)
        var reporter = ProgressReporter(continuation: continuation)

        let roots = Self.deduplicate(request.roots.map(\.url))
        var proposals: [Proposal] = []

        for root in roots {
            try Task.checkCancellation()
            let discovery = try await ProjectDiscovery(files: files).discover(in: root)
            reporter.advance(by: discovery.visited)
            for issue in discovery.issues {
                continuation.yield(
                    .issue(code: issue.code, relativePath: Self.relative(issue.url, to: root))
                )
            }

            for project in discovery.projects {
                try Task.checkCancellation()
                let matches = try await catalog.matches(in: project, files: files, git: git)
                proposals.append(
                    contentsOf: matches.map { Proposal(match: $0, scope: "project", root: root) }
                )
            }
        }

        if request.includeGlobalCaches {
            proposals.append(contentsOf: try await globalProposals(safety))
        }

        let approved = try await approve(
            proposals,
            safety: safety,
            policy: policy,
            continuation: continuation
        )

        var candidates: [CleanupCandidate] = []
        var evidence: [UUID: CandidateEvidence] = [:]

        for proposal in Self.maximal(approved) {
            try Task.checkCancellation()
            guard
                let measured = try await measure(
                    proposal,
                    reporter: &reporter,
                    continuation: continuation
                )
            else { continue }
            candidates.append(measured.candidate)
            evidence[measured.candidate.id] = measured.evidence
        }

        try Task.checkCancellation()

        let snapshot = ScanSnapshot(
            id: UUID(),
            policyRevision: safety.revision,
            candidates: candidates,
            evidence: evidence
        )
        // Registered before it is announced, so the identifiers the interface
        // receives can always be resolved.
        await store.save(snapshot)
        continuation.yield(.completed(snapshot))
    }

    // MARK: - Proposals

    private struct Proposal {
        let match: RuleMatch
        /// "project" or "global": which kind of scope authorised this location.
        let scope: String
        let root: URL
    }

    private func globalProposals(_ safety: SafetyContext) async throws -> [Proposal] {
        var proposals: [Proposal] = []
        for rule in GlobalCacheRules.all {
            for registered in safety.globalRuleRoots[rule.id] ?? [] {
                try Task.checkCancellation()
                guard let entry = try? await files.entry(at: registered),
                    entry.kind == .directory
                else { continue }
                proposals.append(
                    Proposal(
                        match: RuleMatch(
                            ruleID: rule.id,
                            url: registered,
                            category: rule.category,
                            risk: rule.risk,
                            consequenceKey: rule.consequenceKey,
                            allowedRoot: registered,
                            evidenceDigest: RuleCatalog.digest(
                                ruleID: rule.id, registeredRoot: registered)
                        ),
                        scope: "global",
                        root: registered
                    )
                )
            }
        }
        return proposals
    }

    private func approve(
        _ proposals: [Proposal],
        safety: SafetyContext,
        policy: PathPolicy,
        continuation: AsyncThrowingStream<ScanEvent, Error>.Continuation
    ) async throws -> [Proposal] {
        var approved: [Proposal] = []
        var seen: Set<String> = []
        let excludedCategories = Set(
            safety.exclusions.compactMap { exclusion -> CleanupCategory? in
                if case .category(let category) = exclusion { return category }
                return nil
            }
        )

        for proposal in proposals {
            try Task.checkCancellation()
            let key = proposal.match.url.standardizedFileURL.path
            guard seen.insert(key).inserted else { continue }

            // Category exclusions are applied here, where the category is
            // known. Path and rule exclusions are the policy's job.
            guard !excludedCategories.contains(proposal.match.category) else { continue }

            do {
                try await policy.check(
                    proposal.match.url,
                    ruleID: proposal.match.ruleID,
                    context: safety
                )
                approved.append(proposal)
            } catch PolicyError.excluded {
                // Silent: the user asked for this. Not a problem to report.
                continue
            } catch let error as PolicyError {
                continuation.yield(
                    .issue(
                        code: Self.issueCode(for: error),
                        relativePath: Self.relative(proposal.match.url, to: proposal.root)
                    )
                )
            }
        }
        return approved
    }

    /// Keeps only the outermost of any nested pair, so one location is never
    /// offered twice under two names.
    private static func maximal(_ proposals: [Proposal]) -> [Proposal] {
        let components = proposals.map {
            PathPolicy.canonical($0.match.url).pathComponents.map { $0.lowercased() }
        }
        return proposals.enumerated().filter { index, _ in
            !components.indices.contains { other in
                other != index
                    && PathPolicy.componentDescendant(components[index], of: components[other])
            }
        }.map(\.element)
    }

    // MARK: - Measurement

    private struct Measured {
        let candidate: CleanupCandidate
        let evidence: CandidateEvidence
    }

    private func measure(
        _ proposal: Proposal,
        reporter: inout ProgressReporter,
        continuation: AsyncThrowingStream<ScanEvent, Error>.Continuation
    ) async throws -> Measured? {
        guard let target = try? await files.entry(at: proposal.match.url) else { return nil }

        var sum = SizeAccumulator()
        var overflowed = false

        if target.kind == .file {
            try? sum.add(
                logical: target.logicalBytes,
                allocated: target.allocatedBytes,
                identity: target.identity
            )
        } else {
            var pending: [URL] = [proposal.match.url]
            while let current = pending.popLast() {
                try Task.checkCancellation()

                let children: [FileEntry]
                do {
                    children = try await files.children(of: current)
                } catch is CancellationError {
                    // A cancelled filesystem operation is not a partial
                    // measurement failure. Propagate it so no later subtree
                    // is scheduled after the user has stopped the scan.
                    throw CancellationError()
                } catch {
                    sum.noteUnknown()
                    continuation.yield(
                        .issue(
                            code: ProjectDiscovery.issueCode(for: error),
                            relativePath: Self.relative(current, to: proposal.match.url)
                        )
                    )
                    continue
                }
                reporter.advance(by: children.count)

                for child in children {
                    // Never followed: the bytes behind a link are not inside
                    // this candidate and will not move with it.
                    guard child.kind != .symbolicLink else { continue }
                    // Another volume will not move with this item either.
                    guard !child.isMount else { continue }
                    guard child.identity.device == target.identity.device else { continue }
                    if child.isCloudPlaceholder {
                        // Measuring it would make the provider download it.
                        sum.noteUnknown()
                        continue
                    }

                    if child.kind == .directory {
                        pending.append(child.url)
                    } else if child.kind == .file {
                        do {
                            try sum.add(
                                logical: child.logicalBytes,
                                allocated: child.allocatedBytes,
                                identity: child.identity
                            )
                        } catch {
                            overflowed = true
                        }
                    }
                }
            }
        }

        if overflowed {
            sum.noteUnknown()
            continuation.yield(
                .issue(code: ScanIssueCode.sizeOverflow, relativePath: nil)
            )
        }
        if sum.hasUnknownSizes {
            continuation.yield(
                .issue(
                    code: ScanIssueCode.sizeUnavailable,
                    relativePath: Self.relative(proposal.match.url, to: proposal.root)
                )
            )
        }

        let candidate = CleanupCandidate(
            id: UUID(),
            ruleID: proposal.match.ruleID,
            location: .file(proposal.match.url),
            category: proposal.match.category,
            size: sum.reportedLogicalBytes,
            allocatedSize: sum.reportedAllocatedBytes,
            risk: proposal.match.risk,
            method: .trash,
            consequenceKey: proposal.match.consequenceKey
        )
        let evidence = CandidateEvidence(
            identity: target.identity,
            allowedRoot: proposal.match.allowedRoot,
            contextFingerprint: proposal.scope,
            ruleEvidenceDigest: proposal.match.evidenceDigest
        )
        return Measured(candidate: candidate, evidence: evidence)
    }

    // MARK: - Progress

    /// Publishes a visited count at most every 256 entries or 100 ms.
    private struct ProgressReporter {
        let continuation: AsyncThrowingStream<ScanEvent, Error>.Continuation
        private var visited = 0
        private var lastReported = 0
        private var lastReportedAt = Date()

        init(continuation: AsyncThrowingStream<ScanEvent, Error>.Continuation) {
            self.continuation = continuation
        }

        mutating func advance(by count: Int) {
            visited += count
            let now = Date()
            guard
                visited - lastReported >= DeveloperScanner.progressEntryInterval
                    || now.timeIntervalSince(lastReportedAt)
                        >= DeveloperScanner.progressTimeInterval
            else { return }
            lastReported = visited
            lastReportedAt = now
            continuation.yield(.progress(visited: visited))
        }
    }

    // MARK: - Helpers

    /// Drops duplicates and any root already contained by another, so an item
    /// inside two overlapping roots is measured and shown once.
    static func deduplicate(_ roots: [URL]) -> [URL] {
        let canonical = roots.map { PathPolicy.canonical($0) }
        var unique: [URL] = []
        var seen: Set<String> = []
        for root in canonical where seen.insert(root.path).inserted {
            unique.append(root)
        }
        let components = unique.map { $0.pathComponents.map { $0.lowercased() } }
        return unique.enumerated().filter { index, _ in
            !components.indices.contains { other in
                other != index
                    && PathPolicy.componentDescendant(components[index], of: components[other])
            }
        }.map(\.element)
    }

    private static func issueCode(for error: PolicyError) -> String {
        switch error {
        case .permissionDenied: return ScanIssueCode.permissionDenied
        case .symbolicLink: return ScanIssueCode.symbolicLinkSkipped
        case .protectedPath: return ScanIssueCode.mountSkipped
        case .unsupported: return ScanIssueCode.ambiguousArtifact
        case .missing: return ScanIssueCode.unreadable
        default: return ScanIssueCode.unreadable
        }
    }

    /// A path relative to the scanned root. Issue reports never carry the
    /// user's full path.
    private static func relative(_ url: URL, to root: URL) -> String? {
        let target = PathPolicy.canonical(url).pathComponents
        let base = PathPolicy.canonical(root).pathComponents
        guard PathPolicy.componentDescendant(target, of: base) else { return nil }
        return target.dropFirst(base.count).joined(separator: "/")
    }
}
