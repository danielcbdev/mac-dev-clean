import Domain
import TestSupport
import XCTest

@testable import Cleanup

final class JournalTests: XCTestCase {

    // MARK: - Write ahead

    func testJournalFailureBeforeRemovalHasNoSideEffect() async throws {
        let harness = try await CleanupHarness()
        let candidate = try await harness.candidate(
            file: "project/node_modules", rule: "node.modules", risk: .low)
        await harness.journal.failNextBegin()
        let selection = await harness.selection(
            for: [candidate.id], irreversible: false, highRisk: false)
        let plan = try await harness.validate(selection)

        _ = await harness.execute(plan)

        let calls = await harness.trash.calls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testEveryCandidateIsWrittenAsPendingBeforeAnythingMoves() async throws {
        let harness = try await CleanupHarness()
        var ids: Set<UUID> = []
        for index in 0..<3 {
            ids.insert(try await harness.candidate(file: "p\(index)/node_modules").id)
        }
        // Hold the run before the first move completes, then look at what the
        // journal already knows.
        await harness.trash.pause(after: 0)
        let selection = await harness.selection(for: ids, irreversible: false, highRisk: false)
        let plan = try await harness.validate(selection)

        let running = Task { await harness.execute(plan) }
        // The pending rows exist as soon as `begin` returned, which happens
        // before any move is attempted.
        var sessions = try await harness.journal.sessions()
        while sessions.isEmpty {
            await Task.yield()
            sessions = try await harness.journal.sessions()
        }
        let pending = try XCTUnwrap(sessions.first?.records)
        XCTAssertEqual(pending.count, 3)
        XCTAssertTrue(pending.allSatisfy { $0.outcome == .pending })
        let callsSoFar = await harness.trash.calls()
        XCTAssertTrue(callsSoFar.isEmpty)

        await harness.trash.release()
        _ = await running.value
    }

    // MARK: - Failure after a side effect

    func testRecordFailureAfterASuccessStopsTheRunAndMarksItUnrecorded() async throws {
        let harness = try await CleanupHarness()
        let first = try await harness.candidate(file: "alpha/node_modules", bytes: 128)
        let second = try await harness.candidate(file: "beta/node_modules", bytes: 256)
        let selection = await harness.selection(
            for: [first.id, second.id], irreversible: false, highRisk: false)
        let plan = try await harness.validate(selection)

        await harness.journal.failNextRecord()
        let result = await harness.execute(plan)

        let calls = await harness.trash.calls()
        XCTAssertEqual(calls.count, 1, "the second item must not be attempted")

        let firstRecord = try XCTUnwrap(result.records.first)
        // The outcome the user saw is preserved; it is simply flagged as not
        // recorded. It is never downgraded or repeated.
        XCTAssertEqual(firstRecord.outcome, .movedToTrash)
        XCTAssertEqual(firstRecord.errorCode, PolicyError.journalUnavailable.rawValue)

        let secondRecord = try XCTUnwrap(result.records.last)
        XCTAssertEqual(secondRecord.outcome, .skipped)
        XCTAssertEqual(secondRecord.errorCode, PolicyError.journalUnavailable.rawValue)
    }

    func testRepeatingAfterAJournalFailureDoesNotRepeatTheSideEffect() async throws {
        let harness = try await CleanupHarness()
        let candidate = try await harness.candidate(file: "project/node_modules")
        let selection = await harness.selection(
            for: [candidate.id], irreversible: false, highRisk: false)
        let plan = try await harness.validate(selection)

        await harness.journal.failNextRecord()
        _ = await harness.execute(plan)
        _ = await harness.execute(plan)

        let calls = await harness.trash.calls()
        XCTAssertEqual(calls.count, 1, "a spent plan must not act again")
    }

    func testPendingRowsBecomeIndeterminateOnRecovery() async throws {
        let harness = try await CleanupHarness()
        let candidate = try await harness.candidate(file: "project/node_modules")
        await harness.journal.failNextRecord()
        let selection = await harness.selection(
            for: [candidate.id], irreversible: false, highRisk: false)
        let plan = try await harness.validate(selection)
        _ = await harness.execute(plan)

        try await harness.journal.recoverInterruptedSessions()
        let sessions = try await harness.journal.sessions()
        let records = try XCTUnwrap(sessions.first?.records)

        // Never assumed successful, never assumed failed.
        XCTAssertTrue(records.allSatisfy { $0.outcome != .pending })
        XCTAssertTrue(records.contains { $0.outcome == .indeterminate })
    }

    // MARK: - Truthful accounting

    func testBytesMovedToTrashAreNotReportedAsBytesFreed() async throws {
        // The volume reports the *same* free space before and after, which is
        // exactly what happens when an item is trashed on its own volume.
        let harness = try await CleanupHarness(freeSpaceReadings: [1_000_000, 1_000_000])
        let candidate = try await harness.candidate(file: "project/node_modules", bytes: 4096)
        let selection = await harness.selection(
            for: [candidate.id], irreversible: false, highRisk: false)
        let plan = try await harness.validate(selection)

        let summary = await harness.execute(plan)

        XCTAssertEqual(summary.bytesMovedToTrash, 4096)
        XCTAssertEqual(
            summary.observedFreeSpaceDelta, 0,
            "moving to the Trash on the same volume frees nothing")
    }

    func testANegativeFreeSpaceDeltaIsReportedAsMeasured() async throws {
        // Something else on the machine wrote while the cleanup ran.
        let harness = try await CleanupHarness(freeSpaceReadings: [1_000_000, 900_000])
        let candidate = try await harness.candidate(file: "project/node_modules", bytes: 4096)
        let selection = await harness.selection(
            for: [candidate.id], irreversible: false, highRisk: false)
        let plan = try await harness.validate(selection)

        let summary = await harness.execute(plan)

        XCTAssertEqual(summary.bytesMovedToTrash, 4096)
        XCTAssertEqual(
            summary.observedFreeSpaceDelta, -100_000,
            "a negative observation is real and is never clamped to zero")
    }

    func testAnUnavailableFreeSpaceReadingStaysUnknown() async throws {
        let harness = try await CleanupHarness(freeSpaceReadings: [nil])
        let candidate = try await harness.candidate(file: "project/node_modules", bytes: 4096)
        let selection = await harness.selection(
            for: [candidate.id], irreversible: false, highRisk: false)
        let plan = try await harness.validate(selection)

        let summary = await harness.execute(plan)

        XCTAssertNil(summary.observedFreeSpaceDelta)
        XCTAssertEqual(summary.bytesMovedToTrash, 4096)
    }

    func testOnlyConfirmedMovesContributeBytes() async throws {
        let harness = try await CleanupHarness()
        let moved = try await harness.candidate(file: "alpha/node_modules", bytes: 100)
        let blocked = try await harness.candidate(file: "beta/node_modules", bytes: 999_999)
        guard case .file(let blockedURL) = blocked.location else {
            return XCTFail("expected a file")
        }
        await harness.trash.fail(for: blockedURL, with: PolicyError.permissionDenied)
        let selection = await harness.selection(
            for: [moved.id, blocked.id], irreversible: false, highRisk: false)
        let plan = try await harness.validate(selection)

        let summary = await harness.execute(plan)

        XCTAssertEqual(summary.bytesMovedToTrash, 100)
    }

    // MARK: - Diagnostics stay private

    func testTheDiagnosticReportContainsNoPathsOrResourceNames() async throws {
        let harness = try await CleanupHarness()
        let file = try await harness.candidate(file: "project/node_modules", bytes: 4096)
        let volume = await harness.dockerCandidate(kind: .volume, identifier: "customer-database")
        let selection = await harness.selection(
            for: [file.id, volume.id], irreversible: true, highRisk: true)
        let plan = try await harness.validate(selection)
        let summary = await harness.execute(plan)

        let report = CleanupDiagnostics.report(for: summary, appVersion: "1.0.0")

        XCTAssertFalse(report.contains(harness.tree.root.path))
        XCTAssertFalse(report.contains("node_modules"))
        XCTAssertFalse(report.contains("customer-database"))
        XCTAssertFalse(report.contains(NSHomeDirectory()))
        XCTAssertFalse(report.contains("/Users/"))
        // The label "Trash" is fine; a Trash *location* is not.
        XCTAssertFalse(report.contains("file://"))
        XCTAssertFalse(report.contains("/Trash/"))

        // It is still useful.
        XCTAssertTrue(report.contains("rule.node.modules: 1"))
        XCTAssertTrue(report.contains("outcome.movedToTrash: 1"))
        XCTAssertTrue(report.contains("bytesMovedToTrash: 4096"))
        XCTAssertTrue(report.contains("bytes moved to Trash are not bytes freed"))
    }
}
