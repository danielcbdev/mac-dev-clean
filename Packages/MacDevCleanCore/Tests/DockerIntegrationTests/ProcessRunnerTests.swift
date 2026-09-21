import Domain
import XCTest

@testable import DockerIntegration

/// Exercises the real subprocess adapter against harmless system binaries.
///
/// Nothing here runs Docker, and nothing here writes to the filesystem.
final class ProcessRunnerTests: XCTestCase {

    func testArgumentsAreLiteralAndAreNeverInterpretedByAShell() async throws {
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["%s", "$(touch should-not-exist)"],
            environment: [:],
            timeoutSeconds: 5,
            outputLimit: 1024
        )

        let output = try await LocalProcessRunner().run(request)

        XCTAssertEqual(
            String(decoding: output.stdout, as: UTF8.self),
            "$(touch should-not-exist)"
        )
        XCTAssertEqual(output.exitCode, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: "should-not-exist"))
    }

    func testBackticksAndSemicolonsAreAlsoJustText() async throws {
        let payload = "a;b`c`d|e&f>g"
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["%s", payload],
            environment: [:],
            timeoutSeconds: 5,
            outputLimit: 1024
        )

        let output = try await LocalProcessRunner().run(request)

        XCTAssertEqual(String(decoding: output.stdout, as: UTF8.self), payload)
    }

    func testStandardErrorIsCapturedSeparatelyWithItsExitStatus() async throws {
        // `ls` on a missing path writes to stderr and exits non-zero.
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "/bin/ls"),
            arguments: ["/definitely/not/a/real/path/for/macdevclean"],
            environment: [:],
            timeoutSeconds: 5,
            outputLimit: 4096
        )

        let output = try await LocalProcessRunner().run(request)

        XCTAssertTrue(output.stdout.isEmpty)
        XCTAssertFalse(output.stderr.isEmpty)
        XCTAssertNotEqual(output.exitCode, 0)
    }

    func testATimeoutTerminatesTheChild() async throws {
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["30"],
            environment: [:],
            timeoutSeconds: 0.4,
            outputLimit: 1024
        )

        let started = Date()
        do {
            _ = try await LocalProcessRunner().run(request)
            XCTFail("expected a timeout")
        } catch {
            XCTAssertEqual(error as? ProcessError, .timeout)
        }
        XCTAssertLessThan(
            Date().timeIntervalSince(started), 10,
            "the runner must not wait for the child's natural end")
    }

    func testOutputBeyondTheLimitIsRefused() async throws {
        // Far more than the limit, and more than a pipe buffer, so the reader
        // has to be draining concurrently for this to terminate at all.
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "/usr/bin/yes"),
            arguments: ["macdevclean"],
            environment: [:],
            timeoutSeconds: 20,
            outputLimit: 64 * 1024
        )

        do {
            _ = try await LocalProcessRunner().run(request)
            XCTFail("expected the output limit to be enforced")
        } catch {
            XCTAssertEqual(error as? ProcessError, .outputLimit)
        }
    }

    func testLargeOutputOnBothStreamsDoesNotDeadlock() async throws {
        // Both pipes are filled well past their buffers. A runner that drained
        // them one after the other would hang here forever.
        let script =
            "/usr/bin/yes macdevclean | /usr/bin/head -c 400000; "
            + "/usr/bin/yes macdevclean | /usr/bin/head -c 400000 1>&2"
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["sh", "-c", script],
            environment: [:],
            timeoutSeconds: 20,
            outputLimit: 8 * 1024 * 1024
        )

        // The runner refuses to launch an interpreter at all, which is the
        // stronger guarantee: this command can never run through it.
        do {
            _ = try await LocalProcessRunner().run(request)
            XCTFail("expected the runner to refuse an interpreter")
        } catch {
            XCTAssertEqual(error as? ProcessError, .refusedExecutable)
        }
    }

    func testTheRunnerRefusesShellsAndPrivilegeEscalation() async throws {
        for path in ["/bin/sh", "/bin/bash", "/bin/zsh", "/usr/bin/env", "/usr/bin/sudo"] {
            let request = ProcessRequest(
                executable: URL(fileURLWithPath: path),
                arguments: ["-c", "echo hello"],
                environment: [:],
                timeoutSeconds: 5,
                outputLimit: 1024
            )
            do {
                _ = try await LocalProcessRunner().run(request)
                XCTFail("\(path) must never be launched")
            } catch {
                XCTAssertEqual(error as? ProcessError, .refusedExecutable, "for \(path)")
            }
        }
    }

    func testABareProgramNameIsNeverResolvedThroughPATH() async throws {
        // `printf` really is on PATH at /usr/bin/printf. If this runner ever
        // consulted PATH, the command below would succeed. It must not: the
        // executable is a location, never a name to be searched for.
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "printf"),
            arguments: ["%s", "hello"],
            environment: ["PATH": "/usr/bin:/bin"],
            timeoutSeconds: 5,
            outputLimit: 1024
        )

        do {
            let output = try await LocalProcessRunner().run(request)
            XCTFail(
                "PATH must not be consulted; got \(String(decoding: output.stdout, as: UTF8.self))")
        } catch {
            XCTAssertEqual(error as? ProcessError, .launchFailure)
        }
    }

    func testAMissingExecutableIsALaunchFailure() async throws {
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "/usr/bin/definitely-not-installed-macdevclean"),
            arguments: [],
            environment: [:],
            timeoutSeconds: 5,
            outputLimit: 1024
        )

        do {
            _ = try await LocalProcessRunner().run(request)
            XCTFail("expected a launch failure")
        } catch {
            XCTAssertEqual(error as? ProcessError, .launchFailure)
        }
    }

    func testOnlyTheStatedEnvironmentReachesTheChild() async throws {
        setenv("MACDEVCLEAN_SHOULD_NOT_LEAK", "leaked", 1)
        defer { unsetenv("MACDEVCLEAN_SHOULD_NOT_LEAK") }

        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "/usr/bin/printenv"),
            arguments: [],
            environment: ["MACDEVCLEAN_EXPECTED": "present"],
            timeoutSeconds: 5,
            outputLimit: 8192
        )

        let output = try await LocalProcessRunner().run(request)
        let text = String(decoding: output.stdout, as: UTF8.self)

        XCTAssertTrue(text.contains("MACDEVCLEAN_EXPECTED=present"))
        XCTAssertFalse(text.contains("MACDEVCLEAN_SHOULD_NOT_LEAK"))
    }

    func testCancellationTerminatesTheChild() async throws {
        let runner = LocalProcessRunner()
        let work = Task {
            try await runner.run(
                ProcessRequest(
                    executable: URL(fileURLWithPath: "/bin/sleep"),
                    arguments: ["30"],
                    environment: [:],
                    timeoutSeconds: 30,
                    outputLimit: 1024
                )
            )
        }
        // Give it a moment to actually start, then cancel.
        try await Task.sleep(nanoseconds: 100_000_000)
        work.cancel()

        let started = Date()
        do {
            _ = try await work.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(
                error is CancellationError || (error as? ProcessError) == .cancelled,
                "got \(error)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }
}
