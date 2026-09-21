import Domain
import TestSupport
import XCTest

@testable import DockerIntegration

final class DiscoveryTests: XCTestCase {

    private static let executable = URL(
        fileURLWithPath: "/Applications/Docker.app/Contents/Resources/bin/docker")
    private static let context = "desktop-linux"
    private static let socket = "unix:///Users/fixture/.docker/run/docker.sock"

    // MARK: - Endpoints

    func testRemoteEndpointIsRejected() throws {
        XCTAssertThrowsError(try DockerDiscovery.validateEndpoint("ssh://server")) {
            XCTAssertEqual($0 as? PolicyError, .outsideScope)
        }
    }

    func testEveryNonLocalEndpointSchemeIsRejected() throws {
        for endpoint in [
            "ssh://user@server", "tcp://10.0.0.1:2375", "tcp://127.0.0.1:2375",
            "https://example.invalid", "http://localhost:2375", "npipe:////./pipe/docker_engine",
            "fd://", "", "   ", "unix://",
        ] {
            XCTAssertThrowsError(try DockerDiscovery.validateEndpoint(endpoint), endpoint) {
                XCTAssertEqual($0 as? PolicyError, .outsideScope, "for \(endpoint)")
            }
        }
    }

    func testALocalUnixSocketIsAccepted() throws {
        let url = try DockerDiscovery.validateEndpoint(Self.socket)

        XCTAssertEqual(url.scheme, "unix")
        XCTAssertEqual(url.path, "/Users/fixture/.docker/run/docker.sock")
    }

    // MARK: - Executable location

    func testOnlyKnownInstallationLocationsAreConsidered() {
        XCTAssertEqual(
            DockerDiscovery.executableCandidates,
            [
                "/Applications/Docker.app/Contents/Resources/bin/docker",
                "/usr/local/bin/docker",
                "/opt/homebrew/bin/docker",
            ]
        )
        // Nothing writable by a project, and nothing found by asking a shell.
        for candidate in DockerDiscovery.executableCandidates {
            XCTAssertTrue(candidate.hasPrefix("/"))
            XCTAssertFalse(candidate.contains(".."))
        }
    }

    func testAnExplicitChoiceIsUsedWhenItIsExecutable() throws {
        let located = try DockerDiscovery.locateExecutable(
            explicit: URL(fileURLWithPath: "/bin/ls"))

        XCTAssertEqual(located.path, "/bin/ls")
    }

    func testAMissingExecutableIsUnavailable() {
        XCTAssertThrowsError(
            try DockerDiscovery.locateExecutable(
                explicit: URL(fileURLWithPath: "/usr/bin/not-installed-macdevclean"))
        ) {
            XCTAssertEqual($0 as? PolicyError, .unavailable)
        }
    }

    // MARK: - Discovery

    func testALocalDesktopContextIsAccepted() async throws {
        let runner = RecordingProcessRunner()
        await Self.scriptHealthyDaemon(runner)

        let capability = try await DockerDiscovery(runner: runner)
            .discover(executable: Self.executable, context: Self.context, builder: nil)

        XCTAssertEqual(capability.contextName, Self.context)
        XCTAssertEqual(capability.endpoint.path, "/Users/fixture/.docker/run/docker.sock")
        XCTAssertEqual(capability.daemonID, "DAEMON-ID-0001")
        XCTAssertFalse(capability.buildCacheSupported, "no builder was selected")
    }

    func testARemoteContextIsRejectedBeforeAnyDaemonCall() async throws {
        let runner = RecordingProcessRunner()
        await runner.respond(
            to: ["context", "inspect", Self.context],
            stdout: Self.contextJSON(host: "tcp://10.0.0.5:2376")
        )

        do {
            _ = try await DockerDiscovery(runner: runner)
                .discover(executable: Self.executable, context: Self.context, builder: nil)
            XCTFail("a remote context must be refused")
        } catch {
            XCTAssertEqual(error as? PolicyError, .outsideScope)
        }

        let calls = await runner.argumentLists()
        XCTAssertEqual(
            calls, [["context", "inspect", Self.context]],
            "nothing may be asked of a daemon that was never accepted")
    }

    func testAnOfflineDaemonIsUnavailable() async throws {
        let runner = RecordingProcessRunner()
        await runner.respond(
            to: ["context", "inspect", Self.context], stdout: Self.contextJSON(host: Self.socket))
        await runner.respond(
            to: ["--context", Self.context, "version", "--format", "{{json .}}"],
            stderr: "Cannot connect to the Docker daemon.",
            exitCode: 1
        )

        do {
            _ = try await DockerDiscovery(runner: runner)
                .discover(executable: Self.executable, context: Self.context, builder: nil)
            XCTFail("an offline daemon must be reported unavailable")
        } catch {
            XCTAssertEqual(error as? PolicyError, .unavailable)
        }
    }

    func testEndpointOverridesInTheUsersSessionAreNotInherited() async throws {
        let runner = RecordingProcessRunner()
        await Self.scriptHealthyDaemon(runner)

        _ = try await DockerDiscovery(runner: runner)
            .discover(executable: Self.executable, context: Self.context, builder: nil)

        let calls = await runner.calls()
        for call in calls {
            XCTAssertNil(call.environment["DOCKER_HOST"])
            XCTAssertNil(call.environment["DOCKER_CONTEXT"])
            XCTAssertNil(call.environment["BUILDX_BUILDER"])
            XCTAssertNil(call.environment["DOCKER_CONFIG"])
        }
    }

    // MARK: - Builders

    func testALocalBuilderEnablesBuildCacheCleanup() async throws {
        let runner = RecordingProcessRunner()
        await Self.scriptHealthyDaemon(runner)
        await Self.scriptBuilder(runner, endpoints: ["unix:///var/run/docker.sock"])
        await runner.respond(
            to: [
                "--context", Self.context, "buildx", "du", "--builder", "default",
                "--format=json",
            ],
            stdout: #"{"ID":"abc","Size":"1","Reclaimable":true,"Shared":false,"Mutable":false}"#
        )

        let capability = try await DockerDiscovery(runner: runner)
            .discover(executable: Self.executable, context: Self.context, builder: "default")

        XCTAssertTrue(capability.buildCacheSupported)
        XCTAssertEqual(capability.builderName, "default")
    }

    func testABuilderOnARemoteNodeDisablesOnlyBuildCacheCleanup() async throws {
        let runner = RecordingProcessRunner()
        await Self.scriptHealthyDaemon(runner)
        await Self.scriptBuilder(runner, endpoints: ["tcp://builder.internal:1234"])

        let capability = try await DockerDiscovery(runner: runner)
            .discover(executable: Self.executable, context: Self.context, builder: "remote")

        // The rest of the integration still works; only the cache feature is off.
        XCTAssertFalse(capability.buildCacheSupported)
        XCTAssertEqual(capability.daemonID, "DAEMON-ID-0001")
    }

    func testAnUnknownBuildxCapabilityDisablesOnlyBuildCacheCleanup() async throws {
        let runner = RecordingProcessRunner()
        await Self.scriptHealthyDaemon(runner)
        await Self.scriptBuilder(runner, endpoints: ["unix:///var/run/docker.sock"])
        await runner.respond(
            to: [
                "--context", Self.context, "buildx", "du", "--builder", "default",
                "--format=json",
            ],
            stderr: "unknown flag: --format",
            exitCode: 125
        )

        let capability = try await DockerDiscovery(runner: runner)
            .discover(executable: Self.executable, context: Self.context, builder: "default")

        XCTAssertFalse(capability.buildCacheSupported)
    }

    // MARK: - Fingerprint

    func testTheFingerprintBindsEndpointAndDaemonRatherThanTheContextName() async throws {
        let runner = RecordingProcessRunner()
        await Self.scriptHealthyDaemon(runner)
        let original = try await DockerDiscovery(runner: runner)
            .discover(executable: Self.executable, context: Self.context, builder: nil)

        // The name stayed the same; the daemon behind it did not.
        let moved = RecordingProcessRunner()
        await Self.scriptHealthyDaemon(moved, daemonID: "DAEMON-ID-0002")
        let after = try await DockerDiscovery(runner: moved)
            .discover(executable: Self.executable, context: Self.context, builder: nil)

        XCTAssertNotEqual(original.fingerprint, after.fingerprint)
        XCTAssertTrue(original.fingerprint.contains("DAEMON-ID-0001"))
        XCTAssertTrue(original.fingerprint.contains("docker.sock"))
    }

    func testTheSameDaemonProducesTheSameFingerprint() async throws {
        let first = RecordingProcessRunner()
        await Self.scriptHealthyDaemon(first)
        let second = RecordingProcessRunner()
        await Self.scriptHealthyDaemon(second)

        let a = try await DockerDiscovery(runner: first)
            .discover(executable: Self.executable, context: Self.context, builder: nil)
        let b = try await DockerDiscovery(runner: second)
            .discover(executable: Self.executable, context: Self.context, builder: nil)

        XCTAssertEqual(a.fingerprint, b.fingerprint)
    }

    // MARK: - Script helpers

    private static func contextJSON(host: String) -> String {
        """
        [{"Name":"desktop-linux","Metadata":{},"Endpoints":{"docker":{"Host":"\(host)",\
        "SkipTLSVerify":false}}}]
        """
    }

    private static func scriptHealthyDaemon(
        _ runner: RecordingProcessRunner,
        daemonID: String = "DAEMON-ID-0001"
    ) async {
        await runner.respond(
            to: ["context", "inspect", context], stdout: contextJSON(host: socket))
        await runner.respond(
            to: ["--context", context, "version", "--format", "{{json .}}"],
            stdout: #"{"Client":{"Version":"27.0.0"},"Server":{"Version":"27.0.0"}}"#
        )
        await runner.respond(
            to: ["--context", context, "info", "--format", "{{json .}}"],
            stdout: #"{"ID":"\#(daemonID)","Name":"docker-desktop","ServerVersion":"27.0.0"}"#
        )
    }

    private static func scriptBuilder(
        _ runner: RecordingProcessRunner,
        endpoints: [String]
    ) async {
        let name = endpoints.first?.hasPrefix("unix://") == true ? "default" : "remote"
        let nodes = endpoints.enumerated()
            .map { "Name:      node\($0.offset)\nEndpoint:  \($0.element)\nStatus:    running" }
            .joined(separator: "\n")
        await runner.respond(
            to: ["--context", context, "buildx", "inspect", name],
            stdout: "Name:   \(name)\nDriver: docker-container\n\nNodes:\n\(nodes)\n"
        )
    }
}
