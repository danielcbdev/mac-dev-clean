import Foundation

/// One external command, described completely and in advance.
///
/// There is no command *string* anywhere in this type. The executable is a URL
/// and the arguments are separate strings, so nothing the app passes can be
/// reinterpreted as syntax by a shell — because no shell is involved.
///
/// The environment is stated explicitly rather than inherited, so a variable in
/// the user's session cannot redirect the command somewhere else.
public struct ProcessRequest: Sendable, Equatable {
    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let timeoutSeconds: Double
    /// Combined bound on stdout and stderr. A command that talks too much is
    /// killed rather than allowed to exhaust memory.
    public let outputLimit: Int

    public init(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        timeoutSeconds: Double,
        outputLimit: Int
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.timeoutSeconds = timeoutSeconds
        self.outputLimit = outputLimit
    }
}

public struct ProcessOutput: Sendable, Equatable {
    public let stdout: Data
    public let stderr: Data
    public let exitCode: Int32

    public init(stdout: Data, stderr: Data, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

public enum ProcessError: Error, Sendable, Equatable {
    /// The command did not finish within its deadline. For a read this is
    /// harmless; for a write it means the outcome is unknown.
    case timeout
    /// The command produced more output than the request allowed.
    case outputLimit
    /// The command could not be started at all.
    case launchFailure
    case cancelled
    /// The executable is not something this app is willing to run — a shell, an
    /// interpreter, `sudo`, or anything reached by a relative path.
    case refusedExecutable
}

public protocol ProcessRunning: Sendable {
    func run(_ request: ProcessRequest) async throws -> ProcessOutput
}
