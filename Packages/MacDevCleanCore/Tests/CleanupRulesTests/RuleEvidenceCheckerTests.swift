import Domain
import Scanning
import TestSupport
import XCTest

@testable import CleanupRules

final class RuleEvidenceCheckerTests: XCTestCase {

    func testADistCandidateBecomesInvalidWhenGitStartsTrackingAChild() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        try Self.writeJSON(["name": "app"], to: tree.root, named: "package.json")
        try Self.writeJSON(
            ["compilerOptions": ["outDir": "dist"]], to: tree.root, named: "tsconfig.json")
        let dist = try tree.directory("dist")
        _ = try tree.file("dist/bundle.js", bytes: 8)

        let atScanTime = FakeGitStatus(ignored: [dist.standardizedFileURL.path])
        let catalog = RuleCatalog()
        let atScanTimeMatches = try await catalog.matches(
            in: tree.root, files: LocalFileSystem(), git: atScanTime)
        let match = try XCTUnwrap(atScanTimeMatches.first { $0.ruleID == "web.dist" })
        let candidate = Self.candidate(from: match)
        let evidence = Self.evidence(from: match)

        // Still valid against the world as it was.
        try await RuleEvidenceChecker(
            files: LocalFileSystem(), git: atScanTime, catalog: catalog
        ).verify(candidate, evidence: evidence)

        // Somebody commits the built site between the scan and the confirmation.
        let afterCommit = FakeGitStatus(
            tracked: [dist.standardizedFileURL.path],
            ignored: [dist.standardizedFileURL.path]
        )

        await Self.assertRejected(.changed) {
            try await RuleEvidenceChecker(
                files: LocalFileSystem(), git: afterCommit, catalog: catalog
            ).verify(candidate, evidence: evidence)
        }
    }

    func testAFlutterCandidateBecomesInvalidWhenItsManifestChanges() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let pubspec = tree.root.appendingPathComponent("pubspec.yaml")
        try "name: app\ndependencies:\n  flutter:\n    sdk: flutter\n"
            .write(to: pubspec, atomically: true, encoding: .utf8)
        _ = try tree.directory("build")

        let catalog = RuleCatalog()
        let git = FakeGitStatus()
        let currentMatches = try await catalog.matches(
            in: tree.root, files: LocalFileSystem(), git: git)
        let match = try XCTUnwrap(currentMatches.first { $0.ruleID == "flutter.build" })
        let candidate = Self.candidate(from: match)
        let evidence = Self.evidence(from: match)

        try await RuleEvidenceChecker(files: LocalFileSystem(), git: git, catalog: catalog)
            .verify(candidate, evidence: evidence)

        // The project stops being a Flutter project.
        try "name: app\ndependencies:\n  args: ^2.0.0\n"
            .write(to: pubspec, atomically: true, encoding: .utf8)

        await Self.assertRejected(.changed) {
            try await RuleEvidenceChecker(files: LocalFileSystem(), git: git, catalog: catalog)
                .verify(candidate, evidence: evidence)
        }
    }

    func testAGlobalCacheCandidateRequiresItsRegisteredRoot() async throws {
        let home = URL(fileURLWithPath: "/fixture/home")
        let registered = home.appendingPathComponent("Library/Caches/Homebrew")
        let candidate = CleanupCandidate(
            id: UUID(),
            ruleID: "brew.cache",
            location: .file(registered),
            category: .homebrew,
            size: 1,
            allocatedSize: 1,
            risk: .low,
            method: .trash,
            consequenceKey: ConsequenceKey.redownloadTooling
        )
        let checker = RuleEvidenceChecker(
            files: LocalFileSystem(), git: FakeGitStatus(), catalog: RuleCatalog())

        try await checker.verify(
            candidate,
            evidence: CandidateEvidence(
                identity: nil,
                allowedRoot: registered,
                contextFingerprint: nil,
                ruleEvidenceDigest: RuleCatalog.digest(
                    ruleID: "brew.cache", registeredRoot: registered)
            )
        )

        // A different registered root does not authorise this location.
        await Self.assertRejected(.changed) {
            try await checker.verify(
                candidate,
                evidence: CandidateEvidence(
                    identity: nil,
                    allowedRoot: registered,
                    contextFingerprint: nil,
                    ruleEvidenceDigest: RuleCatalog.digest(
                        ruleID: "brew.cache",
                        registeredRoot: home.appendingPathComponent("Library/Caches/pip")
                    )
                )
            )
        }
    }

    func testAnUnknownRuleIsUnsupported() async throws {
        let candidate = CleanupCandidate(
            id: UUID(),
            ruleID: "invented.rule",
            location: .file(URL(fileURLWithPath: "/fixture/anything")),
            category: .node,
            size: nil,
            allocatedSize: nil,
            risk: .low,
            method: .trash,
            consequenceKey: "x"
        )

        await Self.assertRejected(.unsupported) {
            try await RuleEvidenceChecker(
                files: LocalFileSystem(), git: FakeGitStatus(), catalog: RuleCatalog()
            ).verify(
                candidate,
                evidence: CandidateEvidence(
                    identity: nil, allowedRoot: nil, contextFingerprint: nil,
                    ruleEvidenceDigest: ""
                )
            )
        }
    }

    func testOneManifestCannotBeReplayedAsEvidenceForAnotherRule() {
        let manifest = Data("{\"name\":\"app\"}".utf8)

        XCTAssertNotEqual(
            RuleCatalog.digest(ruleID: "node.modules", evidence: manifest),
            RuleCatalog.digest(ruleID: "node.turbo", evidence: manifest)
        )
    }

    // MARK: - Helpers

    private static func candidate(from match: RuleMatch) -> CleanupCandidate {
        CleanupCandidate(
            id: UUID(),
            ruleID: match.ruleID,
            location: .file(match.url),
            category: match.category,
            size: nil,
            allocatedSize: nil,
            risk: match.risk,
            method: .trash,
            consequenceKey: match.consequenceKey
        )
    }

    private static func evidence(from match: RuleMatch) -> CandidateEvidence {
        CandidateEvidence(
            identity: nil,
            allowedRoot: match.allowedRoot,
            contextFingerprint: nil,
            ruleEvidenceDigest: match.evidenceDigest
        )
    }

    private static func writeJSON(
        _ value: [String: Any],
        to root: URL,
        named name: String
    ) throws {
        let data = try JSONSerialization.data(withJSONObject: value)
        try data.write(to: root.appendingPathComponent(name))
    }

    private static func assertRejected(
        _ expected: PolicyError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("expected \(expected) but the check succeeded", file: file, line: line)
        } catch let error as PolicyError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("expected \(expected) but got \(error)", file: file, line: line)
        }
    }
}
