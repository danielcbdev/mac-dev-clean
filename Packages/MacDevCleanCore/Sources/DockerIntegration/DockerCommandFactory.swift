import Domain
import Foundation

/// One reviewed Docker resource.
public struct DockerResource: Sendable, Equatable, Hashable {
    public let kind: DockerOperation
    public let id: String

    public init(kind: DockerOperation, id: String) {
        self.kind = kind
        self.id = id
    }
}

/// Builds removal arguments, and can build nothing else.
///
/// This is an allowlist expressed as code: there is no parameter that widens a
/// command, no string interpolation into an argument, and no way to reach a
/// prune that removes something nobody reviewed.
///
/// Deliberately absent, every one of them a decision:
///
/// - `--all` on any prune — it removes records outside the reviewed set.
/// - `system prune`, `builder prune`, `container prune`, `image prune`,
///   `volume prune` — their effects cannot be shown on a review screen.
/// - `--force` on container or image removal — forcing stops a running
///   container or breaks a tag reference the user never looked at.
/// - `--volumes` on container removal — that destroys data belonging to a
///   different resource kind.
///
/// `buildx prune` is the single command that carries `--force`, and only to
/// suppress its interactive prompt *after* the app's own confirmation. It is
/// always pinned to one record id and to `inuse=false`.
public enum DockerCommandFactory {

    public static func arguments(
        for resource: DockerResource,
        context: String,
        builder: String?
    ) throws -> [String] {
        try DockerIdentifier.validateName(context)
        try DockerIdentifier.validate(kind: resource.kind, id: resource.id)

        switch resource.kind {
        case .container:
            return ["--context", context, "container", "rm", resource.id]

        case .image:
            // --no-prune: removing an image must not also remove parent layers
            // that were never part of the review.
            return ["--context", context, "image", "rm", "--no-prune", resource.id]

        case .volume:
            return ["--context", context, "volume", "rm", resource.id]

        case .buildCache:
            guard let builder else { throw PolicyError.unsupported }
            try DockerIdentifier.validateName(builder)
            return [
                "--context", context,
                "buildx", "prune",
                "--builder", builder,
                "--filter", "id=\(resource.id)",
                "--filter", "inuse=false",
                "--force",
            ]
        }
    }

    /// The read commands the inventory uses. Listed here so the complete set of
    /// commands this app can issue is visible in one place.
    public enum Read {
        public static func contextInspect(_ context: String) -> [String] {
            ["context", "inspect", context]
        }
        public static func version(_ context: String) -> [String] {
            ["--context", context, "version", "--format", "{{json .}}"]
        }
        public static func info(_ context: String) -> [String] {
            ["--context", context, "info", "--format", "{{json .}}"]
        }
        public static func containerList(_ context: String) -> [String] {
            [
                "--context", context, "container", "ls", "--all", "--no-trunc",
                "--format", "{{json .}}",
            ]
        }
        public static func containerInspect(_ context: String, id: String) -> [String] {
            ["--context", context, "container", "inspect", "--size", id]
        }
        public static func imageList(_ context: String) -> [String] {
            ["--context", context, "image", "ls", "--no-trunc", "--format", "{{json .}}"]
        }
        public static func imageInspect(_ context: String, id: String) -> [String] {
            ["--context", context, "image", "inspect", id]
        }
        public static func volumeList(_ context: String) -> [String] {
            ["--context", context, "volume", "ls", "--format", "{{json .}}"]
        }
        public static func volumeInspect(_ context: String, name: String) -> [String] {
            ["--context", context, "volume", "inspect", name]
        }
        public static func buildxInspect(_ context: String, builder: String) -> [String] {
            ["--context", context, "buildx", "inspect", builder]
        }
        public static func buildxUsage(_ context: String, builder: String) -> [String] {
            ["--context", context, "buildx", "du", "--builder", builder, "--format=json"]
        }
    }
}
