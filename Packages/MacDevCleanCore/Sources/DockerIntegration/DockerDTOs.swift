import Domain
import Foundation

/// A row from `docker container ls --all --format {{json .}}`.
public struct ContainerDTO: Sendable, Equatable {
    public let id: String
    public let image: String
    public let names: String
    public let state: String
    /// Volume names and bind sources this container references.
    public let mounts: [String]

    public var isRunning: Bool { state == "running" || state == "restarting" }

    public init(id: String, image: String, names: String, state: String, mounts: [String]) {
        self.id = id
        self.image = image
        self.names = names
        self.state = state
        self.mounts = mounts
    }
}

/// A row from `docker image ls --no-trunc --format {{json .}}`.
public struct ImageDTO: Sendable, Equatable {
    public let id: String
    public let repository: String
    public let tag: String

    /// True when the image has no repository or tag to identify it by.
    public var isDangling: Bool {
        repository == "<none>" || repository.isEmpty || tag == "<none>"
    }

    public init(id: String, repository: String, tag: String) {
        self.id = id
        self.repository = repository
        self.tag = tag
    }
}

/// A row from `docker volume ls --format {{json .}}`.
public struct VolumeDTO: Sendable, Equatable {
    public let name: String
    public let driver: String
    public let scope: String

    /// Only volumes on the built-in local driver are ever eligible. A plugin or
    /// cluster driver may be backed by storage this app knows nothing about.
    public var isLocalDriver: Bool { driver == "local" && scope == "local" }

    public init(name: String, driver: String, scope: String) {
        self.name = name
        self.driver = driver
        self.scope = scope
    }
}

/// A row from `docker buildx du --format=json`.
public struct BuildCacheDTO: Sendable, Equatable {
    public let id: String
    /// `nil` when the size was absent, not a number, negative, or too large to
    /// represent. It is never silently treated as zero.
    public let size: UInt64?
    /// Absent means **not** reclaimable. A missing boolean is never read as the
    /// permissive answer.
    public let reclaimable: Bool
    /// Shared records are excluded from any exact total, because their bytes
    /// belong to more than one record.
    public let shared: Bool
    public let mutable: Bool
    /// Set when the size could not be trusted, so the reason survives to the
    /// interface instead of being lost.
    public let sizeIssue: String?

    public var isEligible: Bool { reclaimable && !mutable }

    public init(
        id: String,
        size: UInt64?,
        reclaimable: Bool,
        shared: Bool,
        mutable: Bool,
        sizeIssue: String? = nil
    ) {
        self.id = id
        self.size = size
        self.reclaimable = reclaimable
        self.shared = shared
        self.mutable = mutable
        self.sizeIssue = sizeIssue
    }
}

/// Authoritative per-resource detail from an `inspect` call.
public struct ContainerDetailDTO: Sendable, Equatable {
    public let id: String
    public let imageID: String
    public let running: Bool
    public let mountNames: [String]
    public let sizeRootFs: UInt64?

    public init(
        id: String, imageID: String, running: Bool, mountNames: [String], sizeRootFs: UInt64?
    ) {
        self.id = id
        self.imageID = imageID
        self.running = running
        self.mountNames = mountNames
        self.sizeRootFs = sizeRootFs
    }
}

public struct ImageDetailDTO: Sendable, Equatable {
    public let id: String
    public let size: UInt64?
    public let repoTags: [String]
    public let repoDigests: [String]

    public init(id: String, size: UInt64?, repoTags: [String], repoDigests: [String]) {
        self.id = id
        self.size = size
        self.repoTags = repoTags
        self.repoDigests = repoDigests
    }
}

public struct VolumeDetailDTO: Sendable, Equatable {
    public let name: String
    public let driver: String
    /// Only present when the daemon itself reports it. This app never mounts a
    /// volume or reads the Docker disk image to work a size out.
    public let size: UInt64?

    public init(name: String, driver: String, size: UInt64?) {
        self.name = name
        self.driver = driver
        self.size = size
    }
}
