import Domain
import TestSupport
import XCTest

@testable import Scanning

final class PathPolicyTests: XCTestCase {

    // MARK: - Exclusion matching

    func testSiblingPrefixIsNotAnExcludedDescendant() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let excluded = try tree.directory("work/app")
        let sibling = try tree.directory("work/application")

        let policy = PathPolicy(files: LocalFileSystem())

        let matches = try await policy.matches(sibling, exclusion: excluded)
        XCTAssertFalse(matches)
    }

    func testAnExclusionEqualToTheCandidateMatches() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let target = try tree.directory("work/app")

        let policy = PathPolicy(files: LocalFileSystem())

        let matches = try await policy.matches(target, exclusion: target)
        XCTAssertTrue(matches)
    }

    func testAnAncestorExclusionMatchesItsDescendant() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let ancestor = try tree.directory("work")
        let candidate = try tree.directory("work/app/node_modules")

        let policy = PathPolicy(files: LocalFileSystem())

        let matches = try await policy.matches(candidate, exclusion: ancestor)
        XCTAssertTrue(matches)
    }

    func testAnExclusionNestedInsideTheCandidateMatches() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let candidate = try tree.directory("work/app/node_modules")
        let keepThis = try tree.directory("work/app/node_modules/.bin")

        let policy = PathPolicy(files: LocalFileSystem())

        // Cleaning the ancestor as a whole would take the excluded child with
        // it, so the exclusion has to block the ancestor.
        let matches = try await policy.matches(candidate, exclusion: keepThis)
        XCTAssertTrue(matches)
    }

    // MARK: - Scope

    func testAProjectArtifactInsideAConfiguredRootIsAllowed() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let project = try tree.directory("work/app")
        let candidate = try tree.directory("work/app/node_modules")
        let context = Self.context(home: tree.root, projectRoots: [project])

        let policy = PathPolicy(files: LocalFileSystem())

        try await policy.check(candidate, ruleID: "node.modules", context: context)
    }

    func testAnArtifactOutsideEveryConfiguredRootIsRejected() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let project = try tree.directory("work/app")
        let stranger = try tree.directory("elsewhere/node_modules")
        let context = Self.context(home: tree.root, projectRoots: [project])

        let policy = PathPolicy(files: LocalFileSystem())

        await Self.assertRejected(.outsideScope) {
            try await policy.check(stranger, ruleID: "node.modules", context: context)
        }
    }

    func testTheProjectRootItselfIsNeverACandidate() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let project = try tree.directory("work/app")
        let context = Self.context(home: tree.root, projectRoots: [project])

        let policy = PathPolicy(files: LocalFileSystem())

        await Self.assertRejected(.protectedPath) {
            try await policy.check(project, ruleID: "node.modules", context: context)
        }
    }

    func testAnAncestorOfAProjectRootIsNeverACandidate() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let project = try tree.directory("work/app")
        let ancestor = try tree.directory("work")
        let context = Self.context(home: tree.root, projectRoots: [project])

        let policy = PathPolicy(files: LocalFileSystem())

        await Self.assertRejected(.protectedPath) {
            try await policy.check(ancestor, ruleID: "node.modules", context: context)
        }
    }

    func testAGlobalCacheRuleAcceptsOnlyItsRegisteredRoot() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let registered = try tree.directory("Library/Caches/Homebrew")
        let other = try tree.directory("Library/Caches/Something")
        var context = Self.context(home: tree.root, projectRoots: [])
        context = SafetyContext(
            home: context.home,
            projectRoots: context.projectRoots,
            largeFileRoots: context.largeFileRoots,
            globalRuleRoots: ["brew.cache": [registered]],
            exclusions: context.exclusions,
            revision: context.revision
        )

        let policy = PathPolicy(files: LocalFileSystem())

        try await policy.check(registered, ruleID: "brew.cache", context: context)
        await Self.assertRejected(.outsideScope) {
            try await policy.check(other, ruleID: "brew.cache", context: context)
        }
    }

    func testAnUnknownRuleIsRejected() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let project = try tree.directory("work/app")
        let candidate = try tree.directory("work/app/node_modules")
        let context = Self.context(home: tree.root, projectRoots: [project])

        let policy = PathPolicy(files: LocalFileSystem())

        await Self.assertRejected(.unsupported) {
            try await policy.check(candidate, ruleID: "totally.invented", context: context)
        }
    }

    // MARK: - Protected locations

    func testProtectedSystemRootsAndTheirDescendantsAreRejected() async throws {
        let policy = PathPolicy(files: LocalFileSystem())
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let context = Self.context(home: home, projectRoots: [URL(fileURLWithPath: "/")])

        for path in [
            "/", "/System", "/System/Library/Caches", "/Library", "/Applications", "/Users",
            home.path,
        ] {
            await Self.assertRejected(.protectedPath) {
                try await policy.check(
                    URL(fileURLWithPath: path),
                    ruleID: "node.modules",
                    context: context
                )
            }
        }
    }

    // MARK: - Filesystem boundaries

    func testASymbolicLinkCandidateIsRejected() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let project = try tree.directory("work/app")
        let real = try tree.directory("work/app/real")
        let link = try tree.symlink("work/app/node_modules", to: real)
        let context = Self.context(home: tree.root, projectRoots: [project])

        let policy = PathPolicy(files: LocalFileSystem())

        await Self.assertRejected(.symbolicLink) {
            try await policy.check(link, ruleID: "node.modules", context: context)
        }
    }

    func testASymbolicLinkAncestorCannotSmuggleATargetIntoScope() async throws {
        let inside = try FixtureTree()
        defer { try? inside.close() }
        let outside = try FixtureTree()
        defer { try? outside.close() }

        let project = try inside.directory("work/app")
        let realTarget = try outside.directory("secret/node_modules")
        // work/app/link -> <other tree>/secret
        _ = try inside.symlink("work/app/link", to: outside.root.appendingPathComponent("secret"))
        let disguised = project.appendingPathComponent("link/node_modules")
        let context = Self.context(home: inside.root, projectRoots: [project])

        let policy = PathPolicy(files: LocalFileSystem())

        XCTAssertTrue(FileManager.default.fileExists(atPath: realTarget.path))
        await Self.assertRejected(.outsideScope) {
            try await policy.check(disguised, ruleID: "node.modules", context: context)
        }
    }

    func testAMissingTargetIsRejected() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let project = try tree.directory("work/app")
        let context = Self.context(home: tree.root, projectRoots: [project])

        let policy = PathPolicy(files: LocalFileSystem())

        await Self.assertRejected(.missing) {
            try await policy.check(
                project.appendingPathComponent("node_modules"),
                ruleID: "node.modules",
                context: context
            )
        }
    }

    func testATargetOnAnotherVolumeIsRejected() async throws {
        let project = URL(fileURLWithPath: "/fixture/work/app")
        let candidate = project.appendingPathComponent("node_modules")
        let files = StubFileSystem()
        await files.setEntry(
            .stub(url: URL(fileURLWithPath: "/fixture"), kind: .directory, device: 1, inode: 1))
        await files.setEntry(
            .stub(url: URL(fileURLWithPath: "/fixture/work"), kind: .directory, device: 1, inode: 2)
        )
        await files.setEntry(.stub(url: project, kind: .directory, device: 1, inode: 3))
        // Same path shape, different device: a separately mounted volume.
        await files.setEntry(
            .stub(url: candidate, kind: .directory, device: 99, inode: 4, isMount: true)
        )
        let context = Self.context(home: URL(fileURLWithPath: "/fixture"), projectRoots: [project])

        let policy = PathPolicy(files: files)

        await Self.assertRejected(.protectedPath) {
            try await policy.check(candidate, ruleID: "node.modules", context: context)
        }
    }

    func testACloudPlaceholderTargetIsRejected() async throws {
        let project = URL(fileURLWithPath: "/fixture/work/app")
        let candidate = project.appendingPathComponent("node_modules")
        let files = StubFileSystem()
        await files.setEntry(
            .stub(url: URL(fileURLWithPath: "/fixture"), kind: .directory, device: 1, inode: 1))
        await files.setEntry(
            .stub(url: URL(fileURLWithPath: "/fixture/work"), kind: .directory, device: 1, inode: 2)
        )
        await files.setEntry(.stub(url: project, kind: .directory, device: 1, inode: 3))
        await files.setEntry(
            .stub(url: candidate, kind: .directory, device: 1, inode: 4, isCloudPlaceholder: true)
        )
        let context = Self.context(home: URL(fileURLWithPath: "/fixture"), projectRoots: [project])

        let policy = PathPolicy(files: files)

        await Self.assertRejected(.unsupported) {
            try await policy.check(candidate, ruleID: "node.modules", context: context)
        }
    }

    // MARK: - Exclusions applied during the check

    func testAPathExclusionBlocksTheCandidate() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let project = try tree.directory("work/app")
        let candidate = try tree.directory("work/app/node_modules")
        let context = Self.context(
            home: tree.root,
            projectRoots: [project],
            exclusions: [.path(candidate)]
        )

        let policy = PathPolicy(files: LocalFileSystem())

        await Self.assertRejected(.excluded) {
            try await policy.check(candidate, ruleID: "node.modules", context: context)
        }
    }

    func testAnExcludedDescendantBlocksCleaningItsAncestor() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let project = try tree.directory("work/app")
        let candidate = try tree.directory("work/app/node_modules")
        let keepThis = try tree.directory("work/app/node_modules/.bin")
        let context = Self.context(
            home: tree.root,
            projectRoots: [project],
            exclusions: [.path(keepThis)]
        )

        let policy = PathPolicy(files: LocalFileSystem())

        await Self.assertRejected(.excluded) {
            try await policy.check(candidate, ruleID: "node.modules", context: context)
        }
    }

    func testARuleExclusionBlocksEveryCandidateOfThatRule() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let project = try tree.directory("work/app")
        let candidate = try tree.directory("work/app/node_modules")
        let context = Self.context(
            home: tree.root,
            projectRoots: [project],
            exclusions: [.rule("node.modules")]
        )

        let policy = PathPolicy(files: LocalFileSystem())

        await Self.assertRejected(.excluded) {
            try await policy.check(candidate, ruleID: "node.modules", context: context)
        }
    }

    // MARK: - Helpers

    private static func context(
        home: URL,
        projectRoots: [URL],
        largeFileRoots: [URL] = [],
        globalRuleRoots: [CleanupRuleID: [URL]] = [:],
        exclusions: [Exclusion] = []
    ) -> SafetyContext {
        SafetyContext(
            home: home,
            projectRoots: projectRoots,
            largeFileRoots: largeFileRoots,
            globalRuleRoots: globalRuleRoots,
            exclusions: exclusions,
            revision: 1
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
            XCTFail("expected \(expected) but the check succeeded", file: file, line: line)
        } catch let error as PolicyError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("expected \(expected) but got \(error)", file: file, line: line)
        }
    }
}
