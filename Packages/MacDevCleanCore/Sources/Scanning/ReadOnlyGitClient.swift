import Domain
import Foundation

/// Asks Git two questions, read-only, without a shell.
///
/// A directory named `dist` or `build` might be generated output or might be
/// authored content somebody committed. Guessing from the name is how a cleanup
/// tool destroys work, so the catalog asks the repository instead.
///
/// The safety properties, all deliberate:
///
/// - a fixed absolute executable, never a `PATH` lookup;
/// - separate literal arguments, never an interpolated command string;
/// - `GIT_LITERAL_PATHSPECS=1` for `ls-files`, so a path containing `*` or `:`
///   is a path and not a pattern or a magic pathspec. `check-ignore` rejects
///   literal pathspec magic outright (`fatal: pathspec magic not supported by
///   this command: 'literal'`), so it runs without that variable and its answer
///   is verified instead: the pathname Git echoes back must be byte-identical
///   to the one that was sent, otherwise the result is discarded;
/// - `GIT_OPTIONAL_LOCKS=0` and `--no-optional-locks`, so reading never writes
///   to the user's repository;
/// - system and global configuration disabled, so no user-controlled setting
///   can point Git at an external filter or program;
/// - bounded output and a hard timeout, and any doubt fails closed.
public struct ReadOnlyGitClient: GitStatusChecking {
    public enum Failure: Error, Equatable {
        case gitUnavailable
        case repositoryMismatch
        case timedOut
        case outputTooLarge
        case unexpectedExit(Int32)
    }

    private static let executable = URL(fileURLWithPath: "/usr/bin/git")
    private static let maximumOutputBytes = 1 << 20
    private let timeout: TimeInterval
    private let queue: DispatchQueue

    public init(timeout: TimeInterval = 10) {
        self.timeout = timeout
        queue = DispatchQueue(
            label: "dev.macdevclean.git",
            qos: .utility,
            autoreleaseFrequency: .workItem
        )
    }

    public func containsTrackedFiles(at url: URL, repository: URL) async throws -> Bool {
        let relative = try Self.relativePath(of: url, in: repository)
        let result = try await run(
            ["--no-optional-locks", "-C", repository.path, "ls-files", "-z", "--", relative],
            literalPathspecs: true
        )
        guard result.status == 0 else { throw Failure.unexpectedExit(result.status) }
        return !Self.nulSeparated(result.output).isEmpty
    }

    public func isIgnored(_ url: URL, repository: URL) async throws -> Bool {
        let relative = try Self.relativePath(of: url, in: repository)
        // `check-ignore -z` is only accepted together with `--stdin`; Git exits
        // 128 otherwise. Feeding the path through stdin is also the stricter
        // option, because the path never appears on the command line at all.
        let result = try await run(
            ["--no-optional-locks", "-C", repository.path, "check-ignore", "-z", "--stdin"],
            input: Data((relative + "\0").utf8),
            literalPathspecs: false
        )
        switch result.status {
        // 0: at least one path is ignored. 1: none is. Anything else is a real
        // error and must not be read as "not ignored".
        case 0:
            // Without literal pathspecs Git could in principle answer about a
            // different path than the one asked about. Accept the answer only
            // when it names exactly the path that was sent.
            return Self.nulSeparated(result.output) == [relative]
        case 1:
            return false
        default:
            throw Failure.unexpectedExit(result.status)
        }
    }

    // MARK: - Process

    private struct Outcome: Sendable {
        let status: Int32
        let output: Data
    }

    private func run(
        _ arguments: [String],
        input: Data? = nil,
        literalPathspecs: Bool
    ) async throws -> Outcome {
        try Task.checkCancellation()
        let timeout = timeout
        let outcome = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Outcome, Error>) in
            queue.async {
                continuation.resume(
                    with: Result {
                        try Self.execute(
                            arguments,
                            input: input,
                            literalPathspecs: literalPathspecs,
                            timeout: timeout
                        )
                    }
                )
            }
        }
        try Task.checkCancellation()
        return outcome
    }

    private static func execute(
        _ arguments: [String],
        input: Data?,
        literalPathspecs: Bool,
        timeout: TimeInterval
    ) throws -> Outcome {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw Failure.gitUnavailable
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        // A deliberately minimal environment. Nothing is inherited, so no
        // user-controlled variable can redirect Git or load an external filter.
        var environment = [
            "GIT_OPTIONAL_LOCKS": "0",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_TERMINAL_PROMPT": "0",
            "LC_ALL": "C",
        ]
        if literalPathspecs { environment["GIT_LITERAL_PATHSPECS"] = "1" }
        process.environment = environment

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        let inputPipe = input.map { _ in Pipe() }
        process.standardInput = inputPipe ?? FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw Failure.gitUnavailable
        }

        // The payload is one short path, far below the pipe buffer, so writing
        // it in full before reading cannot deadlock.
        if let input, let inputPipe {
            try? inputPipe.fileHandleForWriting.write(contentsOf: input)
            try? inputPipe.fileHandleForWriting.close()
        }

        var timedOut = false
        let deadline = DispatchWorkItem {
            timedOut = true
            process.terminate()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + timeout,
            execute: deadline
        )

        var collected = Data()
        while true {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            collected.append(chunk)
            if collected.count > maximumOutputBytes {
                process.terminate()
                process.waitUntilExit()
                deadline.cancel()
                throw Failure.outputTooLarge
            }
        }
        process.waitUntilExit()
        deadline.cancel()

        if timedOut { throw Failure.timedOut }
        return Outcome(status: process.terminationStatus, output: collected)
    }

    // MARK: - Paths

    private static func relativePath(of url: URL, in repository: URL) throws -> String {
        let target = PathPolicy.canonical(url).pathComponents
        let root = PathPolicy.canonical(repository).pathComponents
        guard PathPolicy.componentDescendant(target, of: root) else {
            // Asking a repository about a path outside it would silently answer
            // about the wrong thing.
            throw Failure.repositoryMismatch
        }
        return target.dropFirst(root.count).joined(separator: "/")
    }

    private static func nulSeparated(_ data: Data) -> [String] {
        data.split(separator: 0)
            .compactMap { String(data: Data($0), encoding: .utf8) }
            .filter { !$0.isEmpty }
    }
}
