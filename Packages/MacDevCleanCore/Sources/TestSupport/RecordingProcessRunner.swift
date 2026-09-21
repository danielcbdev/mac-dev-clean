import Domain
import Foundation

/// A process runner that answers from a script a test wrote, and launches
/// nothing.
///
/// Responses are matched on the argument list, so a test states exactly which
/// command it is answering. An unmatched command is a failure rather than an
/// empty success, because "Docker said nothing" must never read as "there is
/// nothing to clean".
public actor RecordingProcessRunner: ProcessRunning {
    public struct Invocation: Sendable, Equatable {
        public let executable: URL
        public let arguments: [String]
        public let environment: [String: String]
    }

    private var responses: [[String]: Result<ProcessOutput, ProcessError>] = [:]
    private var invocations: [Invocation] = []
    private var pauseAfterCalls = Int.max
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    // MARK: - Scripting

    public func respond(to arguments: [String], stdout: String, exitCode: Int32 = 0) {
        responses[arguments] = .success(
            ProcessOutput(stdout: Data(stdout.utf8), stderr: Data(), exitCode: exitCode)
        )
    }

    public func respond(to arguments: [String], stderr: String, exitCode: Int32) {
        responses[arguments] = .success(
            ProcessOutput(stdout: Data(), stderr: Data(stderr.utf8), exitCode: exitCode)
        )
    }

    public func fail(_ arguments: [String], with error: ProcessError) {
        responses[arguments] = .failure(error)
    }

    public func pause(after calls: Int) { pauseAfterCalls = calls }

    public func release() {
        released = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }

    // MARK: - Inspection

    public func calls() -> [Invocation] { invocations }
    public func argumentLists() -> [[String]] { invocations.map(\.arguments) }

    // MARK: - ProcessRunning

    public func run(_ request: ProcessRequest) async throws -> ProcessOutput {
        if !released, invocations.count >= pauseAfterCalls {
            await withCheckedContinuation { waiters.append($0) }
        }
        invocations.append(
            Invocation(
                executable: request.executable,
                arguments: request.arguments,
                environment: request.environment
            )
        )
        guard let response = responses[request.arguments] else {
            // Unscripted. Fail loudly rather than implying an empty result.
            throw ProcessError.launchFailure
        }
        return try response.get()
    }
}
