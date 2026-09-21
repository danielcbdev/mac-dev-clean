import Domain
import TestSupport
import XCTest

@testable import Cleanup

final class ExecutionTests: XCTestCase {

    // MARK: - Time of check, time of use

    func testReplacementAfterReviewIsNeverTrashed() async throws {
        let harness = try await CleanupHarness()
        let candidate = try await harness.candidate(
            file: "project/node_modules", rule: "node.modules", risk: .low)
        let selection = await harness.selection(
            for: [candidate.id], irreversible: false, highRisk: false)
        let plan = try await harness.validate(selection)

        try await harness.replaceWithDifferentIdentity(candidate.id)

        let result = await harness.execute(plan)

        XCTAssertEqual(result.records.first?.errorCode, PolicyError.changed.rawValue)
        let calls = await harness.trash.calls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testAnAncestorReplacedByASymlinkAfterReviewIsNeverTrashed() async throws {
        let harness = try await CleanupHarness()
        let candidate = try await harness.candidate(file: "project/node_modules")
        let selection = await harness.selection(
            for: [candidate.id], irreversible: false, highRisk: false)
        let plan = try await harness.validate(selection)

        // Swap the *parent* for a link pointing somewhere else entirely. The
        // leaf still exists at the end of the path; only an ancestor changed.
        let project = harness.tree.root.appendingPathComponent("project")
        let decoy = try harness.tree.directory("decoy")
        _ = try harness.tree.directory("decoy/node_modules")
        let parked = harness.tree.root.appendingPathComponent("parked-project")
        try FileManager.default.moveItem(at: project, to: parked)
        try FileManager.default.createSymbolicLink(at: project, withDestinationURL: decoy)

        let result = await harness.execute(plan)

        let calls = await harness.trash.calls()
        XCTAssertTrue(calls.isEmpty, "a swapped ancestor must not be followed")
        XCTAssertEqual(result.records.first?.outcome, .skipped)
        XCTAssertNotNil(result.records.first?.errorCode)
    }

    // MARK: - Plans are single use and short lived

    func testAnExpiredPlanCannotExecute() async throws {
        let clock = MutableTestClock()
        let harness = try await CleanupHarness(clock: clock)
        let candidate = try await harness.candidate(file: "project/node_modules")
        let selection = await harness.selection(
            for: [candidate.id], irreversible: false, highRisk: false)
        let plan = try await harness.validate(selection)

        clock.advance(seconds: 61)
        let result = await harness.execute(plan)

        let calls = await harness.trash.calls()
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(result.records.first?.errorCode, PolicyError.expiredPlan.rawValue)
        XCTAssertEqual(result.bytesMovedToTrash, 0)
    }

    func testConfirmingTwiceDoesNotActTwice() async throws {
        let harness = try await CleanupHarness()
        let candidate = try await harness.candidate(file: "project/node_modules")
        let selection = await harness.selection(
            for: [candidate.id], irreversible: false, highRisk: false)
        let plan = try await harness.validate(selection)

        let first = await harness.execute(plan)
        let second = await harness.execute(plan)

        let calls = await harness.trash.calls()
        XCTAssertEqual(calls.count, 1, "the same authorisation must not act twice")
        XCTAssertEqual(first.records.first?.outcome, .movedToTrash)
        XCTAssertEqual(second.records.first?.outcome, .skipped)
        XCTAssertEqual(second.records.first?.errorCode, PolicyError.usedPlan.rawValue)
        XCTAssertEqual(second.bytesMovedToTrash, 0)
    }

    // MARK: - Partial failure

    func testOneFailureDoesNotAbandonTheRestOfThePlan() async throws {
        let harness = try await CleanupHarness()
        let blocked = try await harness.candidate(file: "alpha/node_modules", bytes: 100)
        let fine = try await harness.candidate(file: "beta/node_modules", bytes: 200)
        guard case .file(let blockedURL) = blocked.location else {
            return XCTFail("expected a file")
        }
        await harness.trash.fail(for: blockedURL, with: PolicyError.permissionDenied)

        let selection = await harness.selection(
            for: [blocked.id, fine.id], irreversible: false, highRisk: false)
        let plan = try await harness.validate(selection)
        let result = await harness.execute(plan)

        let failed = try XCTUnwrap(result.records.first { $0.candidate.id == blocked.id })
        let succeeded = try XCTUnwrap(result.records.first { $0.candidate.id == fine.id })
        XCTAssertEqual(failed.outcome, .failed)
        XCTAssertEqual(failed.errorCode, PolicyError.permissionDenied.rawValue)
        XCTAssertEqual(succeeded.outcome, .movedToTrash)
        XCTAssertEqual(result.bytesMovedToTrash, 200, "only the confirmed move counts")
    }

    func testAnUnavailableTrashFailsTheItemWithoutDeletingAnything() async throws {
        let harness = try await CleanupHarness()
        let candidate = try await harness.candidate(file: "project/node_modules")
        guard case .file(let url) = candidate.location else { return XCTFail("expected a file") }
        await harness.trash.fail(for: url, with: PolicyError.unavailable)

        let selection = await harness.selection(
            for: [candidate.id], irreversible: false, highRisk: false)
        let plan = try await harness.validate(selection)
        let result = await harness.execute(plan)

        XCTAssertEqual(result.records.first?.outcome, .failed)
        XCTAssertEqual(result.records.first?.errorCode, PolicyError.unavailable.rawValue)
        // There is no fallback path. The item is still on disk.
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testEveryScheduledItemEndsWithAStatus() async throws {
        let harness = try await CleanupHarness()
        var ids: Set<UUID> = []
        for index in 0..<4 {
            ids.insert(try await harness.candidate(file: "p\(index)/node_modules").id)
        }
        let selection = await harness.selection(for: ids, irreversible: false, highRisk: false)
        let plan = try await harness.validate(selection)

        let result = await harness.execute(plan)

        XCTAssertEqual(result.records.count, 4)
        XCTAssertTrue(result.records.allSatisfy { $0.outcome != .pending })
    }

    func testExactlyOneTerminalSummaryIsEmitted() async throws {
        let harness = try await CleanupHarness()
        let candidate = try await harness.candidate(file: "project/node_modules")
        let selection = await harness.selection(
            for: [candidate.id], irreversible: false, highRisk: false)
        let plan = try await harness.validate(selection)

        var summaries = 0
        var started = 0
        for await event in harness.stream(for: plan) {
            switch event {
            case .started: started += 1
            case .finished: summaries += 1
            case .item: break
            }
        }

        XCTAssertEqual(started, 1)
        XCTAssertEqual(summaries, 1)
    }

    // MARK: - Cancellation

    func testCancellingStopsAfterTheItemInFlight() async throws {
        let harness = try await CleanupHarness()
        var ids: Set<UUID> = []
        for index in 0..<5 {
            ids.insert(try await harness.candidate(file: "p\(index)/node_modules").id)
        }
        // Hold the executor as soon as it has moved one item, so the consumer
        // is guaranteed to walk away mid-plan rather than after it finished.
        await harness.trash.pause(after: 1)
        let selection = await harness.selection(for: ids, irreversible: false, highRisk: false)
        let plan = try await harness.validate(selection)

        var seen = 0
        for await event in harness.stream(for: plan) {
            if case .item = event {
                seen += 1
                if seen == 1 { break }
            }
        }
        await harness.trash.release()

        // At most the item already in flight. Never the whole plan.
        let calls = await harness.trash.calls()
        XCTAssertGreaterThanOrEqual(calls.count, 1)
        XCTAssertLessThanOrEqual(
            calls.count, 2, "cancellation must stop scheduling further items")

        // Nothing is left pending: recovery marks anything unresolved
        // indeterminate rather than assuming it succeeded.
        try await harness.journal.recoverInterruptedSessions()
        let sessions = try await harness.journal.sessions()
        let records = try XCTUnwrap(sessions.first?.records)
        XCTAssertEqual(records.count, 5)
        XCTAssertTrue(records.allSatisfy { $0.outcome != .pending })
    }

    // MARK: - Docker

    func testADockerResourceIsRemovedByIdentifierOnly() async throws {
        let harness = try await CleanupHarness()
        let candidate = await harness.dockerCandidate(kind: .volume, identifier: "vol-1")
        let selection = await harness.selection(
            for: [candidate.id], irreversible: true, highRisk: true)
        let plan = try await harness.validate(selection)

        let result = await harness.execute(plan)

        let removals = await harness.docker.removalCalls()
        XCTAssertEqual(removals, [candidate.id])
        XCTAssertEqual(result.records.first?.outcome, .removed)
        // A Docker removal is irreversible; nothing lands in the Trash.
        XCTAssertNil(result.records.first?.resultingTrashURL)
        XCTAssertEqual(result.bytesMovedToTrash, 0)
    }

    func testADockerResourceThatVanishedIsSkippedBeforeRemoval() async throws {
        let harness = try await CleanupHarness()
        let candidate = await harness.dockerCandidate(kind: .container, identifier: "c-1")
        let selection = await harness.selection(
            for: [candidate.id], irreversible: true, highRisk: true)
        let plan = try await harness.validate(selection)
        await harness.docker.fail(for: candidate.id, with: .missing)

        let result = await harness.execute(plan)

        let removals = await harness.docker.removalCalls()
        XCTAssertTrue(removals.isEmpty)
        XCTAssertEqual(result.records.first?.outcome, .skipped)
        XCTAssertEqual(result.records.first?.errorCode, PolicyError.missing.rawValue)
    }

    // MARK: - Success path

    func testAnApprovedItemIsMovedToTrashAndRecorded() async throws {
        let harness = try await CleanupHarness()
        let candidate = try await harness.candidate(file: "project/node_modules", bytes: 4096)
        let selection = await harness.selection(
            for: [candidate.id], irreversible: false, highRisk: false)
        let plan = try await harness.validate(selection)

        let result = await harness.execute(plan)

        let calls = await harness.trash.calls()
        XCTAssertEqual(calls.count, 1)
        let record = try XCTUnwrap(result.records.first)
        XCTAssertEqual(record.outcome, .movedToTrash)
        XCTAssertNotNil(record.resultingTrashURL)
        XCTAssertNil(record.errorCode)

        let sessions = try await harness.journal.sessions()
        XCTAssertEqual(sessions.first?.records.first?.outcome, .movedToTrash)
        XCTAssertNotNil(sessions.first?.completedAt)
    }
}
