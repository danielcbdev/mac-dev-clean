import Domain
import Foundation

/// Runs one external command with hard bounds, and refuses several outright.
///
/// The guarantees, in order of importance:
///
/// - **No shell, ever.** The executable is a `URL` and the arguments are an
///   array. A shell, an interpreter or `sudo` is refused before launch, so
///   there is no path through this type that reinterprets an argument as
///   syntax.
/// - **No `PATH` lookup.** A relative executable is refused; only an absolute
///   path to a real executable file runs.
/// - **Nothing is inherited.** The child gets exactly the environment the
///   request states, so a variable in the user's session cannot redirect it.
/// - **Both streams are drained concurrently.** Draining one after the other
///   deadlocks as soon as the other fills its pipe buffer.
/// - **Bounded output and a hard deadline.** Exceeding either terminates the
///   child rather than waiting or growing.
public struct LocalProcessRunner: ProcessRunning {
    /// Programs that turn an argument back into syntax, plus privilege
    /// escalation. None of them is ever needed here.
    private static let refusedNames: Set<String> = [
        "sh", "bash", "zsh", "csh", "tcsh", "ksh", "dash", "fish",
        "env", "sudo", "su", "doas", "osascript", "open",
        "perl", "python", "python3", "ruby", "node", "swift", "xargs",
    ]

    private let queue: DispatchQueue

    public init() {
        queue = DispatchQueue(
            label: "dev.macdevclean.process",
            qos: .utility,
            autoreleaseFrequency: .workItem
        )
    }

    public func run(_ request: ProcessRequest) async throws -> ProcessOutput {
        try Self.refuseUnacceptableExecutable(request.executable)
        try Task.checkCancellation()

        let control = ProcessControl()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<ProcessOutput, Error>) in
                queue.async {
                    continuation.resume(
                        with: Result { try Self.execute(request, control: control) })
                }
            }
        } onCancel: {
            control.cancel()
        }
    }

    // MARK: - Refusals

    private static func refuseUnacceptableExecutable(_ url: URL) throws {
        let path = url.standardizedFileURL.path
        guard path.hasPrefix("/") else { throw ProcessError.refusedExecutable }
        guard !refusedNames.contains(url.lastPathComponent.lowercased()) else {
            throw ProcessError.refusedExecutable
        }
    }

    // MARK: - Execution

    private static func execute(
        _ request: ProcessRequest,
        control: ProcessControl
    ) throws -> ProcessOutput {
        guard FileManager.default.isExecutableFile(atPath: request.executable.path) else {
            throw ProcessError.launchFailure
        }

        let process = Process()
        process.executableURL = request.executable
        process.arguments = request.arguments
        process.environment = request.environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw ProcessError.launchFailure
        }
        control.attach(process)
        if control.isCancelled { process.terminate() }

        let sink = OutputSink(limit: request.outputLimit)
        let group = DispatchGroup()

        // Both pipes are drained at the same time. Reading one to the end
        // before starting the other deadlocks the moment the second fills.
        for (handle, isStandardOutput) in [
            (outPipe.fileHandleForReading, true),
            (errPipe.fileHandleForReading, false),
        ] {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                defer { group.leave() }
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    if !sink.append(chunk, toStandardOutput: isStandardOutput) {
                        process.terminate()
                        break
                    }
                }
            }
        }

        let deadline = DispatchTime.now() + request.timeoutSeconds
        if group.wait(timeout: deadline) == .timedOut {
            control.markTimedOut()
            process.terminate()
            _ = group.wait(timeout: .now() + 5)
        }
        process.waitUntilExit()

        if control.isCancelled { throw ProcessError.cancelled }
        if control.timedOut { throw ProcessError.timeout }
        if sink.exceeded { throw ProcessError.outputLimit }

        return ProcessOutput(
            stdout: sink.standardOutput,
            stderr: sink.standardError,
            exitCode: process.terminationStatus
        )
    }
}

/// Lets the cancellation handler reach a process that does not exist yet when
/// the handler is installed.
///
/// `@unchecked Sendable` is sound here because every stored property is read
/// and written only while holding the lock.
private final class ProcessControl: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var didTimeOut = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    var timedOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didTimeOut
    }

    func attach(_ value: Process) {
        lock.lock()
        process = value
        let shouldStop = cancelled
        lock.unlock()
        if shouldStop { value.terminate() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let running = process
        lock.unlock()
        running?.terminate()
    }

    func markTimedOut() {
        lock.lock()
        didTimeOut = true
        lock.unlock()
    }
}

/// Accumulates both streams under one lock and enforces the combined bound.
private final class OutputSink: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var out = Data()
    private var err = Data()
    private var overLimit = false

    init(limit: Int) {
        self.limit = limit
    }

    var standardOutput: Data {
        lock.lock()
        defer { lock.unlock() }
        return out
    }

    var standardError: Data {
        lock.lock()
        defer { lock.unlock() }
        return err
    }

    var exceeded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return overLimit
    }

    /// Returns false once the bound is exceeded, which tells the reader to stop.
    func append(_ chunk: Data, toStandardOutput: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if overLimit { return false }
        if toStandardOutput { out.append(chunk) } else { err.append(chunk) }
        if out.count + err.count > limit {
            overLimit = true
            return false
        }
        return true
    }
}
