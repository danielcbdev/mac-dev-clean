import Domain
import TestSupport
import XCTest

@testable import DockerIntegration

/// Exercises the whole read / classify / revalidate / remove pipeline against
/// scripted daemon output. No test here contacts a Docker daemon.
final class ClientTests: XCTestCase {

    private static let executable = URL(fileURLWithPath: "/usr/local/bin/docker")
    private static let context = "desktop-linux"
    private static let socket = "unix:///Users/fixture/.docker/run/docker.sock"

    private static let runningID = String(repeating: "1", count: 64)
    private static let stoppedID = String(repeating: "2", count: 64)
    private static let usedImage = "sha256:" + String(repeating: "a", count: 64)
    private static let staleImage = "sha256:" + String(repeating: "d", count: 64)

    // MARK: - Classification

    func testOnlyStoppedContainersAreOfferedAndTheyAreHighRisk() async throws {
        let runner = await Self.scriptWorld()
        let inventory = try await Self.client(runner).inventory()

        let containers = inventory.candidates.filter { $0.method == .docker(.container) }
        XCTAssertEqual(containers.count, 1)
        let stopped = try XCTUnwrap(containers.first)
        XCTAssertEqual(
            stopped.risk, .high,
            "a stopped container's writable layer can hold data that exists nowhere else")
        guard case .docker(_, _, _, let id) = stopped.location else {
            return XCTFail("expected a Docker location")
        }
        XCTAssertEqual(id, Self.stoppedID)
        XCTAssertEqual(stopped.size, 12_000_000, "size comes from the daemon, not a guess")
    }

    func testAnImageHeldByAStoppedContainerIsNotOffered() async throws {
        let runner = await Self.scriptWorld()
        let inventory = try await Self.client(runner).inventory()

        let imageIDs = inventory.candidates.compactMap { candidate -> String? in
            guard case .docker(_, _, let kind, let id) = candidate.location, kind == .image else {
                return nil
            }
            return id
        }

        XCTAssertFalse(
            imageIDs.contains(Self.usedImage),
            "eligibility is decided against every container, not only running ones")
        XCTAssertTrue(imageIDs.contains(Self.staleImage))
    }

    func testAVolumeHeldByAStoppedContainerIsNotOffered() async throws {
        let runner = await Self.scriptWorld()
        let inventory = try await Self.client(runner).inventory()

        let volumeNames = inventory.candidates.compactMap { candidate -> String? in
            guard case .docker(_, _, let kind, let id) = candidate.location, kind == .volume else {
                return nil
            }
            return id
        }

        XCTAssertFalse(volumeNames.contains("fixture-db"))
        XCTAssertTrue(volumeNames.contains("fixture-orphan"))
        let orphan = try XCTUnwrap(
            inventory.candidates.first {
                if case .docker(_, _, let kind, let id) = $0.location {
                    return kind == .volume && id == "fixture-orphan"
                }
                return false
            })
        XCTAssertEqual(orphan.risk, .high)
    }

    func testAPluginDriverVolumeIsNeverOffered() async throws {
        let runner = await Self.scriptWorld()
        let inventory = try await Self.client(runner).inventory()

        let names = inventory.candidates.compactMap { candidate -> String? in
            guard case .docker(_, _, let kind, let id) = candidate.location, kind == .volume else {
                return nil
            }
            return id
        }
        XCTAssertFalse(names.contains("fixture-remote"))
    }

    func testAVolumeWithNoDaemonReportedSizeStaysUnknown() async throws {
        let runner = await Self.scriptWorld()
        let inventory = try await Self.client(runner).inventory()

        let orphan = try XCTUnwrap(
            inventory.candidates.first {
                if case .docker(_, _, let kind, let id) = $0.location {
                    return kind == .volume && id == "fixture-orphan"
                }
                return false
            })
        XCTAssertNil(orphan.size, "no volume is mounted to work a size out")
    }

    func testTheInventoryCarriesTheDaemonFingerprintOnEveryCandidate() async throws {
        let runner = await Self.scriptWorld()
        let inventory = try await Self.client(runner).inventory()

        XCTAssertFalse(inventory.candidates.isEmpty)
        for candidate in inventory.candidates {
            let evidence = try XCTUnwrap(inventory.evidence[candidate.id])
            XCTAssertEqual(evidence.contextFingerprint, inventory.fingerprint)
            XCTAssertTrue(evidence.ruleEvidenceDigest.contains(inventory.fingerprint))
        }
    }

    // MARK: - Revalidation

    func testADaemonThatChangedBehindTheContextNameIsRejected() async throws {
        let runner = await Self.scriptWorld()
        let client = Self.client(runner)
        let inventory = try await client.inventory()
        let candidate = try XCTUnwrap(inventory.candidates.first)
        let stale = CandidateEvidence(
            identity: nil,
            allowedRoot: nil,
            contextFingerprint: "endpoint=/somewhere/else|daemon=OTHER|builder=-",
            ruleEvidenceDigest: "whatever"
        )

        do {
            try await client.revalidate(candidate, evidence: stale)
            XCTFail("a different daemon behind the same name must be refused")
        } catch {
            XCTAssertEqual(error as? PolicyError, .changed)
        }
    }

    func testAContainerThatStartedAgainIsRejected() async throws {
        let runner = await Self.scriptWorld()
        let client = Self.client(runner)
        let inventory = try await client.inventory()
        let candidate = try XCTUnwrap(
            inventory.candidates.first { $0.method == .docker(.container) })
        let evidence = try XCTUnwrap(inventory.evidence[candidate.id])

        // It was restarted between the review and the confirmation.
        await runner.respond(
            to: ["--context", Self.context, "container", "inspect", "--size", Self.stoppedID],
            stdout: Self.containerDetail(
                id: Self.stoppedID, image: Self.usedImage, running: true, mounts: ["fixture-db"])
        )

        do {
            try await client.revalidate(candidate, evidence: evidence)
            XCTFail("a running container must never be removed")
        } catch {
            XCTAssertEqual(error as? PolicyError, .changed)
        }
    }

    func testAVolumeAttachedSinceTheReviewIsRejected() async throws {
        let runner = await Self.scriptWorld()
        let client = Self.client(runner)
        let inventory = try await client.inventory()
        let candidate = try XCTUnwrap(
            inventory.candidates.first {
                if case .docker(_, _, let kind, let id) = $0.location {
                    return kind == .volume && id == "fixture-orphan"
                }
                return false
            })
        let evidence = try XCTUnwrap(inventory.evidence[candidate.id])

        // A stopped container now references it. Stopped still counts.
        await runner.respond(
            to: ["--context", Self.context, "container", "inspect", "--size", Self.stoppedID],
            stdout: Self.containerDetail(
                id: Self.stoppedID, image: Self.usedImage, running: false,
                mounts: ["fixture-db", "fixture-orphan"])
        )

        do {
            try await client.revalidate(candidate, evidence: evidence)
            XCTFail("a newly attached volume must be refused")
        } catch {
            XCTAssertEqual(error as? PolicyError, .changed)
        }
    }

    func testAnImageAnsweringToSeveralNamesIsRefused() async throws {
        let runner = await Self.scriptWorld()
        let client = Self.client(runner)
        let inventory = try await client.inventory()
        let candidate = try XCTUnwrap(
            inventory.candidates.first { $0.method == .docker(.image) })
        let evidence = try XCTUnwrap(inventory.evidence[candidate.id])

        await runner.respond(
            to: ["--context", Self.context, "image", "inspect", Self.staleImage],
            stdout: """
                [{"Id":"\(Self.staleImage)","Size":88000000,\
                "RepoTags":["fixture/a:1","fixture/b:2"],"RepoDigests":[]}]
                """
        )

        do {
            try await client.revalidate(candidate, evidence: evidence)
            XCTFail("a non-forcing removal cannot address a multi-tag image cleanly")
        } catch {
            XCTAssertEqual(error as? PolicyError, .unsupported)
        }
    }

    // MARK: - Removal

    func testRemovalIssuesExactlyTheReviewedCommand() async throws {
        let runner = await Self.scriptWorld()
        let client = Self.client(runner)
        let inventory = try await client.inventory()
        let candidate = try XCTUnwrap(
            inventory.candidates.first { $0.method == .docker(.container) })
        let removal = ["--context", Self.context, "container", "rm", Self.stoppedID]
        await runner.respond(to: removal, stdout: Self.stoppedID)

        try await client.remove(candidate)

        let issued = await runner.argumentLists()
        XCTAssertEqual(
            issued.filter { $0.contains("rm") || $0.contains("prune") }, [removal],
            "exactly one write, exactly as reviewed")
    }

    func testTwoSelectedResourcesProduceExactlyTwoWrites() async throws {
        let runner = await Self.scriptWorld()
        let client = Self.client(runner)
        let inventory = try await client.inventory()
        let container = try XCTUnwrap(
            inventory.candidates.first { $0.method == .docker(.container) })
        let volume = try XCTUnwrap(inventory.candidates.first { $0.method == .docker(.volume) })
        await runner.respond(
            to: ["--context", Self.context, "container", "rm", Self.stoppedID], stdout: "")
        await runner.respond(
            to: ["--context", Self.context, "volume", "rm", "fixture-orphan"], stdout: "")

        try await client.remove(container)
        try await client.remove(volume)

        let writes = await runner.argumentLists().filter {
            $0.contains("rm") || $0.contains("prune")
        }
        XCTAssertEqual(writes.count, 2)
    }

    func testATimeoutThatTurnsOutToHaveSucceededIsNotRetried() async throws {
        let runner = await Self.scriptWorld()
        let client = Self.client(runner)
        let inventory = try await client.inventory()
        let candidate = try XCTUnwrap(
            inventory.candidates.first { $0.method == .docker(.container) })
        let removal = ["--context", Self.context, "container", "rm", Self.stoppedID]
        await runner.fail(removal, with: .timeout)
        // Asking afterwards: it is gone.
        await runner.respond(
            to: ["--context", Self.context, "container", "inspect", "--size", Self.stoppedID],
            stderr: "Error: No such container", exitCode: 1
        )

        try await client.remove(candidate)

        let writes = await runner.argumentLists().filter { $0 == removal }
        XCTAssertEqual(writes.count, 1, "a write is never repeated after a timeout")
    }

    func testATimeoutWhereTheResourceSurvivedIsAFailure() async throws {
        let runner = await Self.scriptWorld()
        let client = Self.client(runner)
        let inventory = try await client.inventory()
        let candidate = try XCTUnwrap(
            inventory.candidates.first { $0.method == .docker(.container) })
        await runner.fail(
            ["--context", Self.context, "container", "rm", Self.stoppedID], with: .timeout)

        do {
            try await client.remove(candidate)
            XCTFail("the resource is still there; that is not a success")
        } catch {
            XCTAssertEqual(error as? PolicyError, .unavailable)
        }
    }

    func testATimeoutNobodyCanSettleIsReportedAsIndeterminate() async throws {
        let runner = await Self.scriptWorld()
        let client = Self.client(runner)
        let inventory = try await client.inventory()
        let candidate = try XCTUnwrap(
            inventory.candidates.first { $0.method == .docker(.container) })
        await runner.fail(
            ["--context", Self.context, "container", "rm", Self.stoppedID], with: .timeout)
        // The follow-up inspection cannot answer either.
        await runner.fail(
            ["--context", Self.context, "container", "inspect", "--size", Self.stoppedID],
            with: .timeout)

        do {
            try await client.remove(candidate)
            XCTFail("an unsettled write must not be reported as done")
        } catch {
            XCTAssertEqual(error as? DockerOutcomeError, .indeterminate)
        }
    }

    func testAResourceInUseAtWriteTimeIsReportedAsChanged() async throws {
        let runner = await Self.scriptWorld()
        let client = Self.client(runner)
        let inventory = try await client.inventory()
        let candidate = try XCTUnwrap(inventory.candidates.first { $0.method == .docker(.volume) })
        await runner.respond(
            to: ["--context", Self.context, "volume", "rm", "fixture-orphan"],
            stderr: "Error response from daemon: remove fixture-orphan: volume is in use",
            exitCode: 1
        )

        do {
            try await client.remove(candidate)
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(error as? PolicyError, .changed)
        }
    }

    // MARK: - Scripting a daemon

    private static func client(_ runner: RecordingProcessRunner) -> LocalDockerClient {
        LocalDockerClient(
            discovery: DockerDiscovery(runner: runner),
            runner: runner,
            clock: FixedClock(),
            selection: DockerSelection(executable: executable, contextName: context)
        )
    }

    private static func containerDetail(
        id: String, image: String, running: Bool, mounts: [String]
    ) -> String {
        let mountJSON = mounts.map { #"{"Name":"\#($0)","Type":"volume"}"# }
            .joined(separator: ",")
        return """
            [{"Id":"\(id)","Image":"\(image)","State":{"Running":\(running)},\
            "Mounts":[\(mountJSON)],"SizeRootFs":12000000}]
            """
    }

    private static func scriptWorld() async -> RecordingProcessRunner {
        let runner = RecordingProcessRunner()

        await runner.respond(
            to: ["context", "inspect", context],
            stdout: """
                [{"Name":"desktop-linux","Metadata":{},"Endpoints":{"docker":\
                {"Host":"\(socket)","SkipTLSVerify":false}}}]
                """
        )
        await runner.respond(
            to: ["--context", context, "version", "--format", "{{json .}}"],
            stdout: #"{"Client":{"Version":"27.0.0"},"Server":{"Version":"27.0.0"}}"#)
        await runner.respond(
            to: ["--context", context, "info", "--format", "{{json .}}"],
            stdout: #"{"ID":"DAEMON-ID-0001","Name":"docker-desktop"}"#)

        await runner.respond(
            to: [
                "--context", context, "container", "ls", "--all", "--no-trunc",
                "--format", "{{json .}}",
            ],
            stdout: """
                {"ID":"\(runningID)","Image":"\(usedImage)","Names":"fixture-web",\
                "State":"running","Mounts":""}
                {"ID":"\(stoppedID)","Image":"\(usedImage)","Names":"fixture-db",\
                "State":"exited","Mounts":"fixture-db"}
                """
        )
        await runner.respond(
            to: ["--context", context, "container", "inspect", "--size", runningID],
            stdout: containerDetail(
                id: runningID, image: usedImage, running: true, mounts: []))
        await runner.respond(
            to: ["--context", context, "container", "inspect", "--size", stoppedID],
            stdout: containerDetail(
                id: stoppedID, image: usedImage, running: false, mounts: ["fixture-db"]))

        await runner.respond(
            to: ["--context", context, "image", "ls", "--no-trunc", "--format", "{{json .}}"],
            stdout: """
                {"ID":"\(usedImage)","Repository":"fixture/web","Tag":"latest"}
                {"ID":"\(staleImage)","Repository":"<none>","Tag":"<none>"}
                """
        )
        await runner.respond(
            to: ["--context", context, "image", "inspect", staleImage],
            stdout: """
                [{"Id":"\(staleImage)","Size":88000000,"RepoTags":[],"RepoDigests":[]}]
                """
        )

        await runner.respond(
            to: ["--context", context, "volume", "ls", "--format", "{{json .}}"],
            stdout: """
                {"Name":"fixture-db","Driver":"local","Scope":"local"}
                {"Name":"fixture-orphan","Driver":"local","Scope":"local"}
                {"Name":"fixture-remote","Driver":"some-cloud-plugin","Scope":"global"}
                """
        )
        await runner.respond(
            to: ["--context", context, "volume", "inspect", "fixture-orphan"],
            stdout: #"[{"Name":"fixture-orphan","Driver":"local"}]"#)

        return runner
    }
}
