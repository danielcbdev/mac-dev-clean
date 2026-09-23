import Domain
import TestSupport
import XCTest

@testable import MacDevClean

/// A control that cannot act must not look like one that can.
///
/// "Start scan" was offered, enabled, on a screen where pressing it did
/// nothing: `startScan()` opened with `guard canScan else { return }` and
/// returned in silence. The user pressed a button and the application did not
/// answer. These tests make the refusal say why.
@MainActor
final class ScanAvailabilityTests: XCTestCase {
    private let request = ScanRequest(
        roots: [ScanRoot(url: URL(fileURLWithPath: "/fixture/projects"))],
        includeGlobalCaches: false
    )

    func testAScanCannotStartWithoutRootsAndSaysWhy() async {
        let coordinator = RootCoordinator(dependencies: .fixture(scenario: .firstRun))
        await coordinator.load()

        XCTAssertEqual(coordinator.scanUnavailableReason, .noRoots)
        XCTAssertFalse(coordinator.canScan)

        coordinator.startScan()

        XCTAssertFalse(coordinator.scanModel.isScanning, "a refused scan must not look started")
        XCTAssertNil(coordinator.scanModel.snapshot)
    }

    func testAScanCanStartOnceRootsExist() async {
        let coordinator = RootCoordinator(dependencies: .fixture(scenario: .mixedResults))
        await coordinator.load()

        XCTAssertNil(
            coordinator.scanUnavailableReason,
            "roots are configured, so nothing should refuse the scan")
        XCTAssertTrue(coordinator.canScan)
    }

    /// The second reason: a scan already running. Offering "Start scan" during
    /// a scan invites the user to start the thing that is already happening.
    func testAScanAlreadyRunningIsItsOwnStatedReason() async throws {
        let coordinator = RootCoordinator(dependencies: .fixture(scenario: .mixedResults))
        await coordinator.load()

        coordinator.startScan()
        XCTAssertEqual(coordinator.scanUnavailableReason, .alreadyScanning)

        coordinator.cancelScan()
    }

    // MARK: - Filters that hide everything

    func testAFilterThatMatchesNothingIsDistinctFromHavingNothing() async throws {
        let model = ScanModel(
            scanner: ReplayScanService(events: [
                .completed(
                    ScanFixtures.snapshot([
                        ScanFixtures.candidate(category: .node),
                        ScanFixtures.candidate(category: .node),
                    ]))
            ]))

        model.start(request)
        try await Self.settle(model)

        XCTAssertFalse(model.candidates.isEmpty)
        XCTAssertFalse(
            model.hasResultsHiddenByFilters,
            "nothing is filtered out yet")

        // The Overview sets this filter whenever a category is tapped, which
        // is how a user reaches an empty Caches screen with results in hand.
        model.ecosystemFilter = .xcode

        XCTAssertTrue(model.visibleCandidates.isEmpty)
        XCTAssertTrue(
            model.hasResultsHiddenByFilters,
            "the screen must be able to say the filter is the reason")

        model.ecosystemFilter = nil
        XCTAssertFalse(model.hasResultsHiddenByFilters)
        XCTAssertEqual(model.visibleCandidates.count, 2)
    }

    func testAnEmptyScanIsNotReportedAsAFilterProblem() async throws {
        let model = ScanModel(
            scanner: ReplayScanService(events: [.completed(ScanFixtures.snapshot([]))]))

        model.start(request)
        try await Self.settle(model)

        model.ecosystemFilter = .xcode

        XCTAssertTrue(model.candidates.isEmpty)
        XCTAssertFalse(
            model.hasResultsHiddenByFilters,
            "there is nothing for a filter to hide")
    }

    private static func settle(_ model: ScanModel) async throws {
        for _ in 0..<200 where model.isScanning {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(model.isScanning, "the model never settled")
    }
}
