import CleanupRules
import Domain
import TestSupport
import XCTest

@testable import Scanning

final class LargeFileScannerTests: XCTestCase {

    func testThresholdIncludesBoundaryWithoutLeavingSelectedRoot() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let selected = try tree.directory("chosen")
        _ = try tree.file("chosen/exact.bin", bytes: 100)
        _ = try tree.file("chosen/small.bin", bytes: 99)
        _ = try tree.file("outside/large.bin", bytes: 200)

        let rows = try await Self.rows(
            roots: [selected], selectedRoots: [selected], minimumBytes: 100, tree: tree)

        XCTAssertEqual(rows.map { $0.url.lastPathComponent }, ["exact.bin"])
    }

    func testAFolderThatWasNotChosenIsNeverScanned() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let chosen = try tree.directory("chosen")
        let sibling = try tree.directory("sibling")
        _ = try tree.file("chosen/a.bin", bytes: 200)
        _ = try tree.file("sibling/b.bin", bytes: 500)

        // The request names both; only one is in the Large Files scope.
        let rows = try await Self.rows(
            roots: [chosen, sibling], selectedRoots: [chosen], minimumBytes: 100, tree: tree)

        XCTAssertEqual(rows.map { $0.url.lastPathComponent }, ["a.bin"])
    }

    func testBroadRootsAreRefused() async throws {
        for path in ["/", "/System", "/Users", "/Library", "/Applications", NSHomeDirectory()] {
            XCTAssertTrue(
                LargeFileScanner.isRefused(URL(fileURLWithPath: path)),
                "\(path) is too broad to analyse")
        }
        let tree = try FixtureTree()
        defer { try? tree.close() }
        XCTAssertFalse(LargeFileScanner.isRefused(try tree.directory("chosen/documents")))
    }

    func testASymlinkIsInformationalAndNotSelectable() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let selected = try tree.directory("chosen")
        let target = try tree.file("outside/huge.bin", bytes: 5_000)
        _ = try tree.symlink("chosen/alias.bin", to: target)
        _ = try tree.file("chosen/real.bin", bytes: 200)

        let rows = try await Self.rows(
            roots: [selected], selectedRoots: [selected], minimumBytes: 1, tree: tree)

        let alias = try XCTUnwrap(rows.first { $0.url.lastPathComponent == "alias.bin" })
        XCTAssertFalse(alias.canSelect, "a link is shown, never acted on")
        XCTAssertLessThan(
            alias.logicalBytes, 5_000, "the size of a link is not the size of its target")
        XCTAssertTrue(rows.contains { $0.url.lastPathComponent == "real.bin" })
    }

    func testOnlySelectableRowsBecomeCandidates() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let selected = try tree.directory("chosen")
        let target = try tree.file("outside/huge.bin", bytes: 5_000)
        _ = try tree.symlink("chosen/alias.bin", to: target)
        _ = try tree.file("chosen/real.bin", bytes: 200)

        let result = try await Self.collect(
            roots: [selected], selectedRoots: [selected], minimumBytes: 1, tree: tree)

        XCTAssertEqual(result.snapshot.candidates.count, 1)
        XCTAssertEqual(result.snapshot.candidates.first?.ruleID, manualLargeFileRuleID)
    }

    func testEveryCandidateIsHighRiskAndNoneIsPreselected() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let selected = try tree.directory("chosen")
        _ = try tree.file("chosen/a.bin", bytes: 300)
        _ = try tree.file("chosen/b.bin", bytes: 400)

        let result = try await Self.collect(
            roots: [selected], selectedRoots: [selected], minimumBytes: 1, tree: tree)

        XCTAssertEqual(result.snapshot.candidates.count, 2)
        XCTAssertTrue(result.snapshot.candidates.allSatisfy { $0.risk == .high })
        XCTAssertTrue(result.snapshot.candidates.allSatisfy { $0.category == .largeFiles })
        XCTAssertTrue(result.snapshot.candidates.allSatisfy { $0.method == .trash })
    }

    func testAPackageIsOneDocumentRatherThanAFolderToWalkInto() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let selected = try tree.directory("chosen")
        _ = try tree.file("chosen/Demo.app/Contents/big.bin", bytes: 900)
        _ = try tree.file("chosen/plain.bin", bytes: 900)

        let rows = try await Self.rows(
            roots: [selected], selectedRoots: [selected], minimumBytes: 100, tree: tree)

        XCTAssertEqual(rows.map { $0.url.lastPathComponent }, ["plain.bin"])
    }

    func testAnotherVolumeIsNotFollowed() async throws {
        let root = URL(fileURLWithPath: "/fixture/chosen")
        let mounted = root.appendingPathComponent("mounted")
        let files = StubFileSystem()
        await files.setEntry(.stub(url: root, kind: .directory, device: 1, inode: 1))
        await files.setChildren(
            [
                .stub(
                    url: mounted, kind: .directory, device: 9, inode: 2, isMount: true),
                .stub(
                    url: root.appendingPathComponent("here.bin"), device: 1, inode: 3,
                    logicalBytes: 500, allocatedBytes: 500),
            ],
            of: root
        )
        await files.setChildren(
            [
                .stub(
                    url: mounted.appendingPathComponent("elsewhere.bin"), device: 9, inode: 4,
                    logicalBytes: 9_000, allocatedBytes: 9_000)
            ],
            of: mounted
        )

        let context = MemoryContext(
            value: SafetyContext(
                home: URL(fileURLWithPath: "/fixture"), projectRoots: [],
                largeFileRoots: [root], globalRuleRoots: [:], exclusions: [], revision: 1))
        let scanner = LargeFileScanner(
            files: files, context: context, store: InMemoryCandidateStore())

        var rows: [LargeFileRow] = []
        for try await event in scanner.scan(
            LargeFileRequest(roots: [ScanRoot(url: root)], minimumBytes: 100))
        {
            if case .completed(let result, _) = event { rows = result }
        }

        XCTAssertEqual(rows.map { $0.url.lastPathComponent }, ["here.bin"])
    }

    func testACloudPlaceholderIsSkippedAndReported() async throws {
        let root = URL(fileURLWithPath: "/fixture/chosen")
        let files = StubFileSystem()
        await files.setEntry(.stub(url: root, kind: .directory, device: 1, inode: 1))
        await files.setChildren(
            [
                .stub(
                    url: root.appendingPathComponent("in-cloud.bin"), device: 1, inode: 2,
                    logicalBytes: 9_000, allocatedBytes: 0, isCloudPlaceholder: true)
            ],
            of: root
        )
        let context = MemoryContext(
            value: SafetyContext(
                home: URL(fileURLWithPath: "/fixture"), projectRoots: [],
                largeFileRoots: [root], globalRuleRoots: [:], exclusions: [], revision: 1))
        let scanner = LargeFileScanner(
            files: files, context: context, store: InMemoryCandidateStore())

        var rows: [LargeFileRow] = []
        var issues: [String] = []
        for try await event in scanner.scan(
            LargeFileRequest(roots: [ScanRoot(url: root)], minimumBytes: 100))
        {
            switch event {
            case .completed(let result, _): rows = result
            case .issue(let code): issues.append(code)
            case .progress: break
            }
        }

        XCTAssertTrue(rows.isEmpty, "measuring it would make the provider download it")
        XCTAssertTrue(issues.contains(ScanIssueCode.cloudPlaceholderSkipped))
    }

    func testAnExclusionRemovesARow() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let selected = try tree.directory("chosen")
        let kept = try tree.file("chosen/keep.bin", bytes: 300)
        _ = try tree.file("chosen/skip.bin", bytes: 400)

        let rows = try await Self.rows(
            roots: [selected], selectedRoots: [selected], minimumBytes: 1, tree: tree,
            exclusions: [.path(selected.appendingPathComponent("skip.bin"))])

        XCTAssertEqual(rows.map(\.url.lastPathComponent), [kept.lastPathComponent])
    }

    func testOverlappingChosenFoldersDoNotListAFileTwice() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let outer = try tree.directory("chosen")
        let inner = try tree.directory("chosen/inner")
        _ = try tree.file("chosen/inner/a.bin", bytes: 500)

        let rows = try await Self.rows(
            roots: [outer, inner], selectedRoots: [outer, inner], minimumBytes: 1, tree: tree)

        XCTAssertEqual(rows.count, 1)
    }

    func testCancellingStopsTheScan() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let selected = try tree.directory("chosen")
        for index in 0..<50 {
            _ = try tree.file("chosen/d\(index)/file.bin", bytes: 200)
        }
        let context = MemoryContext(
            value: SafetyContext(
                home: tree.root, projectRoots: [], largeFileRoots: [selected],
                globalRuleRoots: [:], exclusions: [], revision: 1))
        let scanner = LargeFileScanner(
            files: LocalFileSystem(), context: context, store: InMemoryCandidateStore())

        let work = Task {
            var completed = false
            for try await event in scanner.scan(
                LargeFileRequest(roots: [ScanRoot(url: selected)], minimumBytes: 1))
            {
                if case .completed = event { completed = true }
            }
            return completed
        }
        work.cancel()

        do {
            let completed = try await work.value
            XCTAssertFalse(completed, "a cancelled scan must not produce a snapshot")
        } catch is CancellationError {
            // Also acceptable: the producer reported that it stopped.
        }
    }

    // MARK: - Cleanup still protects these

    func testACandidateWhoseFolderIsNoLongerChosenIsRejected() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let selected = try tree.directory("chosen")
        _ = try tree.file("chosen/a.bin", bytes: 500)
        let store = InMemoryCandidateStore()
        let context = MemoryContext(
            value: SafetyContext(
                home: tree.root, projectRoots: [], largeFileRoots: [selected],
                globalRuleRoots: [:], exclusions: [], revision: 1))
        let scanner = LargeFileScanner(
            files: LocalFileSystem(), context: context, store: store)
        var snapshot: ScanSnapshot?
        for try await event in scanner.scan(
            LargeFileRequest(roots: [ScanRoot(url: selected)], minimumBytes: 1))
        {
            if case .completed(_, let value) = event { snapshot = value }
        }
        let candidate = try XCTUnwrap(snapshot?.candidates.first)

        // The user removes the folder from Large Files scope.
        await context.update(
            SafetyContext(
                home: tree.root, projectRoots: [], largeFileRoots: [],
                globalRuleRoots: [:], exclusions: [], revision: 1))
        let policy = PathPolicy(files: LocalFileSystem())
        guard case .file(let url) = candidate.location else { return XCTFail("expected a file") }

        do {
            try await policy.check(
                url, ruleID: manualLargeFileRuleID,
                context: try await context.current())
            XCTFail("a file outside the chosen folders must not be cleanable")
        } catch {
            XCTAssertEqual(error as? PolicyError, .outsideScope)
        }
    }

    // MARK: - Helpers

    private struct Collected {
        let rows: [LargeFileRow]
        let snapshot: ScanSnapshot
    }

    private static func collect(
        roots: [URL],
        selectedRoots: [URL],
        minimumBytes: UInt64,
        tree: FixtureTree,
        exclusions: [Exclusion] = []
    ) async throws -> Collected {
        let context = MemoryContext(
            value: SafetyContext(
                home: tree.root, projectRoots: [], largeFileRoots: selectedRoots,
                globalRuleRoots: [:], exclusions: exclusions, revision: 1))
        let scanner = LargeFileScanner(
            files: LocalFileSystem(), context: context, store: InMemoryCandidateStore())

        var rows: [LargeFileRow] = []
        var snapshot: ScanSnapshot?
        for try await event in scanner.scan(
            LargeFileRequest(roots: roots.map { ScanRoot(url: $0) }, minimumBytes: minimumBytes))
        {
            if case .completed(let result, let value) = event {
                rows = result
                snapshot = value
            }
        }
        return Collected(rows: rows, snapshot: try XCTUnwrap(snapshot))
    }

    private static func rows(
        roots: [URL],
        selectedRoots: [URL],
        minimumBytes: UInt64,
        tree: FixtureTree,
        exclusions: [Exclusion] = []
    ) async throws -> [LargeFileRow] {
        try await collect(
            roots: roots, selectedRoots: selectedRoots, minimumBytes: minimumBytes,
            tree: tree, exclusions: exclusions
        ).rows
    }
}
