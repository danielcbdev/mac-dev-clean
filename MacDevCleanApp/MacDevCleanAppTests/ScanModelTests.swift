import Domain
import TestSupport
import XCTest

@testable import MacDevClean

@MainActor
final class ScanModelTests: XCTestCase {

    private let request = ScanRequest(
        roots: [ScanRoot(url: URL(fileURLWithPath: "/fixture/projects"))],
        includeGlobalCaches: false
    )

    func testProgressArrivesBeforeTheSnapshot() async throws {
        let snapshot = ScanFixtures.snapshot([ScanFixtures.candidate()])
        let model = ScanModel(
            scanner: ReplayScanService(events: [
                .progress(visited: 120), .progress(visited: 400), .completed(snapshot),
            ]))

        model.start(request)
        try await Self.settle(model)

        XCTAssertEqual(model.visited, 400)
        XCTAssertEqual(model.snapshot?.id, snapshot.id)
        XCTAssertFalse(model.isScanning)
        XCTAssertTrue(model.hasScanned)
    }

    func testNothingIsSelectedByAScan() async throws {
        let model = ScanModel(
            scanner: ReplayScanService(events: [
                .completed(
                    ScanFixtures.snapshot([
                        ScanFixtures.candidate(), ScanFixtures.candidate(),
                    ]))
            ]))

        model.start(request)
        try await Self.settle(model)

        XCTAssertEqual(model.candidates.count, 2)
        XCTAssertTrue(model.selectedIDs.isEmpty, "a scan never selects anything")
    }

    func testACancelledRunCannotOverwriteANewerOne() async throws {
        let stale = ScanFixtures.snapshot([ScanFixtures.candidate(path: "/fixture/stale")])
        // Gated: the first run is held before it can deliver its snapshot.
        let slow = ReplayScanService(
            events: [.progress(visited: 1), .completed(stale)], gateAfter: 1)
        let model = ScanModel(scanner: slow)

        model.start(request)
        model.cancel()

        let fresh = ScanFixtures.snapshot([ScanFixtures.candidate(path: "/fixture/fresh")])
        let quick = ReplayScanService(events: [.completed(fresh)])
        let second = ScanModel(scanner: quick)
        second.start(request)
        try await Self.settle(second)

        // Let the abandoned run finish now. It must change nothing.
        await slow.release()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(model.snapshot, "a cancelled run must not deliver results")
        XCTAssertEqual(second.snapshot?.id, fresh.id)
    }

    func testARestartedScanDropsTheEarlierRunsEvents() async throws {
        let first = ScanFixtures.snapshot([ScanFixtures.candidate(path: "/fixture/first")])
        let gated = ReplayScanService(
            events: [.progress(visited: 5), .completed(first)], gateAfter: 1)
        let model = ScanModel(scanner: gated)

        model.start(request)
        model.cancel()
        await gated.release()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(model.snapshot)
        XCTAssertTrue(model.wasCancelled)
    }

    func testDockerUnavailableLeavesFilesystemResultsIntact() async throws {
        let snapshot = ScanFixtures.snapshot([ScanFixtures.candidate()])
        let model = ScanModel(
            scanner: ReplayScanService(events: [
                .issue(code: "issue.docker.unavailable", relativePath: nil),
                .completed(snapshot),
            ]))

        model.start(request)
        try await Self.settle(model)

        XCTAssertTrue(model.issueCodes.contains("issue.docker.unavailable"))
        XCTAssertEqual(model.candidates.count, 1, "Docker's absence costs nothing else")
    }

    func testAFailureSettlesTheModelAndReportsACode() async throws {
        struct Boom: Error {}
        let model = ScanModel(
            scanner: ReplayScanService(events: [.progress(visited: 1)], failure: Boom()))

        model.start(request)
        try await Self.settle(model)

        XCTAssertFalse(model.isScanning)
        XCTAssertEqual(model.failureCode, "scan.failed")
    }

    func testASecondStartWhileScanningIsIgnored() async throws {
        let gated = ReplayScanService(
            events: [.progress(visited: 1), .completed(ScanFixtures.snapshot([]))], gateAfter: 1)
        let model = ScanModel(scanner: gated)

        model.start(request)
        try await Task.sleep(nanoseconds: 50_000_000)
        model.start(request)
        await gated.release()
        try await Self.settle(model)

        let runs = await gated.runCount()
        XCTAssertEqual(runs, 1, "revisiting a screen must not start a second scan")
    }

    // MARK: - Selection

    func testHighRiskItemsAreNotSelectableFromTheList() async throws {
        let high = ScanFixtures.candidate(risk: .high)
        let low = ScanFixtures.candidate(risk: .low)
        let model = ScanModel(
            scanner: ReplayScanService(events: [.completed(ScanFixtures.snapshot([high, low]))]))

        model.start(request)
        try await Self.settle(model)

        XCTAssertFalse(model.canSelectFromList(high))
        XCTAssertTrue(model.canSelectFromList(low))

        model.selectAllSelectable()
        XCTAssertEqual(model.selectedIDs, [low.id], "bulk selection never reaches high risk")
    }

    func testFilteringDoesNotChangeTheSelection() async throws {
        let node = ScanFixtures.candidate(category: .node)
        let brew = ScanFixtures.candidate(
            rule: "brew.cache", path: "/fixture/brew", category: .homebrew)
        let model = ScanModel(
            scanner: ReplayScanService(events: [.completed(ScanFixtures.snapshot([node, brew]))]))

        model.start(request)
        try await Self.settle(model)
        model.toggle(node)
        model.toggle(brew)

        model.ecosystemFilter = .node

        XCTAssertEqual(model.visibleCandidates.map(\.id), [node.id])
        XCTAssertEqual(
            model.selectedIDs, [node.id, brew.id],
            "a filter changes what is shown, never what is selected")
    }

    func testRemovingARootPrunesSelectionsThatNoLongerExist() async throws {
        let kept = ScanFixtures.candidate(path: "/fixture/kept")
        let dropped = ScanFixtures.candidate(path: "/fixture/dropped")
        let model = ScanModel(
            scanner: ReplayScanService(events: [
                .completed(ScanFixtures.snapshot([kept, dropped]))
            ]))
        model.start(request)
        try await Self.settle(model)
        model.toggle(kept)
        model.toggle(dropped)

        // A narrower scope produces a snapshot without the dropped item.
        let narrower = ScanModel(
            scanner: ReplayScanService(events: [.completed(ScanFixtures.snapshot([kept]))]))
        narrower.start(request)
        try await Self.settle(narrower)
        narrower.selectedIDs = [kept.id, dropped.id]
        narrower.pruneSelectionToSnapshot()

        XCTAssertEqual(narrower.selectedIDs, [kept.id])
    }

    // MARK: - Totals

    func testUnknownSizesAreCountedSeparatelyRatherThanAsZero() async throws {
        let known = ScanFixtures.candidate(size: 1_000)
        let unknown = ScanFixtures.candidate(path: "/fixture/unknown", size: nil)
        let model = ScanModel(
            scanner: ReplayScanService(events: [
                .completed(ScanFixtures.snapshot([known, unknown]))
            ]))

        model.start(request)
        try await Self.settle(model)

        XCTAssertEqual(model.knownFilesystemBytes, 1_000)
        XCTAssertEqual(model.unknownFilesystemCount, 1)
    }

    func testDockerBytesAreNeverAddedToTheFilesystemTotal() async throws {
        let file = ScanFixtures.candidate(size: 1_000)
        let docker = ScanFixtures.candidate(
            rule: "docker.volume", category: .docker, size: 9_000,
            risk: .high, method: .docker(.volume))
        let model = ScanModel(
            scanner: ReplayScanService(events: [
                .completed(ScanFixtures.snapshot([file, docker]))
            ]))

        model.start(request)
        try await Self.settle(model)

        XCTAssertEqual(model.knownFilesystemBytes, 1_000)
        XCTAssertEqual(model.estimatedDockerBytes, 9_000)
    }

    func testUnknownSizesSortLastRatherThanFirst() async throws {
        let big = ScanFixtures.candidate(path: "/fixture/big", size: 5_000)
        let small = ScanFixtures.candidate(path: "/fixture/small", size: 10)
        let unknown = ScanFixtures.candidate(path: "/fixture/unknown", size: nil)
        let model = ScanModel(
            scanner: ReplayScanService(events: [
                .completed(ScanFixtures.snapshot([unknown, small, big]))
            ]))

        model.start(request)
        try await Self.settle(model)
        model.sort = .size

        XCTAssertEqual(model.visibleCandidates.map(\.id), [big.id, small.id, unknown.id])
    }

    // MARK: - Helpers

    private static func settle(_ model: ScanModel) async throws {
        for _ in 0..<200 where model.isScanning {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(model.isScanning, "the model never settled")
    }
}
