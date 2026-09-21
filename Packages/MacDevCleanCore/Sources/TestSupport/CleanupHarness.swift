import Cleanup
import CleanupRules
import Domain
import Foundation
import Scanning

/// Wires the real validator and executor to fake destructive adapters.
///
/// Everything below the side effect is genuine: the actual candidate store, the
/// actual path policy, the actual rule evidence checker, the actual validator
/// and the actual executor. Only the three things that would touch the user's
/// machine are fakes — the Trash, the Docker daemon and the journal.
///
/// Fixtures live in a temporary directory this harness owns and removes. No
/// test reaches a real cache, the real Trash or a live daemon.
public final class CleanupHarness {
    public let tree: FixtureTree
    public let store: InMemoryCandidateStore
    public let trash: RecordingTrash
    public let docker: RecordingDocker
    public let journal: InMemoryJournal
    public let freeSpace: StubFreeSpace
    public let scanID = UUID()

    private let files = LocalFileSystem()
    private let git = FakeGitStatus()
    private let catalog = RuleCatalog()
    private let memoryContext: MemoryContext
    private let validator: CleanupPlanValidator
    private let executor: CleanupExecutor

    private var registered: [CleanupCandidate] = []
    private var evidence: [UUID: CandidateEvidence] = [:]
    private var safety: SafetyContext
    private var replacedOriginals: [URL] = []

    public init(
        candidates: [CleanupCandidate] = [],
        evidence: [UUID: CandidateEvidence] = [:],
        context: SafetyContext? = nil,
        clock: (any ClockProviding)? = nil,
        freeSpaceReadings: [Int64?] = [nil]
    ) async throws {
        tree = try FixtureTree()
        store = InMemoryCandidateStore()
        trash = RecordingTrash()
        docker = RecordingDocker()
        journal = InMemoryJournal()
        freeSpace = StubFreeSpace(readings: freeSpaceReadings)

        safety =
            context
            ?? SafetyContext(
                home: tree.root,
                projectRoots: [tree.root],
                largeFileRoots: [],
                globalRuleRoots: [:],
                exclusions: [],
                revision: 1
            )
        memoryContext = MemoryContext(value: safety)

        let resolvedClock = clock ?? FixedClock()
        let policy = PathPolicy(files: files)
        let rules = RuleEvidenceChecker(files: files, git: git, catalog: catalog)

        validator = CleanupPlanValidator(
            store: store,
            context: memoryContext,
            pathPolicy: policy,
            files: files,
            rules: rules,
            docker: docker,
            clock: resolvedClock
        )
        executor = CleanupExecutor(
            store: store,
            context: memoryContext,
            pathPolicy: policy,
            files: files,
            rules: rules,
            trash: trash,
            docker: docker,
            journal: journal,
            clock: resolvedClock,
            freeSpace: freeSpace
        )

        registered = candidates
        self.evidence = evidence
        await publishSnapshot()
    }

    deinit {
        try? tree.close()
    }

    // MARK: - Flow

    public func selection(
        for ids: Set<UUID>,
        irreversible: Bool,
        highRisk: Bool
    ) async -> CleanupSelection {
        CleanupSelection(
            scanID: scanID,
            candidateIDs: ids,
            acknowledgedIrreversible: irreversible,
            acknowledgedHighRisk: highRisk
        )
    }

    public func validate(_ selection: CleanupSelection) async throws -> ValidatedCleanupPlan {
        try await validator.validate(selection)
    }

    public func inspect(_ selection: CleanupSelection) async -> [ValidationIssue] {
        await validator.inspect(selection)
    }

    public func execute(_ plan: ValidatedCleanupPlan) async -> CleanupSummary {
        (try? await CleanupCollector.collect(executor.execute(plan)))
            ?? CleanupSummary(
                sessionID: plan.id, records: [], bytesMovedToTrash: 0, observedFreeSpaceDelta: nil)
        // A missing terminal summary is a real failure; callers that care use
        // `stream(for:)` and assert on it directly.
    }

    public func stream(for plan: ValidatedCleanupPlan) -> AsyncStream<CleanupEvent> {
        executor.execute(plan)
    }

    // MARK: - Building fixtures

    /// Creates a real artifact inside the owned tree, backed by real evidence,
    /// and registers it the way a scan would.
    ///
    /// `file` is a path relative to the fixture root. For a project rule its
    /// parent becomes the project directory and a matching manifest is written
    /// there. For a global cache rule the location is registered as that rule's
    /// exact allowed root.
    @discardableResult
    public func candidate(
        file: String,
        rule: CleanupRuleID = "node.modules",
        risk: RiskLevel = .low,
        bytes: Int = 4096
    ) async throws -> CleanupCandidate {
        let url = try tree.directory(file)
        _ = try tree.file(file + "/payload.bin", bytes: bytes)

        let allowedRoot: URL
        let digest: String
        let category: CleanupCategory
        let consequence: String

        if let global = GlobalCacheRules.byID[rule] {
            allowedRoot = url
            digest = RuleCatalog.digest(ruleID: rule, registeredRoot: url)
            category = global.category
            consequence = global.consequenceKey
            var roots = safety.globalRuleRoots
            roots[rule, default: []].append(url)
            safety = SafetyContext(
                home: safety.home,
                projectRoots: safety.projectRoots,
                largeFileRoots: safety.largeFileRoots,
                globalRuleRoots: roots,
                exclusions: safety.exclusions,
                revision: safety.revision
            )
            await memoryContext.update(safety)
        } else {
            let project = url.deletingLastPathComponent()
            try Data("{\"name\":\"fixture\"}".utf8)
                .write(to: project.appendingPathComponent("package.json"))
            let matches = try await catalog.matches(in: project, files: files, git: git)
            guard
                let match = matches.first(where: {
                    $0.ruleID == rule
                        && $0.url.standardizedFileURL.path == url.standardizedFileURL.path
                })
            else {
                throw HarnessError.noRuleEvidence(rule)
            }
            allowedRoot = match.allowedRoot
            digest = match.evidenceDigest
            category = match.category
            consequence = match.consequenceKey
        }

        let entry = try await files.entry(at: url)
        let candidate = CleanupCandidate(
            id: UUID(),
            ruleID: rule,
            location: .file(url),
            category: category,
            size: UInt64(bytes),
            allocatedSize: UInt64(bytes),
            risk: risk,
            method: .trash,
            consequenceKey: consequence
        )
        registered.append(candidate)
        evidence[candidate.id] = CandidateEvidence(
            identity: entry.identity,
            allowedRoot: allowedRoot,
            contextFingerprint: GlobalCacheRules.byID[rule] == nil ? "project" : "global",
            ruleEvidenceDigest: digest
        )
        await publishSnapshot()
        return candidate
    }

    /// Registers a Docker resource the way a Docker inventory would.
    @discardableResult
    public func dockerCandidate(
        kind: DockerOperation,
        identifier: String = "abc123",
        risk: RiskLevel = .high
    ) async -> CleanupCandidate {
        let candidate = CleanupCandidate(
            id: UUID(),
            ruleID: "docker.\(kind.rawValue)",
            location: .docker(
                context: "desktop-linux", builder: nil, kind: kind, id: identifier),
            category: .docker,
            size: nil,
            allocatedSize: nil,
            risk: risk,
            method: .docker(kind),
            consequenceKey: ConsequenceKey.rebuildOutput
        )
        registered.append(candidate)
        evidence[candidate.id] = CandidateEvidence(
            identity: nil,
            allowedRoot: nil,
            contextFingerprint: "docker",
            ruleEvidenceDigest: "fixture"
        )
        await publishSnapshot()
        return candidate
    }

    /// Swaps the target for a different object at the same path.
    ///
    /// The original is renamed rather than removed and is kept until the
    /// fixture is torn down, so nothing is ever unlinked at a path outside this
    /// harness's own temporary tree.
    public func replaceWithDifferentIdentity(_ id: UUID) async throws {
        guard let candidate = registered.first(where: { $0.id == id }),
            case .file(let url) = candidate.location
        else {
            throw HarnessError.unknownCandidate
        }

        let parked = url.deletingLastPathComponent()
            .appendingPathComponent("parked-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: url, to: parked)
        replacedOriginals.append(parked)

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        try Data("replacement".utf8).write(to: url.appendingPathComponent("payload.bin"))
    }

    /// Adds an exclusion and bumps the policy revision, as the application does
    /// when the user changes scope while a review screen is open.
    public func addExclusion(_ exclusion: Exclusion, bumpRevision: Bool = true) async {
        safety = SafetyContext(
            home: safety.home,
            projectRoots: safety.projectRoots,
            largeFileRoots: safety.largeFileRoots,
            globalRuleRoots: safety.globalRuleRoots,
            exclusions: safety.exclusions + [exclusion],
            revision: bumpRevision ? safety.revision + 1 : safety.revision
        )
        await memoryContext.update(safety)
    }

    /// Changes the policy revision without changing anything else.
    public func bumpPolicyRevision() async {
        safety = SafetyContext(
            home: safety.home,
            projectRoots: safety.projectRoots,
            largeFileRoots: safety.largeFileRoots,
            globalRuleRoots: safety.globalRuleRoots,
            exclusions: safety.exclusions,
            revision: safety.revision + 1
        )
        await memoryContext.update(safety)
    }

    public func currentSafetyContext() -> SafetyContext { safety }

    private func publishSnapshot() async {
        await store.save(
            ScanSnapshot(
                id: scanID,
                policyRevision: safety.revision,
                candidates: registered,
                evidence: evidence
            )
        )
    }

    public enum HarnessError: Error, Equatable {
        case noRuleEvidence(CleanupRuleID)
        case unknownCandidate
    }
}
