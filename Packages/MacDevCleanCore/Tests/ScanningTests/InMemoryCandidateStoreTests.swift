import Domain
import TestSupport
import XCTest

@testable import Scanning

final class InMemoryCandidateStoreTests: XCTestCase {

    func testLooksUpASavedCandidateWithItsEvidenceAndRevision() async throws {
        let store = InMemoryCandidateStore()
        let candidate = Self.candidate()
        let evidence = Self.evidence()
        await store.save(
            ScanSnapshot(
                id: Self.scanID,
                policyRevision: 7,
                candidates: [candidate],
                evidence: [candidate.id: evidence]
            )
        )

        let (found, foundEvidence, revision) = try await store.lookup(
            scanID: Self.scanID,
            candidateID: candidate.id
        )

        XCTAssertEqual(found, candidate)
        XCTAssertEqual(foundEvidence, evidence)
        XCTAssertEqual(revision, 7)
    }

    func testAnUnknownScanIsStale() async throws {
        let store = InMemoryCandidateStore()

        await Self.assertRejected(.staleScan) {
            _ = try await store.lookup(scanID: Self.scanID, candidateID: UUID())
        }
    }

    func testAnUnknownCandidateInAKnownScanIsRejected() async throws {
        let store = InMemoryCandidateStore()
        let candidate = Self.candidate()
        await store.save(
            ScanSnapshot(
                id: Self.scanID,
                policyRevision: 1,
                candidates: [candidate],
                evidence: [candidate.id: Self.evidence()]
            )
        )

        await Self.assertRejected(.unknownCandidate) {
            _ = try await store.lookup(scanID: Self.scanID, candidateID: UUID())
        }
    }

    func testInvalidationDropsEverySnapshot() async throws {
        let store = InMemoryCandidateStore()
        let candidate = Self.candidate()
        await store.save(
            ScanSnapshot(
                id: Self.scanID,
                policyRevision: 1,
                candidates: [candidate],
                evidence: [candidate.id: Self.evidence()]
            )
        )

        await store.invalidate()

        await Self.assertRejected(.staleScan) {
            _ = try await store.lookup(scanID: Self.scanID, candidateID: candidate.id)
        }
    }

    // MARK: - Helpers

    private static let scanID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!

    private static func candidate() -> CleanupCandidate {
        CleanupCandidate(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!,
            ruleID: "node.modules",
            location: .file(URL(fileURLWithPath: "/fixture/app/node_modules")),
            category: .node,
            size: 1024,
            allocatedSize: 4096,
            risk: .low,
            method: .trash,
            consequenceKey: ConsequenceKey.reinstallDependencies
        )
    }

    private static func evidence() -> CandidateEvidence {
        CandidateEvidence(
            identity: FileIdentity(device: 1, inode: 2, modifiedNanoseconds: 3),
            allowedRoot: URL(fileURLWithPath: "/fixture/app"),
            contextFingerprint: nil,
            ruleEvidenceDigest: "digest"
        )
    }

    private static func assertRejected(
        _ expected: PolicyError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("expected \(expected) but the call succeeded", file: file, line: line)
        } catch let error as PolicyError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("expected \(expected) but got \(error)", file: file, line: line)
        }
    }
}
