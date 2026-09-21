import XCTest

import TestSupport

final class FixtureTreeTests: XCTestCase {
    func testRejectsParentTraversalAndWritesNothingOutsideItsRoot() throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }

        let sibling = tree.root.deletingLastPathComponent()
            .appendingPathComponent("escape")

        XCTAssertThrowsError(try tree.file("../escape", bytes: 1)) { error in
            XCTAssertEqual(error as? FixtureTreeError, .invalidRelativePath)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: sibling.path))
    }

    func testRejectsAbsolutePaths() throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }

        XCTAssertThrowsError(try tree.file("/tmp/escape", bytes: 1)) { error in
            XCTAssertEqual(error as? FixtureTreeError, .invalidRelativePath)
        }
        XCTAssertThrowsError(try tree.directory("/tmp/escape")) { error in
            XCTAssertEqual(error as? FixtureTreeError, .invalidRelativePath)
        }
    }

    func testCreatesNestedFileWithExactByteCount() throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }

        let url = try tree.file("project/node_modules/big.bin", bytes: 4096)

        XCTAssertTrue(url.path.hasPrefix(tree.root.path))
        let size = try FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int
        XCTAssertEqual(size, 4096)
    }

    func testSymlinkIsCreatedAsALinkAndNotFollowed() throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }

        let target = try tree.directory("real")
        let link = try tree.symlink("link", to: target)

        let kind = try FileManager.default
            .attributesOfItem(atPath: link.path)[.type] as? FileAttributeType
        XCTAssertEqual(kind, .typeSymbolicLink)
    }

    func testCloseRemovesOnlyItsOwnRoot() throws {
        let tree = try FixtureTree()
        let root = tree.root
        _ = try tree.file("a/b.txt", bytes: 8)

        try tree.close()

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.deletingLastPathComponent().path
            )
        )
    }

    func testUsesAUniqueRootPerInstance() throws {
        let first = try FixtureTree()
        defer { try? first.close() }
        let second = try FixtureTree()
        defer { try? second.close() }

        XCTAssertNotEqual(first.root, second.root)
    }
}
