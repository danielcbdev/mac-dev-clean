import Foundation

/// What a directory entry is, determined with `lstat` semantics: a symbolic
/// link reports `.symbolicLink`, never the kind of whatever it points at.
public enum EntryKind: String, Sendable, Equatable {
    case directory, file, symbolicLink, other
}

/// One directory entry and the metadata scanning needs about it.
public struct FileEntry: Sendable, Equatable {
    public let url: URL
    public let kind: EntryKind
    public let identity: FileIdentity
    /// Apparent size. `nil` when it could not be determined.
    public let logicalBytes: UInt64?
    /// Space actually occupied, where the filesystem reports it.
    public let allocatedBytes: UInt64?
    /// True when this entry is the root of a different mounted volume.
    /// Scanning never descends into one.
    public let isMount: Bool
    /// True when the file's data lives in a cloud provider rather than on disk.
    /// Measuring one would force a download, so it is never materialised.
    public let isCloudPlaceholder: Bool

    public init(
        url: URL,
        kind: EntryKind,
        identity: FileIdentity,
        logicalBytes: UInt64?,
        allocatedBytes: UInt64?,
        isMount: Bool,
        isCloudPlaceholder: Bool
    ) {
        self.url = url
        self.kind = kind
        self.identity = identity
        self.logicalBytes = logicalBytes
        self.allocatedBytes = allocatedBytes
        self.isMount = isMount
        self.isCloudPlaceholder = isCloudPlaceholder
    }
}

/// Read-only filesystem metadata access.
///
/// Every implementation uses `lstat` semantics and performs no synchronous work
/// on the main actor. Nothing here writes, moves or deletes.
public protocol FileSystemClient: Sendable {
    func children(of url: URL) async throws -> [FileEntry]
    func entry(at url: URL) async throws -> FileEntry
    /// Reads at most `limit` bytes of an evidence file. Anything larger, or
    /// unreadable, throws rather than being partially evaluated.
    func readPrefix(at url: URL, limit: Int) async throws -> Data
}

/// Read-only Git questions used to decide whether an ambiguous directory holds
/// authored content.
///
/// Implementations never run hooks, never evaluate repository configuration
/// that can invoke an external filter, and never build a shell command.
public protocol GitStatusChecking: Sendable {
    func containsTrackedFiles(at url: URL, repository: URL) async throws -> Bool
    func isIgnored(_ url: URL, repository: URL) async throws -> Bool
}
