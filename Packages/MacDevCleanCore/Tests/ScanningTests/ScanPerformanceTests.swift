import CleanupRules
import Domain
import Foundation
import TestSupport
import XCTest

@testable import Scanning

final class ScanPerformanceTests: XCTestCase {

    func testCancellingAfterFirstBatchBoundsVisitedPayloadEntries() async throws {
        let files = SyntheticFileSystem(count: 100_000)
        let run = try await PerformanceHarness.start(files: files)

        await files.waitForFirstBatch()
        run.task.cancel()
        await files.releaseBlockedBatch()
        await run.task.value

        let visited = await files.readCount()
        XCTAssertLessThanOrEqual(
            visited,
            SyntheticFileSystem.batchSize * 2,
            "cancellation must prevent traversal beyond two 256-entry payload batches"
        )
    }

    func testFiveThousandRealFilesAreMeasuredFromAnOwnedFixture() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let project = try tree.directory("work/app")
        _ = try tree.directory("work/app/node_modules")
        try Data("{\"name\":\"performance-fixture\"}".utf8)
            .write(to: project.appendingPathComponent("package.json"))
        for index in 0..<5_000 {
            _ = try tree.file("work/app/node_modules/entry-\(index).bin", bytes: 1)
        }

        let root = try tree.directory("work")
        let scanner = makeScanner(files: LocalFileSystem(), roots: [root], home: tree.root)
        let snapshot = try await ScanCollector.collect(
            scanner.scan(ScanRequest(roots: [ScanRoot(url: root)], includeGlobalCaches: false))
        )

        XCTAssertEqual(snapshot.candidates.count, 1)
        XCTAssertEqual(snapshot.candidates.first?.size, 5_000)
    }

    private func makeScanner(
        files: any FileSystemClient,
        roots: [URL],
        home: URL
    ) -> DeveloperScanner {
        let context = MemoryContext(
            value: SafetyContext(
                home: home,
                projectRoots: roots,
                largeFileRoots: [],
                globalRuleRoots: [:],
                exclusions: [],
                revision: 1
            )
        )
        return DeveloperScanner(
            files: files,
            catalog: RuleCatalog(),
            git: FakeGitStatus(),
            context: context,
            store: InMemoryCandidateStore()
        )
    }
}
