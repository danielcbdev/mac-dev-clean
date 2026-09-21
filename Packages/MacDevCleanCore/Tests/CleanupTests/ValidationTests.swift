import Domain
import TestSupport
import XCTest

@testable import Cleanup

final class ValidationTests: XCTestCase {

    // MARK: - Authority cannot be invented

    func testUnregisteredSelectionIsRejected() async throws {
        let harness = try await CleanupHarness(candidates: [], evidence: [:])
        let selection = CleanupSelection(
            scanID: UUID(), candidateIDs: [UUID()],
            acknowledgedIrreversible: false, acknowledgedHighRisk: false)
        do {
            _ = try await harness.validate(selection)
            XCTFail("Unregistered IDs must not create cleanup authority")
        } catch {
            XCTAssertEqual(error as? PolicyError, .staleScan)
        }
    }

    func testAnUnknownCandidateInAKnownScanIsRejected() async throws {
        let harness = try await CleanupHarness()
        _ = try await harness.candidate(file: "project/node_modules")
        let selection = await harness.selection(
            for: [UUID()], irreversible: false, highRisk: false)

        await Self.assertRejected(.unknownCandidate) {
            _ = try await harness.validate(selection)
        }
    }

    func testAnEmptySelectionIsRefused() async throws {
        let harness = try await CleanupHarness()
        let selection = await harness.selection(for: [], irreversible: false, highRisk: false)

        await Self.assertRejected(.unsupported) {
            _ = try await harness.validate(selection)
        }
    }

    func testAValidSelectionProducesAPlanForExactlyThoseItems() async throws {
        let harness = try await CleanupHarness()
        let first = try await harness.candidate(file: "alpha/node_modules")
        let second = try await harness.candidate(file: "beta/node_modules")
        let selection = await harness.selection(
            for: [first.id, second.id], irreversible: false, highRisk: false)

        let plan = try await harness.validate(selection)

        XCTAssertEqual(Set(plan.items.map(\.candidate.id)), [first.id, second.id])
        XCTAssertEqual(plan.items.count, 2)
    }

    func testTheSameIdentifierIsPlannedOnce() async throws {
        let harness = try await CleanupHarness()
        let candidate = try await harness.candidate(file: "project/node_modules")
        // A Set cannot hold a duplicate, which is the point: the shape of the
        // selection makes double execution unrepresentable.
        let selection = await harness.selection(
            for: [candidate.id, candidate.id], irreversible: false, highRisk: false)

        let plan = try await harness.validate(selection)

        XCTAssertEqual(plan.items.count, 1)
    }

    func testItemsAreOrderedDeterministically() async throws {
        let harness = try await CleanupHarness()
        var ids: Set<UUID> = []
        for index in 0..<5 {
            ids.insert(try await harness.candidate(file: "p\(index)/node_modules").id)
        }
        let selection = await harness.selection(for: ids, irreversible: false, highRisk: false)

        let first = try await harness.validate(selection)
        let second = try await harness.validate(selection)

        XCTAssertEqual(first.items.map(\.candidate.id), second.items.map(\.candidate.id))
    }

    // MARK: - Scope changes invalidate a selection

    func testAChangedPolicyRevisionMakesTheSelectionStale() async throws {
        let harness = try await CleanupHarness()
        let candidate = try await harness.candidate(file: "project/node_modules")
        await harness.bumpPolicyRevision()
        let selection = await harness.selection(
            for: [candidate.id], irreversible: false, highRisk: false)

        await Self.assertRejected(.staleScan) {
            _ = try await harness.validate(selection)
        }
    }

    func testAnExclusionAddedWhileReviewIsOpenInvalidatesTheSelection() async throws {
        let harness = try await CleanupHarness()
        let candidate = try await harness.candidate(file: "project/node_modules")
        guard case .file(let url) = candidate.location else { return XCTFail("expected a file") }
        // The revision is deliberately left alone, so this test proves the
        // exclusion itself is re-read rather than only the revision counter.
        await harness.addExclusion(.path(url), bumpRevision: false)
        let selection = await harness.selection(
            for: [candidate.id], irreversible: false, highRisk: false)

        await Self.assertRejected(.excluded) {
            _ = try await harness.validate(selection)
        }
    }

    func testACategoryExclusionAddedWhileReviewIsOpenInvalidatesTheSelection() async throws {
        let harness = try await CleanupHarness()
        let candidate = try await harness.candidate(file: "project/node_modules")
        await harness.addExclusion(.category(.node), bumpRevision: false)
        let selection = await harness.selection(
            for: [candidate.id], irreversible: false, highRisk: false)

        await Self.assertRejected(.excluded) {
            _ = try await harness.validate(selection)
        }
    }

    func testATargetThatDisappearedIsRejected() async throws {
        let harness = try await CleanupHarness()
        let candidate = try await harness.candidate(file: "project/node_modules")
        guard case .file(let url) = candidate.location else { return XCTFail("expected a file") }
        // Move it aside inside the owned fixture; nothing is unlinked.
        try FileManager.default.moveItem(
            at: url, to: url.deletingLastPathComponent().appendingPathComponent("moved"))
        let selection = await harness.selection(
            for: [candidate.id], irreversible: false, highRisk: false)

        await Self.assertRejected(.missing) {
            _ = try await harness.validate(selection)
        }
    }

    func testATargetReplacedAfterScanningIsRejected() async throws {
        let harness = try await CleanupHarness()
        let candidate = try await harness.candidate(file: "project/node_modules")
        try await harness.replaceWithDifferentIdentity(candidate.id)
        let selection = await harness.selection(
            for: [candidate.id], irreversible: false, highRisk: false)

        await Self.assertRejected(.changed) {
            _ = try await harness.validate(selection)
        }
    }

    func testAnInvalidatedSnapshotCannotBeUsed() async throws {
        let harness = try await CleanupHarness()
        let candidate = try await harness.candidate(file: "project/node_modules")
        await harness.store.invalidate()
        let selection = await harness.selection(
            for: [candidate.id], irreversible: false, highRisk: false)

        await Self.assertRejected(.staleScan) {
            _ = try await harness.validate(selection)
        }
    }

    // MARK: - Consent

    func testAHighRiskItemNeedsItsOwnAcknowledgment() async throws {
        let harness = try await CleanupHarness()
        let archives = try await harness.candidate(
            file: "Library/Developer/Xcode/Archives",
            rule: "xcode.archives",
            risk: .high
        )
        let withoutConsent = await harness.selection(
            for: [archives.id], irreversible: true, highRisk: false)

        await Self.assertRejected(.consentRequired) {
            _ = try await harness.validate(withoutConsent)
        }

        let withConsent = await harness.selection(
            for: [archives.id], irreversible: true, highRisk: true)
        let plan = try await harness.validate(withConsent)
        XCTAssertEqual(plan.items.count, 1)
    }

    func testEveryDockerKindNeedsTheIrreversibleAcknowledgment() async throws {
        for kind in DockerOperation.allCases {
            let harness = try await CleanupHarness()
            let candidate = await harness.dockerCandidate(kind: kind, risk: .medium)
            let withoutConsent = await harness.selection(
                for: [candidate.id], irreversible: false, highRisk: true)

            await Self.assertRejected(.consentRequired) {
                _ = try await harness.validate(withoutConsent)
            }

            let withConsent = await harness.selection(
                for: [candidate.id], irreversible: true, highRisk: true)
            let plan = try await harness.validate(withConsent)
            XCTAssertEqual(plan.items.count, 1, "\(kind) should validate once acknowledged")
        }
    }

    func testADockerResourceTheDaemonNoLongerRecognisesIsRejected() async throws {
        let harness = try await CleanupHarness()
        let candidate = await harness.dockerCandidate(kind: .volume)
        await harness.docker.fail(for: candidate.id, with: .missing)
        let selection = await harness.selection(
            for: [candidate.id], irreversible: true, highRisk: true)

        await Self.assertRejected(.missing) {
            _ = try await harness.validate(selection)
        }
    }

    // MARK: - Plan shape

    func testThePlanExpiresAndCarriesItsPolicyRevision() async throws {
        let clock = MutableTestClock()
        let harness = try await CleanupHarness(clock: clock)
        let candidate = try await harness.candidate(file: "project/node_modules")
        let selection = await harness.selection(
            for: [candidate.id], irreversible: false, highRisk: false)

        let plan = try await harness.validate(selection)

        XCTAssertEqual(plan.expiresAt, clock.now().addingTimeInterval(cleanupPlanLifetime))
        XCTAssertEqual(plan.policyRevision, harness.currentSafetyContext().revision)
    }

    // MARK: - Structured issues

    func testInspectReportsEveryReasonWithoutThrowing() async throws {
        let harness = try await CleanupHarness()
        let good = try await harness.candidate(file: "project/node_modules")
        let archives = try await harness.candidate(
            file: "Library/Developer/Xcode/Archives", rule: "xcode.archives", risk: .high)
        let unknown = UUID()
        let selection = await harness.selection(
            for: [good.id, archives.id, unknown], irreversible: false, highRisk: false)

        let issues = await harness.inspect(selection)

        XCTAssertEqual(
            Set(issues.map(\.candidateID)), [archives.id, unknown],
            "the valid item must not appear as an issue")
        XCTAssertEqual(issues.first { $0.candidateID == archives.id }?.code, .consentRequired)
        XCTAssertEqual(issues.first { $0.candidateID == unknown }?.code, .unknownCandidate)
    }

    // MARK: - Helpers

    private static func assertRejected(
        _ expected: PolicyError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("expected \(expected) but validation succeeded", file: file, line: line)
        } catch let error as PolicyError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("expected \(expected) but got \(error)", file: file, line: line)
        }
    }
}
