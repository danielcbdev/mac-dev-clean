#if DEBUG

    import Foundation

    import CleanupRules
    import Domain
    import Scanning

    /// Fixture wiring for previews and UI automation.
    ///
    /// This whole file is compiled out of Release. The Release build has no
    /// fixture types at all, and the launch arguments that reach them are
    /// rejected there, so a shipping binary cannot be talked into fixture mode.
    ///
    /// It is deliberately **app-local**: the application target never links the
    /// package's `TestSupport`. XCTest targets may.
    ///
    /// The fixtures are real directories in a temporary tree this type creates
    /// and owns. That matters — it means UI automation exercises the actual
    /// scanner, the actual path policy and the actual validator, rather than a
    /// stubbed pipeline that would prove nothing. Only the three things that
    /// would touch the user's machine are fakes: the Trash, Docker and storage.
    enum PreviewScenario: String {
        case firstRun = "first-run"
        case mixedResults = "mixed-results"
        case dockerVolume = "docker-volume"

        static func parse(_ arguments: [String]) -> PreviewScenario? {
            guard let index = arguments.firstIndex(of: "--scenario"),
                arguments.indices.contains(index + 1)
            else { return nil }
            return PreviewScenario(rawValue: arguments[index + 1])
        }
    }

    /// A Trash that records and moves nothing.
    actor PreviewTrash: TrashClient {
        private(set) var requested: [URL] = []

        func moveToTrash(_ url: URL) async throws -> URL {
            requested.append(url)
            return URL(fileURLWithPath: "/fixture/Trash")
                .appendingPathComponent(url.lastPathComponent)
        }

        func calls() -> [URL] { requested }
    }

    /// A Docker daemon that exists only in memory.
    actor PreviewDocker: DockerClient {
        private let stored: DockerInventory
        private(set) var removed: [UUID] = []

        init(inventory: DockerInventory) { stored = inventory }

        func inventory() async throws -> DockerInventory { stored }
        func revalidate(_ item: CleanupCandidate, evidence: CandidateEvidence) async throws {}
        func remove(_ item: CleanupCandidate) async throws { removed.append(item.id) }
    }

    /// A Docker client that is simply not there, which is the common case.
    struct UnavailablePreviewDocker: DockerClient {
        func inventory() async throws -> DockerInventory { throw PolicyError.unavailable }
        func revalidate(_ item: CleanupCandidate, evidence: CandidateEvidence) async throws {
            throw PolicyError.unavailable
        }
        func remove(_ item: CleanupCandidate) async throws { throw PolicyError.unavailable }
    }

    struct PreviewFolderPicker: FolderPicking {
        let folders: [URL]
        func chooseFolders() async -> [URL] { folders }
    }

    /// Records instead of opening Finder, so automation can assert the request
    /// without a window appearing.
    @MainActor
    final class PreviewWorkspaceOpener: WorkspaceOpening {
        private(set) var revealed: [URL] = []
        private(set) var openedTrash = 0

        func reveal(_ url: URL) { revealed.append(url) }
        func openTrash() { openedTrash += 1 }
    }

    /// Builds a real, temporary tree of developer artifacts.
    enum PreviewFixtureWorld {
        /// Creates the tree and returns its root, which stands in for `HOME`.
        static func build() throws -> URL {
            let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .resolvingSymlinksInPath()
                .appendingPathComponent("macdevclean-ui-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

            // Two Node projects.
            for (project, bytes) in [("alpha", 2_400_000), ("beta", 900_000)] {
                let directory = root.appendingPathComponent("projects/\(project)")
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true)
                try Data(#"{"name":"\#(project)"}"#.utf8)
                    .write(to: directory.appendingPathComponent("package.json"))
                try write(
                    bytes: bytes,
                    to: directory.appendingPathComponent("node_modules/payload.bin"))
            }

            // A Flutter project.
            let flutter = root.appendingPathComponent("projects/gamma")
            try FileManager.default.createDirectory(at: flutter, withIntermediateDirectories: true)
            try "name: gamma\ndependencies:\n  flutter:\n    sdk: flutter\n"
                .write(
                    to: flutter.appendingPathComponent("pubspec.yaml"), atomically: true,
                    encoding: .utf8)
            try write(bytes: 1_700_000, to: flutter.appendingPathComponent("build/payload.bin"))
            try write(bytes: 300_000, to: flutter.appendingPathComponent(".dart_tool/payload.bin"))

            // Registered global caches.
            try write(
                bytes: 3_100_000,
                to: root.appendingPathComponent(
                    "Library/Developer/Xcode/DerivedData/payload.bin"))
            try write(
                bytes: 1_200_000,
                to: root.appendingPathComponent("Library/Caches/Homebrew/payload.bin"))
            try write(
                bytes: 800_000,
                to: root.appendingPathComponent(".gradle/caches/payload.bin"))

            return root
        }

        /// A Docker inventory with one high-risk volume, for the acknowledgment
        /// flow.
        static func dockerInventory(context: String = "desktop-linux") -> DockerInventory {
            let volume = CleanupCandidate(
                id: UUID(),
                ruleID: "docker.volume",
                location: .docker(
                    context: context, builder: nil, kind: .volume, id: "fixture-orphan"),
                category: .docker,
                size: nil,
                allocatedSize: nil,
                risk: .high,
                method: .docker(.volume),
                consequenceKey: ConsequenceKey.userSelectedFile
            )
            let cache = CleanupCandidate(
                id: UUID(),
                ruleID: "docker.buildCache",
                location: .docker(
                    context: context, builder: "default", kind: .buildCache, id: "cache0001"),
                category: .docker,
                size: 4_096,
                allocatedSize: nil,
                risk: .low,
                method: .docker(.buildCache),
                consequenceKey: ConsequenceKey.rebuildSlowerNextTime
            )
            let fingerprint = "endpoint=/fixture/docker.sock|daemon=FIXTURE|builder=default"
            return DockerInventory(
                fingerprint: fingerprint,
                candidates: [volume, cache],
                evidence: [
                    volume.id: CandidateEvidence(
                        identity: nil, allowedRoot: nil, contextFingerprint: fingerprint,
                        ruleEvidenceDigest: "fixture"),
                    cache.id: CandidateEvidence(
                        identity: nil, allowedRoot: nil, contextFingerprint: fingerprint,
                        ruleEvidenceDigest: "fixture"),
                ]
            )
        }

        private static func write(bytes: Int, to url: URL) throws {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 0x41, count: bytes).write(to: url)
        }
    }

#endif
