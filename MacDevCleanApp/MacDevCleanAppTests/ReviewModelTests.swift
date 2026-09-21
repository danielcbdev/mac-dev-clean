import Cleanup
import Domain
import TestSupport
import XCTest

@testable import MacDevClean

/// Drives the review model against the **real** validator and executor, with
/// fake Trash, fake Docker and an in-memory journal underneath.
@MainActor
final class ReviewModelTests: XCTestCase {

    func testChangingTheSelectionResetsBothAcknowledgments() async throws {
        let harness = try await CleanupHarness()
        let model = Self.model(harness)
        let first = try await harness.candidate(file: "alpha/node_modules")
        let second = try await harness.candidate(file: "beta/node_modules")

        model.contentChanged(to: [first.id])
        model.acknowledgeIrreversible = true
        model.acknowledgeHighRisk = true

        model.contentChanged(to: [first.id, second.id])

        XCTAssertFalse(model.acknowledgeIrreversible)
        XCTAssertFalse(
            model.acknowledgeHighRisk,
            "an acknowledgment applies to what the user was looking at")
    }

    func testTheSameContentDoesNotResetAnAcknowledgment() async throws {
        let harness = try await CleanupHarness()
        let model = Self.model(harness)
        let candidate = try await harness.candidate(file: "alpha/node_modules")

        model.contentChanged(to: [candidate.id])
        model.acknowledgeHighRisk = true
        model.contentChanged(to: [candidate.id])

        XCTAssertTrue(model.acknowledgeHighRisk)
    }

    func testConfirmationIsBlockedUntilRequiredAcknowledgmentsAreGiven() {
        let model = ReviewModel(
            validator: RefusingValidator(), executor: RefusingExecutor())

        XCTAssertFalse(model.canConfirm(needsIrreversible: true, needsHighRisk: false))
        model.acknowledgeIrreversible = true
        XCTAssertTrue(model.canConfirm(needsIrreversible: true, needsHighRisk: false))
        XCTAssertFalse(model.canConfirm(needsIrreversible: true, needsHighRisk: true))
        model.acknowledgeHighRisk = true
        XCTAssertTrue(model.canConfirm(needsIrreversible: true, needsHighRisk: true))
    }

    func testAHighRiskItemWithoutConsentIsRefusedAndNothingIsRemoved() async throws {
        let harness = try await CleanupHarness()
        let model = Self.model(harness)
        let archives = try await harness.candidate(
            file: "Library/Developer/Xcode/Archives", rule: "xcode.archives", risk: .high)

        model.contentChanged(to: [archives.id])
        await model.confirm(scanID: harness.scanID, ids: [archives.id])

        let calls = await harness.trash.calls()
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(model.failureCode, PolicyError.consentRequired.rawValue)
        XCTAssertEqual(model.validationIssues.first?.code, .consentRequired)
        XCTAssertFalse(model.isRunning, "a refusal always settles the model")
    }

    func testAnExpiredPlanReportsAReasonInsteadOfActing() async throws {
        let clock = MutableTestClock()
        let harness = try await CleanupHarness(clock: clock)
        let model = Self.model(harness)
        let candidate = try await harness.candidate(file: "alpha/node_modules")
        model.contentChanged(to: [candidate.id])

        // Validate, then let the plan go stale before it is executed.
        let selection = await harness.selection(
            for: [candidate.id], irreversible: false, highRisk: false)
        let plan = try await harness.validate(selection)
        clock.advance(seconds: 61)
        let summary = await harness.execute(plan)

        let calls = await harness.trash.calls()
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(summary.records.first?.errorCode, PolicyError.expiredPlan.rawValue)
    }

    func testAConfirmedCleanupReportsItsOutcomesGroupedByResult() async throws {
        let harness = try await CleanupHarness()
        let model = Self.model(harness)
        let moved = try await harness.candidate(file: "alpha/node_modules", bytes: 2_048)
        let blocked = try await harness.candidate(file: "beta/node_modules", bytes: 4_096)
        guard case .file(let blockedURL) = blocked.location else {
            return XCTFail("expected a file")
        }
        await harness.trash.fail(for: blockedURL, with: PolicyError.permissionDenied)

        model.contentChanged(to: [moved.id, blocked.id])
        await model.confirm(scanID: harness.scanID, ids: [moved.id, blocked.id])

        XCTAssertEqual(model.recoverable.count, 1)
        XCTAssertEqual(model.failed.count, 1)
        XCTAssertEqual(model.summary?.bytesMovedToTrash, 2_048)
        XCTAssertFalse(model.isRunning)
    }

    func testASecondConfirmWhileRunningDoesNothing() async throws {
        let harness = try await CleanupHarness()
        let model = Self.model(harness)
        let candidate = try await harness.candidate(file: "alpha/node_modules")
        model.contentChanged(to: [candidate.id])

        // Hold the executor mid-run, fire a second confirm, then release.
        await harness.trash.pause(after: 0)
        let first = Task { await model.confirm(scanID: harness.scanID, ids: [candidate.id]) }
        try await Task.sleep(nanoseconds: 100_000_000)
        await model.confirm(scanID: harness.scanID, ids: [candidate.id])
        await harness.trash.release()
        await first.value

        let calls = await harness.trash.calls()
        XCTAssertEqual(calls.count, 1, "a double click must schedule one cleanup")
    }

    func testTheDiagnosticReportCarriesNoPathsOrResourceNames() async throws {
        let harness = try await CleanupHarness()
        let model = Self.model(harness)
        let candidate = try await harness.candidate(file: "alpha/node_modules")

        model.contentChanged(to: [candidate.id])
        await model.confirm(scanID: harness.scanID, ids: [candidate.id])

        let report = model.diagnosticReport
        XCTAssertFalse(report.isEmpty)
        XCTAssertFalse(report.contains(harness.tree.root.path))
        XCTAssertFalse(report.contains("node_modules"))
        XCTAssertFalse(report.contains("file://"))
        XCTAssertTrue(report.contains("bytes moved to Trash are not bytes freed"))
    }

    // MARK: - Helpers

    private static func model(_ harness: CleanupHarness) -> ReviewModel {
        ReviewModel(validator: harness.planValidator, executor: harness.planExecutor)
    }
}

/// A validator that always refuses, for the pure acknowledgment-gate tests.
private struct RefusingValidator: CleanupPlanValidating {
    func validate(_ selection: CleanupSelection) async throws -> ValidatedCleanupPlan {
        throw PolicyError.unsupported
    }
    func inspect(_ selection: CleanupSelection) async -> [ValidationIssue] { [] }
}

/// It is impossible to construct a plan outside the Cleanup target, so this
/// executor can never be handed one. That is the safety boundary, visible here
/// as a type that cannot be called by accident.
private struct RefusingExecutor: CleanupExecuting {
    func execute(_ plan: ValidatedCleanupPlan) -> AsyncStream<CleanupEvent> {
        AsyncStream { $0.finish() }
    }
}
