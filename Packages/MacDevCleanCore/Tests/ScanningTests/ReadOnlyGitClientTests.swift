import Domain
import TestSupport
import XCTest

@testable import Scanning

/// Exercises the Git adapter against a repository the test creates and owns.
///
/// Nothing here touches a repository outside the fixture's temporary directory.
final class ReadOnlyGitClientTests: XCTestCase {

    func testReportsTrackedContentInsideADirectory() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        try Self.git(["init", "-q"], in: tree.root)
        _ = try tree.file("dist/index.html", bytes: 4)
        try Self.git(["add", "--", "dist/index.html"], in: tree.root)

        let client = ReadOnlyGitClient()
        let tracked = try await client.containsTrackedFiles(
            at: tree.root.appendingPathComponent("dist"),
            repository: tree.root
        )

        XCTAssertTrue(tracked)
    }

    func testReportsNoTrackedContentForAGeneratedDirectory() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        try Self.git(["init", "-q"], in: tree.root)
        _ = try tree.file("src/main.ts", bytes: 4)
        try Self.git(["add", "--", "src/main.ts"], in: tree.root)
        _ = try tree.file("dist/bundle.js", bytes: 4)

        let client = ReadOnlyGitClient()
        let tracked = try await client.containsTrackedFiles(
            at: tree.root.appendingPathComponent("dist"),
            repository: tree.root
        )

        XCTAssertFalse(tracked)
    }

    func testReadsIgnoreRules() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        try Self.git(["init", "-q"], in: tree.root)
        try "dist/\n".write(
            to: tree.root.appendingPathComponent(".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        _ = try tree.directory("dist")
        _ = try tree.directory("src")

        let client = ReadOnlyGitClient()

        let ignored = try await client.isIgnored(
            tree.root.appendingPathComponent("dist"),
            repository: tree.root
        )
        let notIgnored = try await client.isIgnored(
            tree.root.appendingPathComponent("src"),
            repository: tree.root
        )

        XCTAssertTrue(ignored)
        XCTAssertFalse(notIgnored)
    }

    func testAPathOutsideTheRepositoryFailsClosed() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let other = try FixtureTree()
        defer { try? other.close() }
        try Self.git(["init", "-q"], in: tree.root)

        let client = ReadOnlyGitClient()

        do {
            _ = try await client.containsTrackedFiles(
                at: other.root.appendingPathComponent("dist"),
                repository: tree.root
            )
            XCTFail("expected a repository mismatch")
        } catch let error as ReadOnlyGitClient.Failure {
            XCTAssertEqual(error, .repositoryMismatch)
        }
    }

    func testAPathContainingPathspecMagicIsTreatedLiterally() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        try Self.git(["init", "-q"], in: tree.root)
        // A literal directory whose name would be a wildcard to a shell or to
        // Git's default pathspec parsing.
        _ = try tree.file("weird*name/file.txt", bytes: 4)
        _ = try tree.file("other/file.txt", bytes: 4)
        try Self.git(["add", "--", "other/file.txt"], in: tree.root)

        let client = ReadOnlyGitClient()
        let tracked = try await client.containsTrackedFiles(
            at: tree.root.appendingPathComponent("weird*name"),
            repository: tree.root
        )

        // If the asterisk were interpreted, this would have matched "other".
        XCTAssertFalse(tracked)
    }

    func testNotARepositoryFailsRatherThanAnsweringFalse() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        _ = try tree.directory("dist")

        let client = ReadOnlyGitClient()

        do {
            _ = try await client.containsTrackedFiles(
                at: tree.root.appendingPathComponent("dist"),
                repository: tree.root
            )
            XCTFail("expected a non-zero exit from git outside a repository")
        } catch let error as ReadOnlyGitClient.Failure {
            guard case .unexpectedExit = error else {
                return XCTFail("expected unexpectedExit, got \(error)")
            }
        }
    }

    // MARK: - Helpers

    fileprivate static func git(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        process.environment = [
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_AUTHOR_NAME": "Fixture",
            "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
            "GIT_COMMITTER_NAME": "Fixture",
            "GIT_COMMITTER_EMAIL": "fixture@example.invalid",
            "LC_ALL": "C",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "FixtureGit",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "git \(arguments.joined(separator: " "))"]
            )
        }
    }
}

extension ReadOnlyGitClientTests {
    /// `check-ignore` cannot be given literal pathspec magic, so the adapter
    /// verifies the pathname Git echoes back instead. A name containing a
    /// wildcard must not be answered with a different path's verdict.
    func testAnIgnoreAnswerIsAcceptedOnlyForTheExactPathAsked() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        try Self.gitSetup(["init", "-q"], in: tree.root)
        try "other/\n".write(
            to: tree.root.appendingPathComponent(".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        _ = try tree.directory("other")
        _ = try tree.directory("weird*name")

        let client = ReadOnlyGitClient()

        let ignored = try await client.isIgnored(
            tree.root.appendingPathComponent("weird*name"),
            repository: tree.root
        )

        XCTAssertFalse(ignored)
    }

    fileprivate static func gitSetup(_ arguments: [String], in directory: URL) throws {
        try git(arguments, in: directory)
    }
}
