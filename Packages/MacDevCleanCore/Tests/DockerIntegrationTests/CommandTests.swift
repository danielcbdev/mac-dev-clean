import Domain
import XCTest

@testable import DockerIntegration

final class CommandTests: XCTestCase {

    private static let containerID = String(repeating: "a", count: 64)
    private static let imageID = "sha256:" + String(repeating: "b", count: 64)
    private static let context = "desktop-linux"

    // MARK: - Exact arguments

    func testContainerRemovalCannotForceOrRemoveVolumes() throws {
        let resource = DockerResource(kind: .container, id: String(repeating: "a", count: 64))
        let args = try DockerCommandFactory.arguments(
            for: resource, context: "desktop-linux", builder: nil)
        XCTAssertEqual(
            args,
            [
                "--context", "desktop-linux", "container", "rm",
                String(repeating: "a", count: 64),
            ])
    }

    func testImageRemovalNeverPrunesParentsAndNeverForces() throws {
        let args = try DockerCommandFactory.arguments(
            for: DockerResource(kind: .image, id: Self.imageID),
            context: Self.context, builder: nil)

        XCTAssertEqual(
            args,
            ["--context", Self.context, "image", "rm", "--no-prune", Self.imageID])
        XCTAssertFalse(args.contains("--force"))
        XCTAssertFalse(args.contains("-f"))
    }

    func testVolumeRemovalNeverForces() throws {
        let args = try DockerCommandFactory.arguments(
            for: DockerResource(kind: .volume, id: "fixture-db"),
            context: Self.context, builder: nil)

        XCTAssertEqual(args, ["--context", Self.context, "volume", "rm", "fixture-db"])
        XCTAssertFalse(args.contains("--force"))
    }

    func testBuildCachePruneIsPinnedToOneRecordAndNeverUsesAll() throws {
        let args = try DockerCommandFactory.arguments(
            for: DockerResource(kind: .buildCache, id: "cache0001"),
            context: Self.context, builder: "default")

        XCTAssertEqual(
            args,
            [
                "--context", Self.context, "buildx", "prune", "--builder", "default",
                "--filter", "id=cache0001", "--filter", "inuse=false", "--force",
            ])
        XCTAssertFalse(args.contains("--all"))
        XCTAssertFalse(args.contains("-a"))
    }

    func testBuildCacheWithoutABuilderIsRefused() {
        XCTAssertThrowsError(
            try DockerCommandFactory.arguments(
                for: DockerResource(kind: .buildCache, id: "cache0001"),
                context: Self.context, builder: nil)
        ) {
            XCTAssertEqual($0 as? PolicyError, .unsupported)
        }
    }

    func testNoCommandEverContainsABroadPrune() throws {
        let resources = [
            DockerResource(kind: .container, id: Self.containerID),
            DockerResource(kind: .image, id: Self.imageID),
            DockerResource(kind: .volume, id: "fixture-db"),
            DockerResource(kind: .buildCache, id: "cache0001"),
        ]

        for resource in resources {
            let args = try DockerCommandFactory.arguments(
                for: resource, context: Self.context, builder: "default")
            XCTAssertFalse(args.contains("system"), "\(resource.kind)")
            XCTAssertFalse(args.contains("--volumes"), "\(resource.kind)")
            XCTAssertFalse(args.contains("--all"), "\(resource.kind)")
            if resource.kind != .buildCache {
                XCTAssertFalse(args.contains("prune"), "\(resource.kind)")
            }
        }
    }

    // MARK: - Identifier validation

    func testAnOptionLikeIdentifierIsRefused() {
        for id in ["--all", "-f", "--force", "-rf"] {
            for kind in DockerOperation.allCases {
                XCTAssertThrowsError(
                    try DockerCommandFactory.arguments(
                        for: DockerResource(kind: kind, id: id),
                        context: Self.context, builder: "default"),
                    "\(kind) \(id)"
                ) {
                    XCTAssertEqual($0 as? PolicyError, .unsupported)
                }
            }
        }
    }

    /// Identifiers that would matter if anything ever reinterpreted them as
    /// syntax. They are refused before they can become an argument, so they are
    /// never executed — which is what this test asserts.
    func testShellPunctuationAndControlCharactersAreRefused() {
        let hostile = [
            "fixture;echo hostile", "fixture$(whoami)", "fixture`id`", "fixture|cat",
            "fixture&&echo", "fixture\nnewline", "fixture\u{0}null", "fixture space",
            "../escape", "fixture'quote", "fixture\"quote",
        ]
        for id in hostile {
            XCTAssertThrowsError(
                try DockerCommandFactory.arguments(
                    for: DockerResource(kind: .volume, id: id),
                    context: Self.context, builder: nil),
                id
            ) {
                XCTAssertEqual($0 as? PolicyError, .unsupported, "for \(id)")
            }
        }
    }

    func testAContainerIdentifierMustBeSixtyFourLowercaseHexCharacters() {
        for id in [
            String(repeating: "a", count: 63),
            String(repeating: "a", count: 65),
            String(repeating: "A", count: 64),
            String(repeating: "g", count: 64),
            "sha256:" + String(repeating: "a", count: 64),
            "",
        ] {
            XCTAssertThrowsError(
                try DockerCommandFactory.arguments(
                    for: DockerResource(kind: .container, id: id),
                    context: Self.context, builder: nil),
                id
            )
        }
        XCTAssertNoThrow(
            try DockerCommandFactory.arguments(
                for: DockerResource(kind: .container, id: Self.containerID),
                context: Self.context, builder: nil))
    }

    func testAnImageIdentifierMustCarryItsDigestPrefix() {
        XCTAssertThrowsError(
            try DockerCommandFactory.arguments(
                for: DockerResource(kind: .image, id: String(repeating: "b", count: 64)),
                context: Self.context, builder: nil))
        XCTAssertThrowsError(
            try DockerCommandFactory.arguments(
                for: DockerResource(kind: .image, id: "fixture/web:latest"),
                context: Self.context, builder: nil),
            "a tag is not the reviewed resource")
        XCTAssertNoThrow(
            try DockerCommandFactory.arguments(
                for: DockerResource(kind: .image, id: Self.imageID),
                context: Self.context, builder: nil))
    }

    func testAHostileContextOrBuilderNameIsRefused() {
        XCTAssertThrowsError(
            try DockerCommandFactory.arguments(
                for: DockerResource(kind: .volume, id: "fixture-db"),
                context: "--host", builder: nil))
        XCTAssertThrowsError(
            try DockerCommandFactory.arguments(
                for: DockerResource(kind: .buildCache, id: "cache0001"),
                context: Self.context, builder: "-f"))
    }

    func testEveryArgumentIsASeparateTokenWithBracesKeptLiteral() throws {
        let read = DockerCommandFactory.Read.containerList(Self.context)

        XCTAssertEqual(
            read,
            [
                "--context", Self.context, "container", "ls", "--all", "--no-trunc",
                "--format", "{{json .}}",
            ])
        // The format string is one argument, not something a shell expands.
        XCTAssertEqual(read.filter { $0.contains("{{") }.count, 1)
    }
}
