import Domain
import TestSupport
import XCTest

@testable import Scanning

final class ProjectDiscoveryTests: XCTestCase {

    func testFindsNestedPackagesInAMonorepo() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        _ = try tree.file("package.json", bytes: 2)
        _ = try tree.file("packages/api/package.json", bytes: 2)
        _ = try tree.file("packages/web/package.json", bytes: 2)
        _ = try tree.file("packages/web/src/index.ts", bytes: 2)

        let found = try await ProjectDiscovery(files: LocalFileSystem()).projects(in: tree.root)

        XCTAssertEqual(
            found.map(\.lastPathComponent).sorted(),
            [tree.root.lastPathComponent, "api", "web"].sorted()
        )
    }

    func testNeverDescendsIntoDependencyTrees() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        _ = try tree.file("package.json", bytes: 2)
        _ = try tree.file("node_modules/left-pad/package.json", bytes: 2)
        _ = try tree.file("node_modules/left-pad/node_modules/inner/package.json", bytes: 2)

        let found = try await ProjectDiscovery(files: LocalFileSystem()).projects(in: tree.root)

        XCTAssertEqual(found, [tree.root])
    }

    func testNeverDescendsIntoGeneratedOutput() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        _ = try tree.file("package.json", bytes: 2)
        _ = try tree.file("dist/package.json", bytes: 2)
        _ = try tree.file("build/package.json", bytes: 2)
        _ = try tree.file(".dart_tool/package.json", bytes: 2)

        let found = try await ProjectDiscovery(files: LocalFileSystem()).projects(in: tree.root)

        XCTAssertEqual(found, [tree.root])
    }

    func testDoesNotWalkIntoBundlesOrFollowLinks() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        _ = try tree.file("Demo.app/Contents/package.json", bytes: 2)
        let real = try tree.directory("real")
        _ = try tree.file("real/package.json", bytes: 2)
        _ = try tree.symlink("alias", to: real)

        let found = try await ProjectDiscovery(files: LocalFileSystem()).projects(in: tree.root)

        XCTAssertEqual(found, [real])
    }

    func testAnUnreadableSubtreeDoesNotLoseOtherResults() async throws {
        let root = URL(fileURLWithPath: "/fixture/root")
        let good = root.appendingPathComponent("good")
        let locked = root.appendingPathComponent("locked")
        let files = StubFileSystem()
        await files.setChildren(
            [
                .stub(url: good, kind: .directory, inode: 2),
                .stub(url: locked, kind: .directory, inode: 3),
            ],
            of: root
        )
        await files.setChildren(
            [.stub(url: good.appendingPathComponent("package.json"), inode: 4)],
            of: good
        )
        await files.setFailure(.permissionDenied, at: locked)

        let found = try await ProjectDiscovery(files: files).projects(in: root)

        XCTAssertEqual(found, [good])
    }

    func testStopsAtTheDepthLimit() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        _ = try tree.file("a/b/c/package.json", bytes: 2)

        let shallow = try await ProjectDiscovery(files: LocalFileSystem(), maximumDepth: 1)
            .projects(in: tree.root)
        let deep = try await ProjectDiscovery(files: LocalFileSystem(), maximumDepth: 5)
            .projects(in: tree.root)

        XCTAssertTrue(shallow.isEmpty)
        XCTAssertEqual(deep.map(\.lastPathComponent), ["c"])
    }
}
