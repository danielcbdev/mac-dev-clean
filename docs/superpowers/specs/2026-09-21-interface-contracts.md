# Shared interface contracts

All task file paths are relative to the future repository root. Declare each public value with a public initializer accepting its stored properties in the order listed, unless the contract explicitly restricts construction. Give default empty collections only where shown. This avoids Swift's internal synthesized memberwise-initializer trap across targets.

## Dependency graph and file ownership

| Target | Production imports | Responsibility |
|---|---|---|
| Domain | Foundation | Sendable values and side-effect ports |
| CleanupRules | Domain, CryptoKit | Rule catalog; project evidence digests |
| Scanning | Domain, CleanupRules | Enumeration, measurement, registry |
| Cleanup | Domain | Validation capabilities, execution, journal coordination |
| DockerIntegration | Domain | Process adapter, discovery and external operations |
| Persistence | Domain, SwiftData | Actor-isolated repositories |
| MacDevCleanApp | all package products, SwiftUI, AppKit, OSLog | Composition, feature models, native UI |
| TestSupport | Domain, CleanupRules, Scanning, Cleanup | Fixtures and fakes; test consumers only |

Dependencies may not point from Domain to another target or from any core target to App. Cleanup uses DockerClient protocol from Domain, so it does not import DockerIntegration. Expose a multi-target library product MacDevCleanCore and individual products where Xcode needs them.

## Domain/ScanTypes.swift (plan 01)

```swift
import Foundation

public typealias ByteCount = UInt64
public typealias CleanupRuleID = String
public enum RiskLevel: String, Codable, Sendable { case low, medium, high }
public enum CleanupCategory: String, Codable, Sendable, CaseIterable {
    case node, webBuild, flutter, xcode, simulator, cocoaPods, homebrew
    case gradle, python, rust, yarn, pnpm, bun, docker, largeFiles
}
public enum DockerOperation: String, Codable, Sendable {
    case container, image, volume, buildCache
}
public enum CleanupMethod: Codable, Sendable, Equatable {
    case trash
    case docker(DockerOperation)
}
public enum CleanupLocation: Codable, Sendable, Hashable {
    case file(URL)
    case docker(context: String, builder: String?, kind: DockerOperation, id: String)
}
public struct ScanRoot: Codable, Sendable, Hashable {
    public let url: URL
}
public struct ScanRequest: Sendable {
    public let roots: [ScanRoot]
    public let includeGlobalCaches: Bool
}
public struct FileIdentity: Codable, Sendable, Hashable {
    public let device: UInt64
    public let inode: UInt64
    public let modifiedNanoseconds: Int64
}
public struct CleanupCandidate: Identifiable, Codable, Sendable {
    public let id: UUID
    public let ruleID: CleanupRuleID
    public let location: CleanupLocation
    public let category: CleanupCategory
    public let size: ByteCount?
    public let allocatedSize: ByteCount?
    public let risk: RiskLevel
    public let method: CleanupMethod
    public let consequenceKey: String
}
public struct CandidateEvidence: Sendable {
    public let identity: FileIdentity?
    public let allowedRoot: URL?
    public let contextFingerprint: String?
    public let ruleEvidenceDigest: String
}
public struct ScanSnapshot: Sendable {
    public let id: UUID
    public let policyRevision: UInt64
    public let candidates: [CleanupCandidate]
    public let evidence: [UUID: CandidateEvidence]
}
public enum ScanEvent: Sendable {
    case progress(visited: Int)
    case issue(code: String, relativePath: String?)
    case completed(ScanSnapshot)
}
public protocol ScanService: Sendable {
    func scan(_ request: ScanRequest) -> AsyncThrowingStream<ScanEvent, Error>
}
```

Also add Hashable to DockerOperation (needed by CleanupLocation). Add Equatable to values used in equality tests. Byte summation uses addingReportingOverflow; overflow results in unknown total plus an issue, never a wraparound.

## Domain/PolicyTypes.swift (plan 01), implemented in plan 02

```swift
public enum Exclusion: Codable, Sendable, Hashable {
    case path(URL)
    case category(CleanupCategory)
    case rule(CleanupRuleID)
}
public struct SafetyContext: Sendable {
    public let home: URL
    public let projectRoots: [URL]
    public let largeFileRoots: [URL]
    public let globalRuleRoots: [CleanupRuleID: [URL]]
    public let exclusions: [Exclusion]
    public let revision: UInt64
}
public enum PolicyError: String, Error, Codable, Sendable {
    case protectedPath, outsideScope, excluded, changed, missing, symbolicLink
    case unknownCandidate, staleScan, consentRequired, expiredPlan, usedPlan
    case unsupported, unavailable, permissionDenied, cancelled, journalUnavailable
}
public protocol SafetyContextProviding: Sendable {
    func current() async throws -> SafetyContext
}
public protocol CandidateStore: Sendable {
    func save(_ snapshot: ScanSnapshot) async
    func lookup(scanID: UUID, candidateID: UUID) async throws
        -> (CleanupCandidate, CandidateEvidence, UInt64)
    func invalidate() async
}
public protocol PathPolicyChecking: Sendable {
    func check(_ url: URL, ruleID: CleanupRuleID, context: SafetyContext) async throws
    func matches(_ url: URL, exclusion: URL) async throws -> Bool
}
public protocol ClockProviding: Sendable {
    func now() -> Date
}
public protocol RuleEvidenceChecking: Sendable {
    func verify(_ candidate: CleanupCandidate, evidence: CandidateEvidence) async throws
}
```

CandidateStore is an actor-owned snapshot registry. UI presents candidates but cleanup accepts only UUID references, not forged candidate values. Policy revision increments for roots, exclusions and supported-rule changes.

## Domain/FileSystemClient.swift (plan 02)

```swift
public enum EntryKind: Sendable { case directory, file, symbolicLink, other }
public struct FileEntry: Sendable {
    public let url: URL
    public let kind: EntryKind
    public let identity: FileIdentity
    public let logicalBytes: UInt64?
    public let allocatedBytes: UInt64?
    public let isMount: Bool
    public let isCloudPlaceholder: Bool
}
public protocol FileSystemClient: Sendable {
    func children(of url: URL) async throws -> [FileEntry]
    func entry(at url: URL) async throws -> FileEntry
    func readPrefix(at url: URL, limit: Int) async throws -> Data
}
public protocol GitStatusChecking: Sendable {
    func containsTrackedFiles(at url: URL, repository: URL) async throws -> Bool
    func isIgnored(_ url: URL, repository: URL) async throws -> Bool
}
```

FileSystemClient uses lstat semantics (including ancestor checks); no synchronous filesystem work on MainActor. The real implementation uses a bounded serial utility DispatchQueue bridged via continuation, checks cancellation between enumeration chunks, and does not use unchecked Sendable on mutable state. Directory enumeration errors become partial scan issues. Do not download cloud placeholders for measurement.

## CleanupRules/RuleCatalog.swift (plan 02)

```swift
public struct RuleMatch: Sendable {
    public let ruleID: String
    public let url: URL
    public let category: CleanupCategory
    public let risk: RiskLevel
    public let consequenceKey: String
    public let allowedRoot: URL
    public let evidenceDigest: String
}
public struct RuleCatalog: Sendable {
    public init()
    public func matches(in project: URL, files: any FileSystemClient,
                        git: any GitStatusChecking) async throws -> [RuleMatch]
    public func globalRoots(home: URL) -> [CleanupRuleID: [URL]]
}
```

Scanning/DeveloperScanner.swift implements ScanService with init(files:catalog:git:context:store:). Scanning/PathPolicy.swift implements PathPolicyChecking with init(files:). Scanning/InMemoryCandidateStore.swift is an actor implementing CandidateStore. Candidate IDs are stable during one snapshot; a new scan produces a new snapshot ID.

CleanupRules/RuleEvidenceChecker.swift implements RuleEvidenceChecking with init(files:git:catalog:). It verifies a registered rule, literal output scope and current project/Git evidence against the stored digest. For manual.largeFile it performs no manifest check; the validator separately enforces registered scan provenance and explicit scope through the store and PathPolicy. Global cache rules require their exact registered root. Unknown rule IDs throw PolicyError.unsupported. Fixed project IDs: node.modules, node.turbo, web.dist, flutter.build, flutter.dartTool, flutter.plugins, flutter.pluginDependencies. Global IDs are defined in plan 02.

## Cleanup/CleanupPlan.swift and CleanupProtocols.swift (plan 03)

```swift
public struct CleanupSelection: Sendable {
    public let scanID: UUID
    public let candidateIDs: Set<UUID>
    public let acknowledgedIrreversible: Bool
    public let acknowledgedHighRisk: Bool
}
public struct ValidatedCleanupItem: Sendable {
    public let candidate: CleanupCandidate
    let evidence: CandidateEvidence
    // Internal initializer, not public.
}
public struct ValidatedCleanupPlan: Sendable {
    public let id: UUID
    public let items: [ValidatedCleanupItem]
    public let expiresAt: Date
    let policyRevision: UInt64
    // Internal initializer, not public; no public decoding.
}
public protocol CleanupPlanValidating: Sendable {
    func validate(_ selection: CleanupSelection) async throws -> ValidatedCleanupPlan
}
public enum ItemOutcome: String, Codable, Sendable {
    case pending, movedToTrash, removed, skipped, failed, cancelled, indeterminate
}
public struct CleanupRecord: Identifiable, Codable, Sendable {
    public let id: UUID
    public let candidate: CleanupCandidate
    public let outcome: ItemOutcome
    public let resultingTrashURL: URL?
    public let errorCode: String?
    public let finishedAt: Date?
}
public struct CleanupSummary: Codable, Sendable {
    public let sessionID: UUID
    public let records: [CleanupRecord]
    public let bytesMovedToTrash: UInt64
    public let observedFreeSpaceDelta: Int64?
}
public enum CleanupEvent: Sendable {
    case started(UUID)
    case item(CleanupRecord)
    case finished(CleanupSummary)
}
public protocol CleanupExecuting: Sendable {
    func execute(_ plan: ValidatedCleanupPlan) -> AsyncStream<CleanupEvent>
}
```

Declare ItemOutcome, CleanupRecord and CleanupSummary in Domain/HistoryTypes.swift in plan 01 so repositories and UI have no cycle; implementation behavior arrives in plan 03. CleanupSelection and validated types stay in Cleanup. Default plan lifetime 60 seconds; tokens consumed exactly once by one executor actor. Revalidate each item immediately before its side effect. UI acknowledgment is a policy gate, not a cryptographic claim about human identity.

CleanupPlanValidator init(store:context:pathPolicy:files:rules:docker:clock:) and CleanupExecutor init(store:context:pathPolicy:files:rules:trash:docker:journal:clock:). These initializers accept the corresponding protocols from these contracts; rules is any RuleEvidenceChecking. Both validation and execution recheck rule evidence so a newly tracked dist directory cannot bypass policy using an old scan.

## Domain/SideEffectPorts.swift (declarations plan 01, behavior plan 03, Docker details plan 04)

```swift
public protocol TrashClient: Sendable {
    func moveToTrash(_ url: URL) async throws -> URL
}
public protocol CleanupJournal: Sendable {
    func begin(sessionID: UUID, candidates: [CleanupCandidate], at: Date) async throws
    func record(sessionID: UUID, record: CleanupRecord) async throws
    func finish(_ summary: CleanupSummary, at: Date) async throws
}
public struct DockerInventory: Sendable {
    public let fingerprint: String
    public let candidates: [CleanupCandidate]
    public let evidence: [UUID: CandidateEvidence]
}
public protocol DockerClient: Sendable {
    func inventory() async throws -> DockerInventory
    func revalidate(_ item: CleanupCandidate, evidence: CandidateEvidence) async throws
    func remove(_ item: CleanupCandidate) async throws
}
```

Journal failure before a side effect aborts execution. If recording fails after a side effect, stop scheduling and expose the result as potentially unrecorded; never repeat the side effect to “fix” history. On restart pending records become indeterminate, never assumed successful.

## Domain/PersistenceTypes.swift (plan 01 declarations; plan 07 durable implementation)

```swift
public enum AppLanguage: String, Codable, Sendable { case system, english, portugueseBrazil }
public enum AppAppearance: String, Codable, Sendable { case system, light, dark }
public enum HistoryRetention: Int, Codable, Sendable { case forever = 0, days30 = 30, days90 = 90 }
public struct AppPreferences: Codable, Sendable, Equatable {
    public var scanOnLaunch: Bool = false
    public var largeFileThreshold: UInt64 = 1_000_000_000
    public var language: AppLanguage = .system
    public var appearance: AppAppearance = .system
    public var retention: HistoryRetention = .forever
    public init() {}
}
public struct HistorySession: Identifiable, Codable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let completedAt: Date?
    public let summary: CleanupSummary?
    public let records: [CleanupRecord]
}
public protocol SettingsRepository: Sendable {
    func preferences() async throws -> AppPreferences
    func savePreferences(_ value: AppPreferences) async throws
    func roots() async throws -> [ScanRoot]
    func saveRoots(_ value: [ScanRoot]) async throws
    func exclusions() async throws -> [Exclusion]
    func saveExclusions(_ value: [Exclusion]) async throws
}
public protocol HistoryRepository: CleanupJournal {
    func sessions() async throws -> [HistorySession]
    func clear() async throws
    func applyRetention(_ retention: HistoryRetention, now: Date) async throws
    func recoverInterruptedSessions() async throws
}
```

App/SessionRepositories.swift (plan 05) implements SettingsRepository and HistoryRepository for an intermediate app demo; TestSupport/InMemoryJournal implements HistoryRepository for tests. SwiftDataRepositories (plan 07) implements both in one model actor. AppSafetyContextProvider derives a context from settings plus the rule catalog, increments revision, and invalidates the candidate store on scope changes. Production cleanup stays disabled until durable persistence is composed.

## Domain/LargeFileTypes.swift (plan 06)

```swift
public struct LargeFileRequest: Sendable {
    public let roots: [ScanRoot]
    public let minimumBytes: UInt64
}
public struct LargeFileRow: Identifiable, Sendable {
    public let id: UUID
    public let url: URL
    public let logicalBytes: UInt64
    public let modifiedAt: Date
    public let kindDescription: String
    public let canSelect: Bool
}
public enum LargeFileEvent: Sendable {
    case progress(Int)
    case issue(String)
    case completed(rows: [LargeFileRow], snapshot: ScanSnapshot)
}
public protocol LargeFileScanning: Sendable {
    func scan(_ request: LargeFileRequest) -> AsyncThrowingStream<LargeFileEvent, Error>
}
```

LargeFileScanner init(files:context:store:). Its regular-file candidates use ruleID manual.largeFile, category largeFiles, risk high, method trash. Reuse the cleanup validator; allowed scope uses context.largeFileRoots, not projectRoots.

## App-facing adapters and feature model interfaces (plan 05 onward)

```swift
@MainActor protocol FolderPicking {
    func chooseFolders() async -> [URL] // cancellation returns []
}
@MainActor protocol WorkspaceOpening {
    func reveal(_ url: URL)
    func openTrash()
}
@MainActor @Observable final class ScanModel {
    private(set) var snapshot: ScanSnapshot?
    private(set) var isScanning = false
    private(set) var visited = 0
    private(set) var issueCodes: [String] = []
    var selectedIDs: Set<UUID> = []
    // init(scanner: any ScanService)
    func start(_ request: ScanRequest)
    func cancel()
}
@MainActor @Observable final class ReviewModel {
    private(set) var results: [CleanupRecord] = []
    private(set) var isRunning = false
    var acknowledgeIrreversible = false
    var acknowledgeHighRisk = false
    // init(validator: any CleanupPlanValidating, executor: any CleanupExecuting)
    func confirm(scanID: UUID, ids: Set<UUID>) async
    func cancel()
}
```

Use enum-backed states internally if that prevents invalid combinations. Keep public presentation semantics above consistent. RootCoordinator owns navigation and services; ScanModel never creates filesystem clients itself. Settings/history feature models receive repositories. Scan progress includes an indeterminate indicator and visited count; no fabricated completion percentage.

## Fixture support contracts (grow with each owner task)

TestSupport/FixtureTree.swift owns a unique temporary directory and exposes init(), root: URL, directory(_:), file(_:bytes:), symlink(_:to:), close(). Each relative path rejects .. and absolute input; close removes only its validated owned temporary root.

TestSupport/Fakes.swift provides:
- FixedClock(now:) implements ClockProviding; returns its fixed Date.
- MemoryContext(value:) actor implements SafetyContextProviding with update(_:) to change scope.
- RecordingTrash actor implements TrashClient, calls() -> [URL], fail(for:) and a deterministic fixture result URL.
- RecordingDocker actor implements DockerClient, removalCalls() -> [UUID], with fail(for:), setInventory(_:) and assertable context changes.
- InMemoryJournal actor implements HistoryRepository; records exactly successful writes and can inject one failing journal operation.
- FakeGitStatus implements GitStatusChecking with explicit tracked/ignored path sets.
- ScanCollector.collect(_:) async throws -> ScanSnapshot drains events, throws if no completed event.
- CleanupCollector.collect(_:) async -> CleanupSummary drains events; a missing terminal summary fails the test.

Create CleanupHarness in plan 03: async throwing init(candidates: [CleanupCandidate] = [], evidence: [UUID: CandidateEvidence] = [:], context: SafetyContext? = nil, clock: (any ClockProviding)? = nil) wires actual registry, path policy, validator and executor to RecordingTrash, RecordingDocker and InMemoryJournal. A nil context creates an owned fixture-home/root; a nil clock uses a fixed test date. Expose trash and journal actor references for assertions. Methods selection(for ids: Set<UUID>, irreversible: Bool, highRisk: Bool) async -> CleanupSelection, validate(_ selection: CleanupSelection) async throws -> ValidatedCleanupPlan and execute(_ plan: ValidatedCleanupPlan) async -> CleanupSummary expose real flow, not a stubbed validator. candidate(file: String, rule: String, risk: RiskLevel) async throws -> CleanupCandidate creates project evidence inside its owned tree and registers the actual identity. replaceWithDifferentIdentity(_ id: UUID) async throws performs an owned-fixture rename/create. The harness registers each accumulated snapshot consistently and includes selected IDs only from its own store.

Do not use harness defaults that silently consent or bypass identity policy. Actual XCTest files use @testable import only for the target under test, and public imports for neighbors.
