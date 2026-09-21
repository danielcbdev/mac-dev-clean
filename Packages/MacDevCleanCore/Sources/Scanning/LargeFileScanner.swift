import Domain
import Foundation
import UniformTypeIdentifiers

/// Finds big files inside folders the user chose for this feature.
///
/// This is an analysis tool, not a rule. Nothing detects a large file as
/// disposable: a 4 GB video may be the only copy of something irreplaceable.
/// Every eligible row is therefore classified **high risk**, nothing is ever
/// preselected, and the shared review flow demands an explicit acknowledgment.
///
/// `UniformTypeIdentifiers` is used to name a file's kind. It is an Apple
/// framework, so it needs no architectural decision record; it is noted here
/// because it is the one import this target has beyond the contract's table.
public struct LargeFileScanner: LargeFileScanning {
    /// Locations too broad to analyse. A user who wants their Documents folder
    /// examined can choose a specific subfolder inside it.
    static let refusedRoots = [
        "/", "/System", "/Library", "/Applications", "/Users", "/Volumes",
        "/private", "/var", "/bin", "/sbin", "/usr",
    ]

    private let files: any FileSystemClient
    private let context: any SafetyContextProviding
    private let store: any CandidateStore
    private let maximumDepth: Int

    public init(
        files: any FileSystemClient,
        context: any SafetyContextProviding,
        store: any CandidateStore,
        maximumDepth: Int = 24
    ) {
        self.files = files
        self.context = context
        self.store = store
        self.maximumDepth = maximumDepth
    }

    public func scan(
        _ request: LargeFileRequest
    ) -> AsyncThrowingStream<LargeFileEvent, Error> {
        AsyncThrowingStream(LargeFileEvent.self, bufferingPolicy: .unbounded) { continuation in
            let work = Task {
                do {
                    let result = try await run(request, into: continuation)
                    await store.save(result.snapshot)
                    continuation.yield(
                        .completed(rows: result.rows, snapshot: result.snapshot))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    // MARK: - Walking

    private struct Result {
        let rows: [LargeFileRow]
        let snapshot: ScanSnapshot
    }

    private func run(
        _ request: LargeFileRequest,
        into continuation: AsyncThrowingStream<LargeFileEvent, Error>.Continuation
    ) async throws -> Result {
        let safety = try await context.current()
        // Only folders the user chose for *this* feature, deduplicated so an
        // overlapping pair cannot list a file twice.
        let allowed = Set(
            safety.largeFileRoots.map { PathPolicy.canonical($0).path })
        let roots = DeveloperScanner.deduplicate(
            request.roots.map(\.url)
                .filter { allowed.contains(PathPolicy.canonical($0).path) }
        )

        var rows: [LargeFileRow] = []
        var candidates: [CleanupCandidate] = []
        var evidence: [UUID: CandidateEvidence] = [:]
        var visited = 0
        var lastReported = 0

        for root in roots {
            guard !Self.isRefused(root) else {
                continuation.yield(.issue("issue.largeFiles.rootTooBroad"))
                continue
            }
            guard let rootEntry = try? await files.entry(at: root),
                rootEntry.kind == .directory
            else {
                continuation.yield(.issue(ScanIssueCode.unreadable))
                continue
            }

            var pending: [(url: URL, depth: Int)] = [(root, 0)]
            while let current = pending.popLast() {
                try Task.checkCancellation()

                let children: [FileEntry]
                do {
                    children = try await files.children(of: current.url)
                } catch {
                    continuation.yield(.issue(ProjectDiscovery.issueCode(for: error)))
                    continue
                }
                visited += children.count
                if visited - lastReported >= 256 {
                    lastReported = visited
                    continuation.yield(.progress(visited))
                }

                for child in children {
                    if Self.isExcluded(child.url, safety: safety) { continue }

                    switch child.kind {
                    case .symbolicLink:
                        // Shown for information, never traversed, never acted
                        // on. The bytes behind it are not inside this folder.
                        if let row = Self.row(for: child, canSelect: false),
                            row.logicalBytes >= request.minimumBytes
                        {
                            rows.append(row)
                        }
                    case .directory:
                        guard !child.isMount, !child.isCloudPlaceholder else { continue }
                        guard child.identity.device == rootEntry.identity.device else {
                            continue
                        }
                        // A package is one document to the user, not a folder.
                        guard
                            !ProjectDiscovery.bundleExtensions.contains(
                                child.url.pathExtension.lowercased())
                        else { continue }
                        guard current.depth < maximumDepth else { continue }
                        pending.append((child.url, current.depth + 1))
                    case .file:
                        // Measuring a cloud placeholder would make the provider
                        // download it, which is the opposite of the point.
                        guard !child.isCloudPlaceholder else {
                            continuation.yield(
                                .issue(ScanIssueCode.cloudPlaceholderSkipped))
                            continue
                        }
                        guard let bytes = child.logicalBytes,
                            bytes >= request.minimumBytes
                        else { continue }
                        guard let row = Self.row(for: child, canSelect: true) else { continue }
                        rows.append(row)

                        let candidate = CleanupCandidate(
                            id: row.id,
                            ruleID: manualLargeFileRuleID,
                            location: .file(child.url),
                            category: .largeFiles,
                            size: bytes,
                            allocatedSize: child.allocatedBytes,
                            // Always high: nothing here was detected as
                            // disposable. The user chose it.
                            risk: .high,
                            method: .trash,
                            consequenceKey: ConsequenceKey.userSelectedFile
                        )
                        candidates.append(candidate)
                        evidence[candidate.id] = CandidateEvidence(
                            identity: child.identity,
                            allowedRoot: root,
                            contextFingerprint: "largeFile",
                            ruleEvidenceDigest: "manual"
                        )
                    case .other:
                        continue
                    }
                }
            }
        }

        try Task.checkCancellation()
        let snapshot = ScanSnapshot(
            id: UUID(),
            policyRevision: safety.revision,
            candidates: candidates,
            evidence: evidence
        )
        return Result(rows: rows.sorted { $0.logicalBytes > $1.logicalBytes }, snapshot: snapshot)
    }

    // MARK: - Helpers

    static func isRefused(_ url: URL) -> Bool {
        let path = PathPolicy.canonical(url).path
        if refusedRoots.contains(path) { return true }
        // The home folder itself is too broad; a subfolder of it is fine.
        return path == PathPolicy.canonical(URL(fileURLWithPath: NSHomeDirectory())).path
    }

    private static func isExcluded(_ url: URL, safety: SafetyContext) -> Bool {
        let target = PathPolicy.canonical(url).pathComponents.map { $0.lowercased() }
        for exclusion in safety.exclusions {
            guard case .path(let excluded) = exclusion else { continue }
            let other = PathPolicy.canonical(excluded).pathComponents.map { $0.lowercased() }
            if target == other || PathPolicy.componentDescendant(target, of: other) {
                return true
            }
        }
        return safety.exclusions.contains(.category(.largeFiles))
    }

    private static func row(for entry: FileEntry, canSelect: Bool) -> LargeFileRow? {
        guard let bytes = entry.logicalBytes else { return nil }
        return LargeFileRow(
            id: UUID(),
            url: entry.url,
            logicalBytes: bytes,
            modifiedAt: Date(
                timeIntervalSince1970: Double(entry.identity.modifiedNanoseconds) / 1_000_000_000),
            kindDescription: kind(for: entry),
            canSelect: canSelect
        )
    }

    /// Derived from the file name, not by opening the file.
    static func kind(for entry: FileEntry) -> String {
        if entry.kind == .symbolicLink { return "Alias" }
        let ext = entry.url.pathExtension
        guard !ext.isEmpty else { return "Document" }
        if let type = UTType(filenameExtension: ext), let description = type.localizedDescription {
            return description
        }
        return ext.uppercased()
    }
}
