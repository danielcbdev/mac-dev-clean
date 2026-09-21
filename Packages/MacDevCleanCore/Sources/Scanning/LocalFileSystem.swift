import Domain
import Foundation

/// Read-only filesystem access backed by `lstat`.
///
/// Every call hops onto one bounded utility queue, so no filesystem work ever
/// runs on the main actor, and cancellation is checked on both sides of the
/// hop. Nothing here writes, moves or deletes: the only removal mechanism in
/// this product is the Trash port in `Domain`.
public struct LocalFileSystem: FileSystemClient {
    private let queue: DispatchQueue

    public init() {
        queue = DispatchQueue(
            label: "dev.macdevclean.filesystem",
            qos: .utility,
            autoreleaseFrequency: .workItem
        )
    }

    public func children(of url: URL) async throws -> [FileEntry] {
        try await run {
            let directory = try Self.metadata(at: url, parentDevice: nil)
            guard directory.kind == .directory else { throw PolicyError.unsupported }

            let names: [String]
            do {
                names = try FileManager.default.contentsOfDirectory(atPath: url.path)
            } catch let error as NSError {
                throw Self.translate(error)
            }

            // Sorted so a traversal over the same tree visits in the same order
            // every time, which keeps scan results and tests deterministic.
            return try names.sorted().map { name in
                try Self.metadata(
                    at: url.appendingPathComponent(name),
                    parentDevice: directory.identity.device
                )
            }
        }
    }

    public func entry(at url: URL) async throws -> FileEntry {
        try await run {
            let parent = url.deletingLastPathComponent()
            // A missing or unreadable parent is not fatal here: without it the
            // entry simply is not reported as a mount point, and the caller's
            // ancestor walk catches the problem separately.
            let parentDevice = try? Self.metadata(at: parent, parentDevice: nil).identity.device
            return try Self.metadata(at: url, parentDevice: parentDevice)
        }
    }

    public func readPrefix(at url: URL, limit: Int) async throws -> Data {
        try await run {
            let entry = try Self.metadata(at: url, parentDevice: nil)
            guard entry.kind == .file else { throw PolicyError.unsupported }
            guard let size = entry.logicalBytes, size <= UInt64(limit) else {
                // Evidence files are small by nature. Something larger is not
                // parsed hopefully; it is refused.
                throw PolicyError.unsupported
            }

            guard let handle = FileHandle(forReadingAtPath: url.path) else {
                throw PolicyError.permissionDenied
            }
            defer { try? handle.close() }
            do {
                return try handle.read(upToCount: limit) ?? Data()
            } catch let error as NSError {
                throw Self.translate(error)
            }
        }
    }

    // MARK: - Queue hop

    private func run<T: Sendable>(
        _ work: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try Task.checkCancellation()
        let value = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<T, Error>) in
            queue.async {
                continuation.resume(with: Result { try work() })
            }
        }
        try Task.checkCancellation()
        return value
    }

    // MARK: - Metadata

    /// `SF_DATALESS`: the file is a cloud placeholder whose data is not on this
    /// disk. Reading or measuring it would make the provider download it, which
    /// is exactly what a disk-cleanup tool must not do.
    private static let datalessFlag: UInt32 = 0x4000_0000

    private static func metadata(at url: URL, parentDevice: UInt64?) throws -> FileEntry {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw translate(errno: errno)
        }

        let kind: EntryKind
        switch info.st_mode & S_IFMT {
        case S_IFDIR: kind = .directory
        case S_IFREG: kind = .file
        case S_IFLNK: kind = .symbolicLink
        default: kind = .other
        }

        let device = UInt64(info.st_dev)
        let identity = FileIdentity(
            device: device,
            inode: UInt64(info.st_ino),
            modifiedNanoseconds: Int64(info.st_mtimespec.tv_sec) * 1_000_000_000
                + Int64(info.st_mtimespec.tv_nsec)
        )

        let isCloudPlaceholder = (info.st_flags & datalessFlag) != 0
        // A different device from the parent directory means this entry is
        // where another volume is mounted.
        let isMount = parentDevice.map { $0 != device } ?? false

        return FileEntry(
            // One canonical spelling. `appendingPathComponent` stats the path
            // and adds a trailing slash for directories, so the same location
            // can otherwise arrive with two different URLs that do not compare
            // equal. Directory-ness is carried by `kind`, not by the URL.
            url: URL(fileURLWithPath: url.path, isDirectory: false),
            kind: kind,
            identity: identity,
            logicalBytes: info.st_size >= 0 ? UInt64(info.st_size) : nil,
            allocatedBytes: info.st_blocks >= 0 ? UInt64(info.st_blocks) * 512 : nil,
            isMount: isMount,
            isCloudPlaceholder: isCloudPlaceholder
        )
    }

    private static func translate(errno code: Int32) -> PolicyError {
        switch code {
        case ENOENT, ENOTDIR: return .missing
        case EACCES, EPERM: return .permissionDenied
        default: return .unavailable
        }
    }

    private static func translate(_ error: NSError) -> PolicyError {
        switch error.code {
        case NSFileReadNoSuchFileError, NSFileNoSuchFileError: return .missing
        case NSFileReadNoPermissionError: return .permissionDenied
        default: return .unavailable
        }
    }
}
