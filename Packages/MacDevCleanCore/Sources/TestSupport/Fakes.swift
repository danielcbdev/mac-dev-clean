import Domain
import Foundation

/// A clock that never moves, so plan expiry and timestamps are deterministic.
public struct FixedClock: ClockProviding {
    private let value: Date

    public init(now: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        value = now
    }

    public func now() -> Date { value }
}

/// A safety context a test can change between calls, to model the user editing
/// roots or exclusions while a scan snapshot is still in hand.
public actor MemoryContext: SafetyContextProviding {
    private var value: SafetyContext

    public init(value: SafetyContext) {
        self.value = value
    }

    public func current() async throws -> SafetyContext { value }

    public func update(_ newValue: SafetyContext) {
        value = newValue
    }
}

/// Git answers a test states outright, so ambiguous-artifact rules can be
/// exercised without creating real repositories.
public struct FakeGitStatus: GitStatusChecking {
    private let trackedPaths: Set<String>
    private let ignoredPaths: Set<String>
    private let failure: PolicyError?

    public init(
        tracked: Set<String> = [],
        ignored: Set<String> = [],
        failure: PolicyError? = nil
    ) {
        trackedPaths = tracked
        ignoredPaths = ignored
        self.failure = failure
    }

    public func containsTrackedFiles(at url: URL, repository: URL) async throws -> Bool {
        if let failure { throw failure }
        return trackedPaths.contains(url.standardizedFileURL.path)
    }

    public func isIgnored(_ url: URL, repository: URL) async throws -> Bool {
        if let failure { throw failure }
        return ignoredPaths.contains(url.standardizedFileURL.path)
    }
}

/// A filesystem a test describes entry by entry.
///
/// It exists for cases a fixture on the real disk cannot produce on demand —
/// a second volume, a mount point, a cloud placeholder — and it counts reads so
/// a test can assert that work stopped when it was supposed to.
public actor StubFileSystem: FileSystemClient {
    private var entries: [String: FileEntry] = [:]
    private var childLists: [String: [FileEntry]] = [:]
    private var contents: [String: Data] = [:]
    private var failures: [String: PolicyError] = [:]
    private var reads = 0

    public init() {}

    public func setEntry(_ entry: FileEntry) {
        entries[entry.url.standardizedFileURL.path] = entry
    }

    public func setChildren(_ children: [FileEntry], of url: URL) {
        childLists[url.standardizedFileURL.path] = children
        for child in children { setEntry(child) }
    }

    public func setContents(_ data: Data, at url: URL) {
        contents[url.standardizedFileURL.path] = data
    }

    public func setFailure(_ error: PolicyError, at url: URL) {
        failures[url.standardizedFileURL.path] = error
    }

    public func readCount() -> Int { reads }

    public func children(of url: URL) async throws -> [FileEntry] {
        reads += 1
        let key = url.standardizedFileURL.path
        if let failure = failures[key] { throw failure }
        return childLists[key] ?? []
    }

    public func entry(at url: URL) async throws -> FileEntry {
        reads += 1
        let key = url.standardizedFileURL.path
        if let failure = failures[key] { throw failure }
        guard let entry = entries[key] else { throw PolicyError.missing }
        return entry
    }

    public func readPrefix(at url: URL, limit: Int) async throws -> Data {
        reads += 1
        let key = url.standardizedFileURL.path
        if let failure = failures[key] { throw failure }
        guard let data = contents[key] else { throw PolicyError.missing }
        guard data.count <= limit else { throw PolicyError.unsupported }
        return data
    }
}

/// Convenience builders for the metadata a stub entry needs.
extension FileEntry {
    public static func stub(
        url: URL,
        kind: EntryKind = .file,
        device: UInt64 = 1,
        inode: UInt64 = 1,
        modifiedNanoseconds: Int64 = 0,
        logicalBytes: UInt64? = 0,
        allocatedBytes: UInt64? = 0,
        isMount: Bool = false,
        isCloudPlaceholder: Bool = false
    ) -> FileEntry {
        FileEntry(
            url: url,
            kind: kind,
            identity: FileIdentity(
                device: device,
                inode: inode,
                modifiedNanoseconds: modifiedNanoseconds
            ),
            logicalBytes: logicalBytes,
            allocatedBytes: allocatedBytes,
            isMount: isMount,
            isCloudPlaceholder: isCloudPlaceholder
        )
    }
}
