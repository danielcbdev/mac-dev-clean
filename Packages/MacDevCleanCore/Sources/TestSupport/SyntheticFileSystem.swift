import Domain
import Foundation

/// A lazily generated Node project for scan stress and cancellation tests.
///
/// Its metadata describes `count` files without allocating file contents or a
/// 100,000-entry fixture on disk. Each directory response has at most 257
/// entries: one 256-file batch plus the next batch directory.
public actor SyntheticFileSystem: FileSystemClient {
    public static let batchSize = 256
    public static let root = URL(fileURLWithPath: "/synthetic/projects")
    private static let project = root.appendingPathComponent("app")
    private static let modules = project.appendingPathComponent("node_modules")

    private let count: Int
    private nonisolated let cancellation = SyntheticScanCancellation()
    private var payloadReads = 0
    private var firstBatchRead = false
    private var blockedBatchReleased = false
    private var firstBatchWaiters: [CheckedContinuation<Void, Never>] = []
    private var blockedBatchWaiters: [CheckedContinuation<Void, Never>] = []

    public init(count: Int) {
        self.count = count
    }

    public func waitForFirstBatch() async {
        guard !firstBatchRead else { return }
        await withCheckedContinuation { firstBatchWaiters.append($0) }
    }

    public func releaseBlockedBatch() {
        blockedBatchReleased = true
        let waiters = blockedBatchWaiters
        blockedBatchWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    /// Counts lazily generated payload entries, excluding project metadata.
    public func readCount() -> Int { payloadReads }

    /// Called by the harness's synchronous cancellation handler. The blocked
    /// I/O remains blocked until the test releases it, then observes the flag.
    nonisolated func requestCancellation() {
        cancellation.request()
    }

    public func children(of url: URL) async throws -> [FileEntry] {
        switch url.standardizedFileURL.path {
        case Self.root.path:
            return [directory(Self.project, inode: 2)]
        case Self.project.path:
            return [
                file(Self.project.appendingPathComponent("package.json"), inode: 3, bytes: 14),
                directory(Self.modules, inode: 4),
            ]
        case Self.modules.path:
            return [directory(batchURL(0), inode: 1_000)]
        default:
            guard let index = batchIndex(for: url) else { return [] }
            try await blockSecondBatchIfNeeded(index: index)
            return payloadEntries(in: url, batch: index)
        }
    }

    public func entry(at url: URL) async throws -> FileEntry {
        switch url.standardizedFileURL.path {
        case Self.root.path:
            return directory(Self.root, inode: 1)
        case Self.project.path:
            return directory(Self.project, inode: 2)
        case Self.modules.path:
            return directory(Self.modules, inode: 4)
        case Self.project.appendingPathComponent("package.json").path:
            return file(url, inode: 3, bytes: 14)
        default:
            throw PolicyError.missing
        }
    }

    public func readPrefix(at url: URL, limit: Int) async throws -> Data {
        guard url.lastPathComponent == "package.json" else { throw PolicyError.missing }
        return Data("{\"name\":\"app\"}".utf8)
    }

    private var batchCount: Int {
        (count + Self.batchSize - 1) / Self.batchSize
    }

    private func batchURL(_ index: Int) -> URL {
        Self.modules.appendingPathComponent("batch-\(index)")
    }

    private func batchIndex(for url: URL) -> Int? {
        guard
            url.deletingLastPathComponent().standardizedFileURL.path
                == Self.modules.standardizedFileURL.path,
            let value = Int(url.lastPathComponent.dropFirst("batch-".count)),
            (0..<batchCount).contains(value)
        else { return nil }
        return value
    }

    private func blockSecondBatchIfNeeded(index: Int) async throws {
        guard index == 1, !blockedBatchReleased else { return }
        await withCheckedContinuation { blockedBatchWaiters.append($0) }
        if cancellation.isRequested { throw CancellationError() }
    }

    private func payloadEntries(in url: URL, batch index: Int) -> [FileEntry] {
        let start = index * Self.batchSize
        let end = min(start + Self.batchSize, count)
        guard start < end else { return [] }

        payloadReads += end - start
        if index == 0 {
            firstBatchRead = true
            let waiters = firstBatchWaiters
            firstBatchWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }

        var entries = (start..<end).map { offset in
            file(
                url.appendingPathComponent("entry-\(offset).bin"),
                inode: UInt64(100_000 + offset),
                bytes: 16
            )
        }
        if index + 1 < batchCount {
            entries.append(directory(batchURL(index + 1), inode: UInt64(1_000 + index + 1)))
        }
        return entries
    }

    private func directory(_ url: URL, inode: UInt64) -> FileEntry {
        FileEntry(
            url: url,
            kind: .directory,
            identity: FileIdentity(device: 1, inode: inode, modifiedNanoseconds: 0),
            logicalBytes: 0,
            allocatedBytes: 0,
            isMount: false,
            isCloudPlaceholder: false
        )
    }

    private func file(_ url: URL, inode: UInt64, bytes: UInt64) -> FileEntry {
        FileEntry(
            url: url,
            kind: .file,
            identity: FileIdentity(device: 1, inode: inode, modifiedNanoseconds: 0),
            logicalBytes: bytes,
            allocatedBytes: bytes,
            isMount: false,
            isCloudPlaceholder: false
        )
    }
}

private final class SyntheticScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var requested = false

    func request() {
        lock.lock()
        requested = true
        lock.unlock()
    }

    var isRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return requested
    }
}
