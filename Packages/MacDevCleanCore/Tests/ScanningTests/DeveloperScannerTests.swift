import CleanupRules
import Domain
import TestSupport
import XCTest

@testable import Scanning

final class DeveloperScannerTests: XCTestCase {

    // MARK: - Finding and measuring

    func testFindsAndMeasuresASupportedProjectArtifact() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        try Self.writePackageJSON(in: tree, at: "work/app")
        _ = try tree.file("work/app/node_modules/a.bin", bytes: 1000)
        _ = try tree.file("work/app/node_modules/nested/b.bin", bytes: 24)
        let root = try tree.directory("work")

        let harness = try await Harness(tree: tree, roots: [root])
        let snapshot = try await harness.scan()

        XCTAssertEqual(snapshot.candidates.count, 1)
        let candidate = try XCTUnwrap(snapshot.candidates.first)
        XCTAssertEqual(candidate.ruleID, "node.modules")
        XCTAssertEqual(candidate.size, 1024)
        XCTAssertEqual(candidate.risk, .low)
        XCTAssertNotNil(snapshot.evidence[candidate.id])
    }

    func testOverlappingRootsDoNotProduceDuplicates() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        try Self.writePackageJSON(in: tree, at: "work/app")
        _ = try tree.file("work/app/node_modules/a.bin", bytes: 8)
        let outer = try tree.directory("work")
        let inner = try tree.directory("work/app")

        let harness = try await Harness(tree: tree, roots: [outer, inner])
        let snapshot = try await harness.scan()

        XCTAssertEqual(snapshot.candidates.count, 1)
    }

    func testOnlyTheOutermostOverlappingCandidateIsOffered() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        try Self.writePackageJSON(in: tree, at: "work/app")
        // A package.json inside the artifact would make the inner directory
        // look like a project too. The artifact must still be offered once, as
        // the outermost item.
        _ = try tree.file("work/app/node_modules/inner/package.json", bytes: 16)
        _ = try tree.file("work/app/node_modules/inner/node_modules/x.bin", bytes: 8)
        let root = try tree.directory("work")

        let harness = try await Harness(tree: tree, roots: [root])
        let snapshot = try await harness.scan()

        XCTAssertEqual(
            snapshot.candidates.compactMap { candidate -> String? in
                guard case .file(let url) = candidate.location else { return nil }
                return url.standardizedFileURL.path
            },
            [tree.root.appendingPathComponent("work/app/node_modules").standardizedFileURL.path]
        )
    }

    func testAnExcludedDescendantSkipsItsAncestorInsteadOfTrashingIt() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        try Self.writePackageJSON(in: tree, at: "work/app")
        _ = try tree.file("work/app/node_modules/keep/patched.js", bytes: 8)
        let root = try tree.directory("work")
        let keep = tree.root.appendingPathComponent("work/app/node_modules/keep")

        let harness = try await Harness(tree: tree, roots: [root], exclusions: [.path(keep)])
        let snapshot = try await harness.scan()

        XCTAssertTrue(snapshot.candidates.isEmpty)
    }

    func testACategoryExclusionRemovesItsCandidates() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        try Self.writePackageJSON(in: tree, at: "work/app")
        _ = try tree.file("work/app/node_modules/a.bin", bytes: 8)
        let root = try tree.directory("work")

        let harness = try await Harness(tree: tree, roots: [root], exclusions: [.category(.node)])
        let snapshot = try await harness.scan()

        XCTAssertTrue(snapshot.candidates.isEmpty)
    }

    func testAwkwardFilenamesAreMeasuredNormally() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        try Self.writePackageJSON(in: tree, at: "work/app")
        _ = try tree.file("work/app/node_modules/line\nbreak.bin", bytes: 10)
        _ = try tree.file("work/app/node_modules/emoji 🧹 spaces.bin", bytes: 20)
        _ = try tree.file("work/app/node_modules/quote'and\"quote.bin", bytes: 30)
        let root = try tree.directory("work")

        let harness = try await Harness(tree: tree, roots: [root])
        let snapshot = try await harness.scan()

        XCTAssertEqual(snapshot.candidates.first?.size, 60)
    }

    func testASymbolicLinkInsideACandidateIsNotFollowed() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        try Self.writePackageJSON(in: tree, at: "work/app")
        _ = try tree.file("work/app/node_modules/real.bin", bytes: 100)
        _ = try tree.file("outside/huge.bin", bytes: 5000)
        _ = try tree.symlink(
            "work/app/node_modules/link",
            to: tree.root.appendingPathComponent("outside")
        )
        let root = try tree.directory("work")

        let harness = try await Harness(tree: tree, roots: [root])
        let snapshot = try await harness.scan()

        // 5000 bytes behind the link must not appear in the total.
        XCTAssertEqual(snapshot.candidates.first?.size, 100)
    }

    // MARK: - Global caches

    func testGlobalCachesAreScannedOnlyWhenRequested() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        _ = try tree.file("Library/Caches/Homebrew/downloads/a.tar", bytes: 512)

        let harness = try await Harness(tree: tree, roots: [], home: tree.root)

        let without = try await harness.scan(includeGlobalCaches: false)
        let with = try await harness.scan(includeGlobalCaches: true)

        XCTAssertTrue(without.candidates.isEmpty)
        let brew = try XCTUnwrap(with.candidates.first { $0.ruleID == "brew.cache" })
        XCTAssertEqual(brew.size, 512)
        XCTAssertEqual(brew.category, .homebrew)
    }

    // MARK: - Partial failure

    func testAnUnreadableSubtreePreservesTheOtherResults() async throws {
        let root = URL(fileURLWithPath: "/fixture/work")
        let good = root.appendingPathComponent("good")
        let locked = root.appendingPathComponent("locked")
        let modules = good.appendingPathComponent("node_modules")

        let files = StubFileSystem()
        await files.setChildren(
            [
                .stub(url: good, kind: .directory, inode: 10),
                .stub(url: locked, kind: .directory, inode: 11),
            ],
            of: root
        )
        await files.setChildren(
            [
                .stub(url: good.appendingPathComponent("package.json"), inode: 12),
                .stub(url: modules, kind: .directory, inode: 13),
            ],
            of: good
        )
        await files.setChildren(
            [
                .stub(
                    url: modules.appendingPathComponent("a.bin"),
                    inode: 14, logicalBytes: 64, allocatedBytes: 64)
            ],
            of: modules
        )
        await files.setContents(
            Data("{\"name\":\"app\"}".utf8), at: good.appendingPathComponent("package.json"))
        await files.setFailure(.permissionDenied, at: locked)

        let context = MemoryContext(
            value: SafetyContext(
                home: URL(fileURLWithPath: "/fixture"),
                projectRoots: [root],
                largeFileRoots: [],
                globalRuleRoots: [:],
                exclusions: [],
                revision: 3
            )
        )
        let store = InMemoryCandidateStore()
        let scanner = DeveloperScanner(
            files: files,
            catalog: RuleCatalog(),
            git: FakeGitStatus(),
            context: context,
            store: store
        )

        let result = try await ScanCollector.drain(
            scanner.scan(ScanRequest(roots: [ScanRoot(url: root)], includeGlobalCaches: false))
        )

        XCTAssertEqual(result.snapshot.candidates.count, 1)
        XCTAssertEqual(result.snapshot.candidates.first?.size, 64)
        XCTAssertTrue(result.issueCodes.contains(ScanIssueCode.permissionDenied))
    }

    // MARK: - Snapshot registration

    func testTheSnapshotIsRegisteredWithItsPolicyRevisionBeforeCompletion() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        try Self.writePackageJSON(in: tree, at: "work/app")
        _ = try tree.file("work/app/node_modules/a.bin", bytes: 8)
        let root = try tree.directory("work")

        let harness = try await Harness(tree: tree, roots: [root], revision: 42)
        let snapshot = try await harness.scan()
        let candidate = try XCTUnwrap(snapshot.candidates.first)

        XCTAssertEqual(snapshot.policyRevision, 42)
        let (found, _, revision) = try await harness.store.lookup(
            scanID: snapshot.id, candidateID: candidate.id)
        XCTAssertEqual(found.id, candidate.id)
        XCTAssertEqual(revision, 42)
    }

    func testEachScanProducesANewSnapshotIdentity() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        try Self.writePackageJSON(in: tree, at: "work/app")
        _ = try tree.file("work/app/node_modules/a.bin", bytes: 8)
        let root = try tree.directory("work")

        let harness = try await Harness(tree: tree, roots: [root])

        let first = try await harness.scan()
        let second = try await harness.scan()

        XCTAssertNotEqual(first.id, second.id)
    }

    // MARK: - Cancellation

    func testCancellingStopsEnumerationRatherThanOnlyHidingIt() async throws {
        // The fake stops answering after 20 reads, so the scan is provably
        // still in progress when the consumer walks away. Nothing here depends
        // on winning a race with the producer.
        let files = HugeFileSystem(
            directories: 1_000,
            filesPerDirectory: 100,
            pauseAfterReads: 20
        )
        let root = HugeFileSystem.root
        let context = MemoryContext(
            value: SafetyContext(
                home: URL(fileURLWithPath: "/huge"),
                projectRoots: [root],
                largeFileRoots: [],
                globalRuleRoots: [:],
                exclusions: [],
                revision: 1
            )
        )
        let scanner = DeveloperScanner(
            files: files,
            catalog: RuleCatalog(),
            git: FakeGitStatus(),
            context: context,
            store: InMemoryCandidateStore()
        )

        var sawProgress = false
        var sawCompleted = false
        do {
            for try await event in scanner.scan(
                ScanRequest(roots: [ScanRoot(url: root)], includeGlobalCaches: false)
            ) {
                if case .completed = event { sawCompleted = true }
                if case .progress = event {
                    sawProgress = true
                    // Leaving the loop terminates the stream, which must stop
                    // the producer, not merely stop delivering to us.
                    break
                }
            }
        } catch is CancellationError {
            // Acceptable: the producer reported that it stopped.
        }

        XCTAssertTrue(sawProgress, "the fixture is large enough to report progress")
        XCTAssertFalse(sawCompleted, "a cancelled scan must not produce a snapshot")

        let atCancellation = await files.readCount()
        XCTAssertLessThan(
            atCancellation, 100,
            "the scan should still have most of the tree left to walk"
        )

        // Let the fake answer again. A producer that really stopped will not
        // ask for anything else.
        await files.release()

        let stabilised = expectation(description: "enumeration stops")
        Task {
            var previous = await files.readCount()
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                let current = await files.readCount()
                if current == previous {
                    stabilised.fulfill()
                    return
                }
                previous = current
            }
        }
        await fulfillment(of: [stabilised], timeout: 5)

        let settled = await files.readCount()
        XCTAssertLessThan(
            settled, 200,
            "enumeration must not have resumed after the consumer walked away"
        )
    }

    // MARK: - Harness

    private struct Harness {
        let tree: FixtureTree
        let store: InMemoryCandidateStore
        let scanner: DeveloperScanner
        let roots: [URL]

        init(
            tree: FixtureTree,
            roots: [URL],
            home: URL? = nil,
            exclusions: [Exclusion] = [],
            revision: UInt64 = 1
        ) async throws {
            self.tree = tree
            self.roots = roots
            store = InMemoryCandidateStore()
            let resolvedHome = home ?? tree.root
            let context = MemoryContext(
                value: SafetyContext(
                    home: resolvedHome,
                    projectRoots: roots,
                    largeFileRoots: [],
                    globalRuleRoots: RuleCatalog().globalRoots(home: resolvedHome),
                    exclusions: exclusions,
                    revision: revision
                )
            )
            scanner = DeveloperScanner(
                files: LocalFileSystem(),
                catalog: RuleCatalog(),
                git: FakeGitStatus(),
                context: context,
                store: store
            )
        }

        func scan(includeGlobalCaches: Bool = false) async throws -> ScanSnapshot {
            try await ScanCollector.collect(
                scanner.scan(
                    ScanRequest(
                        roots: roots.map { ScanRoot(url: $0) },
                        includeGlobalCaches: includeGlobalCaches
                    )
                )
            )
        }
    }

    private static func writePackageJSON(in tree: FixtureTree, at relativePath: String) throws {
        let directory = try tree.directory(relativePath)
        try Data("{\"name\":\"app\"}".utf8)
            .write(to: directory.appendingPathComponent("package.json"))
    }
}

/// A synthetic filesystem large enough that a scan cannot finish instantly, so
/// cancellation is observable. It counts reads, which is how the test proves
/// enumeration really stopped.
private actor HugeFileSystem: FileSystemClient {
    static let root = URL(fileURLWithPath: "/huge/work")
    private static let project = root.appendingPathComponent("app")
    private static let modules = project.appendingPathComponent("node_modules")

    private let directories: Int
    private let filesPerDirectory: Int
    private let pauseAfterReads: Int
    private var reads = 0
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(directories: Int, filesPerDirectory: Int, pauseAfterReads: Int = .max) {
        self.directories = directories
        self.filesPerDirectory = filesPerDirectory
        self.pauseAfterReads = pauseAfterReads
    }

    func readCount() -> Int { reads }

    /// Lets the fake answer again after the consumer has cancelled.
    func release() {
        released = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }

    private func pauseIfNeeded() async {
        guard !released, reads >= pauseAfterReads else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func children(of url: URL) async throws -> [FileEntry] {
        await pauseIfNeeded()
        reads += 1
        let path = url.standardizedFileURL.path
        if path == Self.root.path {
            return [Self.directory(Self.project, inode: 2)]
        }
        if path == Self.project.path {
            return [
                Self.file(Self.project.appendingPathComponent("package.json"), inode: 3, bytes: 14),
                Self.directory(Self.modules, inode: 4),
            ]
        }
        if path == Self.modules.path {
            return (0..<directories).map {
                Self.directory(
                    Self.modules.appendingPathComponent("d\($0)"),
                    inode: UInt64(1_000 + $0)
                )
            }
        }
        if path.hasPrefix(Self.modules.path + "/") {
            let base = UInt64(abs(path.hashValue % 1_000_000)) * 1_000
            return (0..<filesPerDirectory).map {
                Self.file(
                    url.appendingPathComponent("f\($0).bin"),
                    inode: base + UInt64($0),
                    bytes: 16
                )
            }
        }
        return []
    }

    func entry(at url: URL) async throws -> FileEntry {
        await pauseIfNeeded()
        reads += 1
        let path = url.standardizedFileURL.path
        if path == Self.modules.path { return Self.directory(Self.modules, inode: 4) }
        if path == Self.project.path { return Self.directory(Self.project, inode: 2) }
        if path == Self.root.path { return Self.directory(Self.root, inode: 1) }
        if path.hasSuffix("package.json") {
            return Self.file(url, inode: 3, bytes: 14)
        }
        throw PolicyError.missing
    }

    func readPrefix(at url: URL, limit: Int) async throws -> Data {
        await pauseIfNeeded()
        reads += 1
        guard url.lastPathComponent == "package.json" else { throw PolicyError.missing }
        return Data("{\"name\":\"app\"}".utf8)
    }

    private static func directory(_ url: URL, inode: UInt64) -> FileEntry {
        FileEntry(
            url: url,
            kind: .directory,
            identity: FileIdentity(device: 1, inode: inode, modifiedNanoseconds: 0),
            logicalBytes: 0,
            allocatedBytes: 0,
            isMount: false,
            isCloudPlaceholder: false
        )
    }

    private static func file(_ url: URL, inode: UInt64, bytes: UInt64) -> FileEntry {
        FileEntry(
            url: url,
            kind: .file,
            identity: FileIdentity(device: 1, inode: inode, modifiedNanoseconds: 0),
            logicalBytes: bytes,
            allocatedBytes: bytes,
            isMount: false,
            isCloudPlaceholder: false
        )
    }
}
