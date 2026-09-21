import Domain
import Foundation

/// What was found, and what it is allowed to do.
///
/// The fingerprint deliberately binds the endpoint, the daemon's own identity
/// and the builder — never just the context name. A context name is a label the
/// user can repoint at a completely different machine; the daemon identity is
/// not.
public struct DockerCapability: Sendable, Equatable {
    public let executable: URL
    public let contextName: String
    public let endpoint: URL
    public let daemonID: String
    public let builderName: String?
    /// False when Buildx is absent, on a remote node, or does not support the
    /// precise filtering this app requires. Only the build-cache feature is
    /// disabled; everything else keeps working.
    public let buildCacheSupported: Bool
    public let fingerprint: String

    public init(
        executable: URL,
        contextName: String,
        endpoint: URL,
        daemonID: String,
        builderName: String?,
        buildCacheSupported: Bool,
        fingerprint: String
    ) {
        self.executable = executable
        self.contextName = contextName
        self.endpoint = endpoint
        self.daemonID = daemonID
        self.builderName = builderName
        self.buildCacheSupported = buildCacheSupported
        self.fingerprint = fingerprint
    }
}

/// Decides whether there is a local Docker this app may touch.
///
/// Everything here is read-only. Docker Desktop is never started, no builder is
/// bootstrapped, nothing is pulled, and no login shell is run to find anything.
public struct DockerDiscovery: Sendable {

    /// Installation locations, in order. All absolute, none writable by a
    /// project, and none discovered by asking a shell where `docker` lives.
    public static let executableCandidates = [
        "/Applications/Docker.app/Contents/Resources/bin/docker",
        "/usr/local/bin/docker",
        "/opt/homebrew/bin/docker",
    ]

    private let runner: any ProcessRunning
    private let readTimeout: Double

    public init(runner: any ProcessRunning, readTimeout: Double = 10) {
        self.runner = runner
        self.readTimeout = readTimeout
    }

    // MARK: - Static validation

    /// Accepts a local Unix socket and nothing else.
    ///
    /// `ssh://` and `tcp://` endpoints reach someone else's machine. Cleaning
    /// resources there would be destroying data on a host the user is not
    /// looking at.
    public static func validateEndpoint(_ value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("unix://") else { throw PolicyError.outsideScope }
        let path = String(trimmed.dropFirst("unix://".count))
        guard path.hasPrefix("/"), path.count > 1, !path.contains("..") else {
            throw PolicyError.outsideScope
        }
        var components = URLComponents()
        components.scheme = "unix"
        components.path = path
        guard let url = components.url else { throw PolicyError.outsideScope }
        return url
    }

    /// Resolves the binary actually used, following an installation symlink so
    /// the app reports the real file rather than the alias.
    public static func locateExecutable(
        explicit: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let paths = explicit.map { [$0.path] } ?? executableCandidates
        for path in paths where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path).resolvingSymlinksInPath()
        }
        throw PolicyError.unavailable
    }

    // MARK: - Discovery

    public func discover(
        executable: URL,
        context: String,
        builder: String?
    ) async throws -> DockerCapability {
        try DockerIdentifier.validateName(context)

        // The endpoint is settled before the daemon is spoken to at all, so a
        // remote context never receives a single request.
        let contextData = try await read(executable, ["context", "inspect", context])
        let endpoint = try Self.validateEndpoint(Self.host(in: contextData))

        // Reachability. A non-zero exit here means the daemon is not running.
        _ = try await read(
            executable, ["--context", context, "version", "--format", "{{json .}}"])

        let infoData = try await read(
            executable, ["--context", context, "info", "--format", "{{json .}}"])
        let daemonID = try Self.daemonID(in: infoData)

        var resolvedBuilder: String?
        var buildCacheSupported = false
        if let builder {
            try DockerIdentifier.validateName(builder)
            if try await builderIsLocal(executable, context: context, builder: builder) {
                resolvedBuilder = builder
                buildCacheSupported = await buildCacheIsUsable(
                    executable, context: context, builder: builder)
            }
        }

        return DockerCapability(
            executable: executable,
            contextName: context,
            endpoint: endpoint,
            daemonID: daemonID,
            builderName: resolvedBuilder,
            buildCacheSupported: buildCacheSupported,
            fingerprint: Self.fingerprint(
                endpoint: endpoint, daemonID: daemonID, builder: resolvedBuilder)
        )
    }

    /// Endpoint, daemon identity and builder. Not the context name, which the
    /// user can repoint at another machine without changing a character of it.
    static func fingerprint(endpoint: URL, daemonID: String, builder: String?) -> String {
        "endpoint=\(endpoint.path)|daemon=\(daemonID)|builder=\(builder ?? "-")"
    }

    // MARK: - Builder

    private func builderIsLocal(
        _ executable: URL,
        context: String,
        builder: String
    ) async throws -> Bool {
        guard
            let data = try? await read(
                executable, ["--context", context, "buildx", "inspect", builder])
        else {
            return false
        }
        let text = String(decoding: data, as: UTF8.self)
        let endpoints =
            text
            .split(separator: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("Endpoint:") else { return nil }
                return trimmed.dropFirst("Endpoint:".count)
                    .trimmingCharacters(in: .whitespaces)
            }
        guard !endpoints.isEmpty else { return false }
        // Every node must be local. One remote node makes the whole builder
        // inspection-only.
        return endpoints.allSatisfy { endpoint in
            endpoint == "docker" || (try? Self.validateEndpoint(endpoint)) != nil
        }
    }

    /// A read-only probe. If Buildx cannot report usage as JSON, precise
    /// per-record cleanup is impossible, so that one feature stays off.
    private func buildCacheIsUsable(
        _ executable: URL,
        context: String,
        builder: String
    ) async -> Bool {
        guard
            let data = try? await read(
                executable,
                ["--context", context, "buildx", "du", "--builder", builder, "--format=json"]
            )
        else {
            return false
        }
        return (try? DockerParser.buildCache(data)) != nil
    }

    // MARK: - Reading

    private func read(_ executable: URL, _ arguments: [String]) async throws -> Data {
        let output: ProcessOutput
        do {
            output = try await runner.run(
                ProcessRequest(
                    executable: executable,
                    arguments: arguments,
                    environment: DockerEnvironment.read(),
                    timeoutSeconds: readTimeout,
                    outputLimit: DockerEnvironment.outputLimit
                )
            )
        } catch {
            throw PolicyError.unavailable
        }
        guard output.exitCode == 0 else { throw PolicyError.unavailable }
        return output.stdout
    }

    private static func host(in data: Data) throws -> String {
        guard let parsed = try? JSONSerialization.jsonObject(with: data),
            let entries = parsed as? [[String: Any]],
            let first = entries.first,
            let endpoints = first["Endpoints"] as? [String: Any],
            let docker = endpoints["docker"] as? [String: Any],
            let host = docker["Host"] as? String
        else {
            // A shape nobody recognises is a refusal, never an assumption.
            throw PolicyError.unsupported
        }
        return host
    }

    private static func daemonID(in data: Data) throws -> String {
        guard let parsed = try? JSONSerialization.jsonObject(with: data),
            let info = parsed as? [String: Any],
            let id = info["ID"] as? String,
            !id.isEmpty
        else {
            throw PolicyError.unsupported
        }
        return id
    }
}

/// The environment Docker commands run in.
///
/// Built from nothing, so `DOCKER_HOST`, `DOCKER_CONTEXT`, `BUILDX_BUILDER` and
/// `DOCKER_CONFIG` in the user's session cannot redirect a command at another
/// machine. `HOME` is included because context definitions live under it.
public enum DockerEnvironment {
    public static let outputLimit = 8 * 1024 * 1024
    public static let readTimeout: Double = 10
    public static let writeTimeout: Double = 60

    public static func read() -> [String: String] {
        ["HOME": NSHomeDirectory(), "LC_ALL": "C"]
    }
}
