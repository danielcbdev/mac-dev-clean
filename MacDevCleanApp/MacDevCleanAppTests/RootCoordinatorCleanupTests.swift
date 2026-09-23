import Cleanup
import Domain
import Scanning
import TestSupport
import XCTest

@testable import MacDevClean

/// What happens to the overview's scan once a cleanup is confirmed.
///
/// Closing the review without confirming must leave the snapshot where it is.
/// Confirming must drop it once anything has actually been moved or removed,
/// because that snapshot still lists items that are no longer there.
@MainActor
final class RootCoordinatorCleanupTests: XCTestCase {

    func testASuccessfulCleanupClearsTheScanAndReturnsToIdle() async throws {
        let (coordinator, harness) = try await Self.prepared()

        await coordinator.confirmCleanup()

        XCTAssertFalse(coordinator.scanModel.hasScanned)
        XCTAssertNil(coordinator.scanModel.snapshot)
        XCTAssertTrue(coordinator.scanModel.selectedIDs.isEmpty)
        XCTAssertEqual(coordinator.state, .idle)

        coordinator.closeReview()
        XCTAssertEqual(
            coordinator.state, .idle,
            "closing the review stays idle once the scan is gone")
        XCTAssertFalse(coordinator.isReviewing)
        // The harness owns the fixture tree and deletes it on release. It has
        // to outlive confirmation, or validation finds the files already gone.
        withExtendedLifetime(harness) {}
    }

    func testClosingTheReviewWithoutConfirmingKeepsTheScan() async throws {
        let (coordinator, harness) = try await Self.prepared()

        coordinator.closeReview()

        XCTAssertTrue(coordinator.scanModel.hasScanned)
        XCTAssertNotNil(coordinator.scanModel.snapshot)
        XCTAssertFalse(coordinator.scanModel.selectedIDs.isEmpty)
        XCTAssertEqual(coordinator.state, .results)
        withExtendedLifetime(harness) {}
    }

    func testAPartialCleanupClearsTheScanBecauseSomeItemsAreAlreadyGone() async throws {
        let (coordinator, harness) = try await Self.prepared(files: [
            "alpha/node_modules", "beta/node_modules",
        ])
        guard case .file(let blockedURL) = coordinator.scanModel.candidates[0].location else {
            return XCTFail("expected a file")
        }
        await harness.trash.fail(for: blockedURL, with: PolicyError.permissionDenied)

        await coordinator.confirmCleanup()

        XCTAssertEqual(coordinator.reviewModel.recoverable.count, 1)
        XCTAssertEqual(coordinator.reviewModel.failed.count, 1)
        XCTAssertFalse(coordinator.scanModel.hasScanned)
        XCTAssertNil(coordinator.scanModel.snapshot)
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testACleanupThatMovesNothingKeepsTheScan() async throws {
        let (coordinator, harness) = try await Self.prepared()
        for candidate in coordinator.scanModel.candidates {
            guard case .file(let url) = candidate.location else {
                return XCTFail("expected a file")
            }
            await harness.trash.fail(for: url, with: PolicyError.permissionDenied)
        }

        await coordinator.confirmCleanup()

        XCTAssertTrue(coordinator.reviewModel.recoverable.isEmpty)
        XCTAssertEqual(coordinator.reviewModel.failed.count, 1)
        XCTAssertTrue(coordinator.scanModel.hasScanned)
        XCTAssertNotNil(coordinator.scanModel.snapshot)
        XCTAssertEqual(coordinator.state, .completed)
    }

    // MARK: - Harness

    private static func prepared(
        files: [String] = ["alpha/node_modules"]
    ) async throws -> (RootCoordinator, CleanupHarness) {
        let harness = try await CleanupHarness()
        var candidates: [CleanupCandidate] = []
        for file in files {
            candidates.append(try await harness.candidate(file: file))
        }

        let snapshot = ScanSnapshot(
            id: harness.scanID,
            policyRevision: 1,
            candidates: candidates,
            evidence: [:]
        )
        let settings = SessionRepositories(roots: [ScanRoot(url: harness.tree.root)])
        let store = InMemoryCandidateStore()
        let dependencies = AppDependencies(
            scanner: ReplayScanService(events: [.completed(snapshot)]),
            largeFileScanner: IdleLargeFileScanner(),
            validator: harness.planValidator,
            executor: harness.planExecutor,
            settings: settings,
            history: settings,
            store: store,
            context: AppSafetyContextProvider(
                settings: settings, store: store, home: harness.tree.root),
            picker: PreviewFolderPicker(folders: []),
            workspace: PreviewWorkspaceOpener(),
            home: harness.tree.root,
            cleanupEnabled: true,
            isUITesting: true,
            storageFailureCode: nil
        )

        let coordinator = RootCoordinator(dependencies: dependencies)
        await coordinator.load()
        coordinator.startScan()
        for _ in 0..<200 where coordinator.state == .scanning || coordinator.scanModel.isScanning {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(coordinator.state, .results)
        XCTAssertTrue(coordinator.scanModel.hasScanned)

        coordinator.scanModel.selectedIDs = Set(candidates.map(\.id))
        coordinator.openReview()
        XCTAssertEqual(coordinator.state, .reviewing)
        return (coordinator, harness)
    }
}

private struct IdleLargeFileScanner: LargeFileScanning {
    func scan(_ request: LargeFileRequest) -> AsyncThrowingStream<LargeFileEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
