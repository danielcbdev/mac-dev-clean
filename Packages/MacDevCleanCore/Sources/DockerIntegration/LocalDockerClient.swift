import Domain
import Foundation

/// The Docker installation and context the user explicitly chose.
public struct DockerSelection: Sendable, Equatable {
    public let executable: URL
    public let contextName: String
    public let builderName: String?

    public init(executable: URL, contextName: String, builderName: String? = nil) {
        self.executable = executable
        self.contextName = contextName
        self.builderName = builderName
    }
}

/// Reads and removes local Docker resources.
///
/// Eligibility is decided against **every** container, running or not. A
/// stopped container still holds a writable layer, still references its image,
/// and still holds its volumes; treating "not running" as "not in use" is how a
/// cleanup tool destroys somebody's database.
///
/// Sizes are reported only where the daemon gives an authoritative number. No
/// volume is mounted and the Docker disk image is never read to work one out.
/// Image sizes share layers between images, so they are per-kind estimates and
/// are never added into one confident total.
public actor LocalDockerClient: DockerClient {
    private let discovery: DockerDiscovery
    private let runner: any ProcessRunning
    private let clock: any ClockProviding
    private let selection: DockerSelection

    public init(
        discovery: DockerDiscovery,
        runner: any ProcessRunning,
        clock: any ClockProviding,
        selection: DockerSelection
    ) {
        self.discovery = discovery
        self.runner = runner
        self.clock = clock
        self.selection = selection
    }

    // MARK: - Reading

    public func inventory() async throws -> DockerInventory {
        let capability = try await capability()
        let world = try await readWorld(capability)

        var candidates: [CleanupCandidate] = []
        var evidence: [UUID: CandidateEvidence] = [:]

        func register(_ candidate: CleanupCandidate, state: String) {
            candidates.append(candidate)
            evidence[candidate.id] = CandidateEvidence(
                identity: nil,
                allowedRoot: nil,
                contextFingerprint: capability.fingerprint,
                ruleEvidenceDigest: Self.digest(
                    fingerprint: capability.fingerprint,
                    kind: candidate.method,
                    location: candidate.location,
                    state: state
                )
            )
        }

        for container in world.containers where !container.isRunning {
            let detail = world.containerDetails[container.id]
            // High, not low: a writable layer can hold data that exists
            // nowhere else.
            register(
                Self.candidate(
                    kind: .container,
                    id: container.id,
                    context: capability.contextName,
                    builder: nil,
                    size: detail?.sizeRootFs,
                    risk: .high,
                    consequenceKey: ConsequenceKey.rebuildOutput
                ),
                state: container.state
            )
        }

        for image in world.images where !world.referencedImageIDs.contains(image.id) {
            // Medium: an unused local image has no guaranteed remote
            // replacement, and a locally built one has none at all.
            register(
                Self.candidate(
                    kind: .image,
                    id: image.id,
                    context: capability.contextName,
                    builder: nil,
                    size: world.imageDetails[image.id]?.size,
                    risk: .medium,
                    consequenceKey: ConsequenceKey.redownloadTooling
                ),
                state: image.isDangling ? "dangling" : "tagged"
            )
        }

        for volume in world.volumes
        where volume.isLocalDriver && !world.referencedVolumeNames.contains(volume.name) {
            register(
                Self.candidate(
                    kind: .volume,
                    id: volume.name,
                    context: capability.contextName,
                    builder: nil,
                    size: world.volumeDetails[volume.name]?.size,
                    risk: .high,
                    consequenceKey: ConsequenceKey.userSelectedFile
                ),
                state: volume.driver
            )
        }

        for record in world.buildCache where record.isEligible {
            register(
                Self.candidate(
                    kind: .buildCache,
                    id: record.id,
                    context: capability.contextName,
                    builder: capability.builderName,
                    // A shared record's bytes belong to more than one record,
                    // so it never contributes an exact number.
                    size: record.shared ? nil : record.size,
                    risk: .low,
                    consequenceKey: ConsequenceKey.rebuildSlowerNextTime
                ),
                state: record.shared ? "shared" : "exclusive"
            )
        }

        return DockerInventory(
            fingerprint: capability.fingerprint,
            candidates: candidates,
            evidence: evidence
        )
    }

    // MARK: - Revalidation

    public func revalidate(_ item: CleanupCandidate, evidence: CandidateEvidence) async throws {
        guard case .docker(_, _, let kind, let id) = item.location else {
            throw PolicyError.unsupported
        }

        let capability = try await capability()
        // The context may still be called the same thing while pointing at a
        // different daemon entirely.
        guard capability.fingerprint == evidence.contextFingerprint else {
            throw PolicyError.changed
        }
        try DockerIdentifier.validate(kind: kind, id: id)

        switch kind {
        case .container:
            let details = try await inspectContainers(capability, ids: [id])
            guard let detail = details.first else { throw PolicyError.missing }
            // It started up again between the review and now.
            guard !detail.running else { throw PolicyError.changed }

        case .image:
            let data = try await read(
                capability, DockerCommandFactory.Read.imageInspect(capability.contextName, id: id))
            guard let detail = try DockerParser.imageDetails(data).first else {
                throw PolicyError.missing
            }
            // A non-forcing removal cannot address one image that answers to
            // several names without affecting references nobody reviewed.
            guard detail.repoTags.count <= 1 else { throw PolicyError.unsupported }
            let world = try await readContainers(capability)
            guard !world.referencedImageIDs.contains(id) else { throw PolicyError.changed }

        case .volume:
            let data = try await read(
                capability,
                DockerCommandFactory.Read.volumeInspect(capability.contextName, name: id))
            guard try DockerParser.volumeDetails(data).first != nil else {
                throw PolicyError.missing
            }
            let world = try await readContainers(capability)
            // Newly attached — including to a container that is merely stopped.
            guard !world.referencedVolumeNames.contains(id) else { throw PolicyError.changed }

        case .buildCache:
            guard capability.buildCacheSupported, let builder = capability.builderName else {
                throw PolicyError.unsupported
            }
            let data = try await read(
                capability,
                DockerCommandFactory.Read.buildxUsage(capability.contextName, builder: builder))
            guard let record = try DockerParser.buildCache(data).first(where: { $0.id == id })
            else {
                throw PolicyError.missing
            }
            guard record.isEligible else { throw PolicyError.changed }
        }
    }

    // MARK: - Removal

    public func remove(_ item: CleanupCandidate) async throws {
        guard case .docker(_, _, let kind, let id) = item.location else {
            throw PolicyError.unsupported
        }
        let capability = try await capability()
        let arguments = try DockerCommandFactory.arguments(
            for: DockerResource(kind: kind, id: id),
            context: capability.contextName,
            builder: capability.builderName
        )

        let output: ProcessOutput
        do {
            output = try await runner.run(
                ProcessRequest(
                    executable: capability.executable,
                    arguments: arguments,
                    environment: DockerEnvironment.read(),
                    timeoutSeconds: DockerEnvironment.writeTimeout,
                    outputLimit: DockerEnvironment.outputLimit
                )
            )
        } catch ProcessError.timeout {
            // The write may already have taken effect. Ask, once — and if the
            // answer is not clear, say so rather than trying again.
            try await settleAfterTimeout(capability, kind: kind, id: id)
            return
        } catch ProcessError.cancelled {
            throw PolicyError.cancelled
        } catch {
            throw PolicyError.unavailable
        }

        guard output.exitCode == 0 else {
            let message = String(decoding: output.stderr, as: UTF8.self).lowercased()
            if message.contains("no such") { throw PolicyError.missing }
            if message.contains("in use") || message.contains("is being used") {
                throw PolicyError.changed
            }
            throw PolicyError.unavailable
        }
    }

    /// Three states, deliberately. "I could not find out" is not "it is gone".
    private enum Presence {
        case present
        case absent
        case unknown
    }

    private func settleAfterTimeout(
        _ capability: DockerCapability,
        kind: DockerOperation,
        id: String
    ) async throws {
        let context = capability.contextName
        let presence: Presence

        switch kind {
        case .container:
            presence = await probe(
                capability,
                DockerCommandFactory.Read.containerInspect(context, id: id)
            ) { (try? DockerParser.containerDetails($0))?.isEmpty == false }

        case .image:
            presence = await probe(
                capability,
                DockerCommandFactory.Read.imageInspect(context, id: id)
            ) { (try? DockerParser.imageDetails($0))?.isEmpty == false }

        case .volume:
            presence = await probe(
                capability,
                DockerCommandFactory.Read.volumeInspect(context, name: id)
            ) { (try? DockerParser.volumeDetails($0))?.isEmpty == false }

        case .buildCache:
            guard let builder = capability.builderName else {
                throw DockerOutcomeError.indeterminate
            }
            presence = await probe(
                capability,
                DockerCommandFactory.Read.buildxUsage(context, builder: builder)
            ) { (try? DockerParser.buildCache($0))?.contains { $0.id == id } == true }
        }

        switch presence {
        case .absent:
            // It is gone. The write landed before the deadline passed, and it
            // is emphatically not repeated.
            return
        case .present:
            throw PolicyError.unavailable
        case .unknown:
            throw DockerOutcomeError.indeterminate
        }
    }

    /// Runs one inspection and classifies the answer.
    ///
    /// A non-zero exit that says "no such" is a real absence. Anything else —
    /// a timeout, a launch failure, an exit code nobody recognises — is
    /// unknown, never absence.
    private func probe(
        _ capability: DockerCapability,
        _ arguments: [String],
        isPresent: (Data) -> Bool
    ) async -> Presence {
        let output: ProcessOutput
        do {
            output = try await runner.run(
                ProcessRequest(
                    executable: capability.executable,
                    arguments: arguments,
                    environment: DockerEnvironment.read(),
                    timeoutSeconds: DockerEnvironment.readTimeout,
                    outputLimit: DockerEnvironment.outputLimit
                )
            )
        } catch {
            return .unknown
        }

        if output.exitCode == 0 {
            return isPresent(output.stdout) ? .present : .absent
        }
        let message = String(decoding: output.stderr, as: UTF8.self).lowercased()
        return message.contains("no such") ? .absent : .unknown
    }

    // MARK: - Reading the daemon

    private struct World {
        var containers: [ContainerDTO] = []
        var images: [ImageDTO] = []
        var volumes: [VolumeDTO] = []
        var buildCache: [BuildCacheDTO] = []
        var containerDetails: [String: ContainerDetailDTO] = [:]
        var imageDetails: [String: ImageDetailDTO] = [:]
        var volumeDetails: [String: VolumeDetailDTO] = [:]
        /// Images and volumes referenced by **any** container, stopped included.
        var referencedImageIDs: Set<String> = []
        var referencedVolumeNames: Set<String> = []
    }

    private func capability() async throws -> DockerCapability {
        try await discovery.discover(
            executable: selection.executable,
            context: selection.contextName,
            builder: selection.builderName
        )
    }

    private func readContainers(_ capability: DockerCapability) async throws -> World {
        var world = World()
        let context = capability.contextName

        let listing = try await read(capability, DockerCommandFactory.Read.containerList(context))
        world.containers = try DockerParser.containers(listing)

        let details = try await inspectContainers(
            capability, ids: world.containers.map(\.id))
        for detail in details {
            world.containerDetails[detail.id] = detail
            world.referencedImageIDs.insert(detail.imageID)
            world.referencedVolumeNames.formUnion(detail.mountNames)
        }
        // The listing's own mount column is a second source for the same
        // question; using both means a parsing gap in one does not silently
        // widen eligibility.
        for container in world.containers {
            world.referencedVolumeNames.formUnion(container.mounts)
        }
        return world
    }

    private func readWorld(_ capability: DockerCapability) async throws -> World {
        var world = try await readContainers(capability)
        let context = capability.contextName

        world.images = try DockerParser.images(
            try await read(capability, DockerCommandFactory.Read.imageList(context)))
        for image in world.images where !world.referencedImageIDs.contains(image.id) {
            if let data = try? await read(
                capability, DockerCommandFactory.Read.imageInspect(context, id: image.id)),
                let detail = try? DockerParser.imageDetails(data).first
            {
                world.imageDetails[image.id] = detail
            }
        }

        world.volumes = try DockerParser.volumes(
            try await read(capability, DockerCommandFactory.Read.volumeList(context)))
        for volume in world.volumes
        where volume.isLocalDriver && !world.referencedVolumeNames.contains(volume.name) {
            if let data = try? await read(
                capability, DockerCommandFactory.Read.volumeInspect(context, name: volume.name)),
                let detail = try? DockerParser.volumeDetails(data).first
            {
                world.volumeDetails[volume.name] = detail
            }
        }

        if capability.buildCacheSupported, let builder = capability.builderName,
            let data = try? await read(
                capability, DockerCommandFactory.Read.buildxUsage(context, builder: builder))
        {
            world.buildCache = (try? DockerParser.buildCache(data)) ?? []
        }

        return world
    }

    private func inspectContainers(
        _ capability: DockerCapability,
        ids: [String]
    ) async throws -> [ContainerDetailDTO] {
        var details: [ContainerDetailDTO] = []
        for id in ids {
            guard (try? DockerIdentifier.validateContainerID(id)) != nil else { continue }
            guard
                let data = try? await read(
                    capability,
                    DockerCommandFactory.Read.containerInspect(capability.contextName, id: id))
            else { continue }
            details.append(contentsOf: (try? DockerParser.containerDetails(data)) ?? [])
        }
        return details
    }

    private func read(_ capability: DockerCapability, _ arguments: [String]) async throws -> Data {
        let output: ProcessOutput
        do {
            output = try await runner.run(
                ProcessRequest(
                    executable: capability.executable,
                    arguments: arguments,
                    environment: DockerEnvironment.read(),
                    timeoutSeconds: DockerEnvironment.readTimeout,
                    outputLimit: DockerEnvironment.outputLimit
                )
            )
        } catch {
            throw PolicyError.unavailable
        }
        guard output.exitCode == 0 else { throw PolicyError.unavailable }
        return output.stdout
    }

    // MARK: - Helpers

    private static func candidate(
        kind: DockerOperation,
        id: String,
        context: String,
        builder: String?,
        size: UInt64?,
        risk: RiskLevel,
        consequenceKey: String
    ) -> CleanupCandidate {
        CleanupCandidate(
            id: UUID(),
            ruleID: "docker.\(kind.rawValue)",
            location: .docker(context: context, builder: builder, kind: kind, id: id),
            category: .docker,
            size: size,
            allocatedSize: nil,
            risk: risk,
            method: .docker(kind),
            consequenceKey: consequenceKey
        )
    }

    /// Binds a candidate to the exact daemon and the state it was in when it
    /// was offered. A change in either invalidates it.
    static func digest(
        fingerprint: String,
        kind: CleanupMethod,
        location: CleanupLocation,
        state: String
    ) -> String {
        guard case .docker(let context, let builder, let operation, let id) = location else {
            return ""
        }
        return [
            fingerprint, context, builder ?? "-", operation.rawValue, id, state,
        ].joined(separator: "|")
    }
}
