import Domain
import Persistence
import Scanning
import TestSupport
import XCTest

@testable import MacDevClean

/// Asserts the application composes durable storage, and behaves correctly when
/// it cannot.
@MainActor
final class RepositoryWiringTests: XCTestCase {

    func testDurableStorageIsWhatEnablesCleanup() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let durable = try SwiftDataRepositories.make(
            containerURL: tree.root.appendingPathComponent("store/macdevclean.sqlite"))

        XCTAssertTrue(
            durable.isDurable,
            "the app offers cleanup only when the record of it will survive a quit")
        XCTAssertFalse(
            SessionRepositories().isDurable,
            "in-memory storage must never be mistaken for durable")
    }

    func testTheStoreLivesInApplicationSupportUnderTheAppName() throws {
        let url = try AppDependencies.storeURL()

        XCTAssertEqual(url.lastPathComponent, "store.sqlite")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "MacDevClean")
        XCTAssertTrue(url.path.contains("Application Support"))
    }

    func testAChangedScopeInvalidatesRegisteredSnapshots() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let repository = try SwiftDataRepositories.make(containerURL: nil, inMemory: true)
        let store = InMemoryCandidateStore()
        let provider = AppSafetyContextProvider(
            settings: repository, store: store, home: tree.root)

        let candidate = CleanupCandidate(
            id: UUID(), ruleID: "node.modules",
            location: .file(tree.root.appendingPathComponent("a/node_modules")),
            category: .node, size: 1, allocatedSize: 1, risk: .low, method: .trash,
            consequenceKey: ConsequenceKey.reinstallDependencies)
        let scanID = UUID()
        await store.save(
            ScanSnapshot(
                id: scanID, policyRevision: 1, candidates: [candidate],
                evidence: [
                    candidate.id: CandidateEvidence(
                        identity: nil, allowedRoot: nil, contextFingerprint: nil,
                        ruleEvidenceDigest: "x")
                ]))
        let before = try await provider.current().revision

        await provider.invalidateAfterSettingsChange()

        let after = try await provider.current().revision
        XCTAssertGreaterThan(after, before, "a scope change must bump the revision")

        do {
            _ = try await store.lookup(scanID: scanID, candidateID: candidate.id)
            XCTFail("the snapshot should have been discarded")
        } catch {
            XCTAssertEqual(error as? PolicyError, .staleScan)
        }
    }

    func testSettingsSurviveARelaunchThroughTheSameStore() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let store = tree.root.appendingPathComponent("store/macdevclean.sqlite")

        do {
            let repository = try SwiftDataRepositories.make(containerURL: store)
            let model = SettingsModel(
                repository: repository, invalidate: {},
                picker: StubPicker(folders: [tree.root.appendingPathComponent("work")]))
            await model.load()
            await model.addRoots()
            model.preferences.language = .portugueseBrazil
            await model.savePreferences()
        }

        let reopened = try SwiftDataRepositories.make(containerURL: store)
        let model = SettingsModel(
            repository: reopened, invalidate: {}, picker: StubPicker(folders: []))
        await model.load()

        XCTAssertEqual(model.roots.map(\.url.lastPathComponent), ["work"])
        XCTAssertEqual(model.preferences.language, .portugueseBrazil)
    }

    func testScanOnLaunchCannotBeEnabledWithoutRoots() async throws {
        let repository = try SwiftDataRepositories.make(containerURL: nil, inMemory: true)
        let model = SettingsModel(
            repository: repository, invalidate: {}, picker: StubPicker(folders: []))
        await model.load()

        XCTAssertFalse(model.canEnableScanOnLaunch)
        XCTAssertFalse(model.preferences.scanOnLaunch, "off until the user turns it on")
    }

    func testAnExclusionThatCannotBeSavedIsNotReportedAsActive() async throws {
        let model = ExclusionsModel(
            repository: RefusingSettings(), invalidate: {}, picker: StubPicker(folders: []))
        await model.load()

        await model.add(.rule("node.modules"))

        XCTAssertTrue(model.exclusions.isEmpty, "a failed save must not look like success")
        XCTAssertEqual(model.failureCode, PolicyError.unavailable.rawValue)
    }

    func testAMissingExclusionPathStaysListedAsUnavailable() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let repository = try SwiftDataRepositories.make(containerURL: nil, inMemory: true)
        let present = try tree.directory("here")
        let absent = tree.root.appendingPathComponent("gone")
        let model = ExclusionsModel(
            repository: repository, invalidate: {}, picker: StubPicker(folders: []))

        await model.add(.path(present))
        await model.add(.path(absent))

        XCTAssertEqual(model.exclusions.count, 2, "a decision is not discarded silently")
        XCTAssertTrue(model.resolves(.path(present)))
        XCTAssertFalse(model.resolves(.path(absent)))
    }

    func testClearingHistoryNeverTouchesTheTrash() async throws {
        let repository = try SwiftDataRepositories.make(containerURL: nil, inMemory: true)
        let workspace = SpyWorkspace()
        let candidate = CleanupCandidate(
            id: UUID(), ruleID: "node.modules",
            location: .file(URL(fileURLWithPath: "/fixture/a/node_modules")),
            category: .node, size: 1, allocatedSize: 1, risk: .low, method: .trash,
            consequenceKey: ConsequenceKey.reinstallDependencies)
        let sessionID = UUID()
        try await repository.begin(
            sessionID: sessionID, candidates: [candidate], at: Date())

        let model = HistoryModel(repository: repository, workspace: workspace)
        await model.load()
        XCTAssertEqual(model.sessions.count, 1)

        await model.clearConfirmed()

        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertEqual(workspace.openedTrash, 0, "clearing records is not a filesystem action")
        XCTAssertTrue(workspace.revealed.isEmpty)
    }

    func testShowInTrashIsOfferedOnlyWhenTheLocationStillResolves() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let repository = try SwiftDataRepositories.make(containerURL: nil, inMemory: true)
        let existing = try tree.file("trash/present.bin", bytes: 4)
        let candidate = CleanupCandidate(
            id: UUID(), ruleID: "node.modules",
            location: .file(URL(fileURLWithPath: "/fixture/a/node_modules")),
            category: .node, size: 1, allocatedSize: 1, risk: .low, method: .trash,
            consequenceKey: ConsequenceKey.reinstallDependencies)
        let sessionID = UUID()
        try await repository.begin(
            sessionID: sessionID, candidates: [candidate], at: Date())
        try await repository.record(
            sessionID: sessionID,
            record: CleanupRecord(
                id: candidate.id, candidate: candidate, outcome: .movedToTrash,
                resultingTrashURL: existing, errorCode: nil, finishedAt: Date()))

        let model = HistoryModel(repository: repository, workspace: SpyWorkspace())
        await model.load()
        let record = try XCTUnwrap(model.sessions.first?.records.first)
        XCTAssertTrue(model.canRevealTrash(record))

        let vanished = CleanupRecord(
            id: UUID(), candidate: candidate, outcome: .movedToTrash,
            resultingTrashURL: tree.root.appendingPathComponent("trash/gone.bin"),
            errorCode: nil, finishedAt: Date())
        XCTAssertFalse(model.canRevealTrash(vanished))
    }

    func testAnInterruptedSessionIsShownAsUnknownRatherThanFailed() async throws {
        let repository = try SwiftDataRepositories.make(containerURL: nil, inMemory: true)
        let candidate = CleanupCandidate(
            id: UUID(), ruleID: "node.modules",
            location: .file(URL(fileURLWithPath: "/fixture/a/node_modules")),
            category: .node, size: 1, allocatedSize: 1, risk: .low, method: .trash,
            consequenceKey: ConsequenceKey.reinstallDependencies)
        try await repository.begin(
            sessionID: UUID(), candidates: [candidate], at: Date())

        let model = HistoryModel(repository: repository, workspace: SpyWorkspace())
        await model.load()

        let record = try XCTUnwrap(model.sessions.first?.records.first)
        XCTAssertEqual(record.outcome, .indeterminate)
        XCTAssertEqual(record.errorCode, "session.interrupted")
        XCTAssertEqual(model.unknownCount(model.sessions[0]), 1)
        XCTAssertEqual(model.problemCount(model.sessions[0]), 0, "unknown is not a failure")
    }
}

private struct StubPicker: FolderPicking {
    let folders: [URL]
    func chooseFolders() async -> [URL] { folders }
}

@MainActor
private final class SpyWorkspace: WorkspaceOpening {
    private(set) var revealed: [URL] = []
    private(set) var openedTrash = 0
    func reveal(_ url: URL) { revealed.append(url) }
    func openTrash() { openedTrash += 1 }
}

/// Refuses every write, to model a disk that has become unavailable.
private struct RefusingSettings: SettingsRepository {
    func preferences() async throws -> AppPreferences { AppPreferences() }
    func savePreferences(_ value: AppPreferences) async throws { throw PolicyError.unavailable }
    func roots() async throws -> [ScanRoot] { [] }
    func saveRoots(_ value: [ScanRoot]) async throws { throw PolicyError.unavailable }
    func exclusions() async throws -> [Exclusion] { [] }
    func saveExclusions(_ value: [Exclusion]) async throws { throw PolicyError.unavailable }
}
