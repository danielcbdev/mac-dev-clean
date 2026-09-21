import Domain
import Scanning
import TestSupport
import XCTest

@testable import CleanupRules

final class RuleCatalogTests: XCTestCase {

    // MARK: - Names alone prove nothing

    func testAnArbitraryBuildDirectoryIsNotAFlutterCandidate() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        _ = try tree.file("build/notes.txt", bytes: 8)

        let matches = try await RuleCatalog().matches(
            in: tree.root,
            files: LocalFileSystem(),
            git: FakeGitStatus()
        )

        XCTAssertTrue(matches.isEmpty)
    }

    func testNodeModulesWithoutAManifestIsNotACandidate() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        _ = try tree.file("node_modules/left-pad/index.js", bytes: 8)

        let matches = try await RuleCatalog().matches(
            in: tree.root,
            files: LocalFileSystem(),
            git: FakeGitStatus()
        )

        XCTAssertTrue(matches.isEmpty)
    }

    func testAnUnreadableManifestProducesNoCandidate() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        // Present but not valid JSON: the manifest cannot be read as evidence.
        try "this is not json".write(
            to: tree.root.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )
        _ = try tree.directory("node_modules")

        let matches = try await RuleCatalog().matches(
            in: tree.root,
            files: LocalFileSystem(),
            git: FakeGitStatus()
        )

        XCTAssertTrue(matches.isEmpty)
    }

    // MARK: - Node

    func testNodeModulesBesideAReadableManifestIsACandidate() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        try Self.writeJSON(["name": "app"], to: tree.root, named: "package.json")
        _ = try tree.file("node_modules/left-pad/index.js", bytes: 8)

        let matches = try await RuleCatalog().matches(
            in: tree.root,
            files: LocalFileSystem(),
            git: FakeGitStatus()
        )

        let match = try XCTUnwrap(matches.first { $0.ruleID == "node.modules" })
        XCTAssertEqual(match.url, tree.root.appendingPathComponent("node_modules"))
        XCTAssertEqual(match.category, .node)
        XCTAssertEqual(match.risk, .low)
        XCTAssertEqual(match.allowedRoot, tree.root)
        XCTAssertFalse(match.evidenceDigest.isEmpty)
    }

    func testTurboCacheRequiresATurboConfiguration() async throws {
        let withConfig = try FixtureTree()
        defer { try? withConfig.close() }
        try Self.writeJSON(["name": "app"], to: withConfig.root, named: "package.json")
        try Self.writeJSON(["tasks": [:]], to: withConfig.root, named: "turbo.json")
        _ = try withConfig.directory(".turbo")

        let without = try FixtureTree()
        defer { try? without.close() }
        try Self.writeJSON(["name": "app"], to: without.root, named: "package.json")
        _ = try without.directory(".turbo")

        let catalog = RuleCatalog()
        let present = try await catalog.matches(
            in: withConfig.root, files: LocalFileSystem(), git: FakeGitStatus())
        let absent = try await catalog.matches(
            in: without.root, files: LocalFileSystem(), git: FakeGitStatus())

        XCTAssertTrue(present.contains { $0.ruleID == "node.turbo" })
        XCTAssertFalse(absent.contains { $0.ruleID == "node.turbo" })
    }

    // MARK: - Flutter

    func testFlutterArtifactsRequireFlutterEvidenceInThePubspec() async throws {
        let flutter = try FixtureTree()
        defer { try? flutter.close() }
        try Self.writePubspec(flutter: true, to: flutter.root)
        _ = try flutter.directory("build")
        _ = try flutter.directory(".dart_tool")
        _ = try flutter.file(".flutter-plugins", bytes: 4)
        _ = try flutter.file(".flutter-plugins-dependencies", bytes: 4)

        let matches = try await RuleCatalog().matches(
            in: flutter.root, files: LocalFileSystem(), git: FakeGitStatus())

        XCTAssertEqual(
            Set(matches.map(\.ruleID)),
            ["flutter.build", "flutter.dartTool", "flutter.plugins", "flutter.pluginDependencies"]
        )
        let build = try XCTUnwrap(matches.first { $0.ruleID == "flutter.build" })
        XCTAssertEqual(build.category, .flutter)
        XCTAssertEqual(build.risk, .low)
    }

    func testAPubspecWithoutFlutterProducesNoBuildCandidate() async throws {
        let dart = try FixtureTree()
        defer { try? dart.close() }
        try Self.writePubspec(flutter: false, to: dart.root)
        _ = try dart.directory("build")
        _ = try dart.directory(".dart_tool")

        let matches = try await RuleCatalog().matches(
            in: dart.root, files: LocalFileSystem(), git: FakeGitStatus())

        XCTAssertTrue(matches.isEmpty)
    }

    // MARK: - Web builds

    func testAnIgnoredDistWithDeclaredOutputIsACandidate() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        try Self.writeJSON(["name": "app"], to: tree.root, named: "package.json")
        try Self.writeJSON(
            ["compilerOptions": ["outDir": "dist"]], to: tree.root, named: "tsconfig.json")
        let dist = try tree.directory("dist")
        _ = try tree.file("dist/bundle.js", bytes: 16)

        let matches = try await RuleCatalog().matches(
            in: tree.root,
            files: LocalFileSystem(),
            git: FakeGitStatus(ignored: [dist.standardizedFileURL.path])
        )

        let match = try XCTUnwrap(matches.first { $0.ruleID == "web.dist" })
        XCTAssertEqual(match.category, .webBuild)
        XCTAssertEqual(match.risk, .medium)
    }

    func testATrackedDistIsNeverACandidate() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        try Self.writeJSON(["name": "app"], to: tree.root, named: "package.json")
        try Self.writeJSON(
            ["compilerOptions": ["outDir": "dist"]], to: tree.root, named: "tsconfig.json")
        let dist = try tree.directory("dist")
        _ = try tree.file("dist/bundle.js", bytes: 16)

        let matches = try await RuleCatalog().matches(
            in: tree.root,
            files: LocalFileSystem(),
            git: FakeGitStatus(
                tracked: [dist.standardizedFileURL.path],
                ignored: [dist.standardizedFileURL.path]
            )
        )

        XCTAssertFalse(matches.contains { $0.ruleID == "web.dist" })
    }

    func testADistWithoutDeclaredOutputIsNotACandidate() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        try Self.writeJSON(["name": "app"], to: tree.root, named: "package.json")
        let dist = try tree.directory("dist")
        _ = try tree.file("dist/bundle.js", bytes: 16)

        let matches = try await RuleCatalog().matches(
            in: tree.root,
            files: LocalFileSystem(),
            git: FakeGitStatus(ignored: [dist.standardizedFileURL.path])
        )

        XCTAssertFalse(matches.contains { $0.ruleID == "web.dist" })
    }

    func testADistThatGitDoesNotIgnoreIsNotACandidate() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        try Self.writeJSON(["name": "app"], to: tree.root, named: "package.json")
        try Self.writeJSON(
            ["compilerOptions": ["outDir": "dist"]], to: tree.root, named: "tsconfig.json")
        _ = try tree.directory("dist")
        _ = try tree.file("dist/bundle.js", bytes: 16)

        let matches = try await RuleCatalog().matches(
            in: tree.root, files: LocalFileSystem(), git: FakeGitStatus())

        XCTAssertFalse(matches.contains { $0.ruleID == "web.dist" })
    }

    func testAnUnavailableGitAnswerSkipsTheAmbiguousArtifact() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        try Self.writeJSON(["name": "app"], to: tree.root, named: "package.json")
        try Self.writeJSON(
            ["compilerOptions": ["outDir": "dist"]], to: tree.root, named: "tsconfig.json")
        _ = try tree.file("dist/bundle.js", bytes: 16)
        _ = try tree.file("node_modules/left-pad/index.js", bytes: 8)

        let matches = try await RuleCatalog().matches(
            in: tree.root,
            files: LocalFileSystem(),
            git: FakeGitStatus(failure: .unavailable)
        )

        // dist is skipped, but the unambiguous node_modules is unaffected.
        XCTAssertFalse(matches.contains { $0.ruleID == "web.dist" })
        XCTAssertTrue(matches.contains { $0.ruleID == "node.modules" })
    }

    // MARK: - Symlinks

    func testASymlinkedArtifactIsNotACandidate() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        try Self.writeJSON(["name": "app"], to: tree.root, named: "package.json")
        let real = try tree.directory("elsewhere")
        _ = try tree.symlink("node_modules", to: real)

        let matches = try await RuleCatalog().matches(
            in: tree.root, files: LocalFileSystem(), git: FakeGitStatus())

        XCTAssertTrue(matches.isEmpty)
    }

    // MARK: - Global cache roots

    func testGlobalRootsAreHomeRelativeAndUnique() {
        let home = URL(fileURLWithPath: "/fixture/home")
        let roots = RuleCatalog().globalRoots(home: home)

        XCTAssertEqual(
            roots["xcode.derived"],
            [home.appendingPathComponent("Library/Developer/Xcode/DerivedData")]
        )
        XCTAssertEqual(
            roots["yarn.cache"],
            [
                home.appendingPathComponent(".cache/yarn"),
                home.appendingPathComponent("Library/Caches/Yarn"),
            ]
        )

        let all = roots.values.flatMap { $0 }.map(\.standardizedFileURL.path)
        XCTAssertEqual(all.count, Set(all).count, "global cache locations must be unique")
        for path in all {
            XCTAssertTrue(
                path.hasPrefix(home.path + "/"),
                "\(path) is not inside the user's home"
            )
        }
    }

    func testGlobalRootsExcludeToolchainsAndInstalledBinaries() {
        let home = URL(fileURLWithPath: "/fixture/home")
        let all = RuleCatalog().globalRoots(home: home).values
            .flatMap { $0 }
            .map(\.standardizedFileURL.path)

        for forbidden in [
            "/.gradle", "/.cargo/bin", "/Library/Caches/Homebrew/Cellar",
            "/Library/Developer/CoreSimulator/Devices", "/Library/Android",
        ] {
            XCTAssertFalse(
                all.contains { $0 == home.path + forbidden },
                "\(forbidden) must not be a cleanup location"
            )
        }
        XCTAssertFalse(all.contains(home.appendingPathComponent(".gradle").path))
    }

    func testArchivesAndDeviceSupportCarryHigherRisk() throws {
        let rules = GlobalCacheRules.all
        let archives = try XCTUnwrap(rules.first { $0.id == "xcode.archives" })
        let devices = try XCTUnwrap(rules.first { $0.id == "xcode.devices" })

        XCTAssertEqual(archives.risk, .high)
        XCTAssertEqual(devices.risk, .medium)
        XCTAssertTrue(
            rules.filter { !["xcode.archives", "xcode.devices"].contains($0.id) }
                .allSatisfy { $0.risk == .low }
        )
    }

    // MARK: - Helpers

    private static func writeJSON(
        _ value: [String: Any],
        to root: URL,
        named name: String
    ) throws {
        let data = try JSONSerialization.data(withJSONObject: value)
        try data.write(to: root.appendingPathComponent(name))
    }

    private static func writePubspec(flutter: Bool, to root: URL) throws {
        let body =
            flutter
            ? "name: app\ndependencies:\n  flutter:\n    sdk: flutter\n"
            : "name: tool\ndependencies:\n  args: ^2.0.0\n"
        try body.write(
            to: root.appendingPathComponent("pubspec.yaml"),
            atomically: true,
            encoding: .utf8
        )
    }
}
