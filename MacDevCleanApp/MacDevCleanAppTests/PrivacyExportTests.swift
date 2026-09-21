import Cleanup
import Domain
import TestSupport
import XCTest

@MainActor
final class PrivacyExportTests: XCTestCase {
    func testDiagnosticExportContainsNoCustomerMarkerOrFilesystemLocations() async throws {
        let harness = try await CleanupHarness()
        let candidate = try await harness.candidate(
            file: "private-customer-database/node_modules", bytes: 4096)
        let selection = await harness.selection(
            for: [candidate.id], irreversible: false, highRisk: false)
        let plan = try await harness.validate(selection)
        let summary = await harness.execute(plan)

        let report = CleanupDiagnostics.report(for: summary, appVersion: "1.0.0")

        XCTAssertFalse(report.contains("private-customer-database"))
        XCTAssertFalse(report.contains(harness.tree.root.path))
        XCTAssertFalse(report.contains("file://"))
        XCTAssertTrue(report.contains("app: 1.0.0"))
        XCTAssertTrue(report.contains("items: 1"))
        XCTAssertTrue(report.contains("outcome.movedToTrash: 1"))
    }
}
