import Foundation

public enum FixtureTreeError: Error, Equatable {
    /// The relative path was absolute, empty, or contained a `..` component.
    case invalidRelativePath
    /// `close()` was asked to remove a directory this tree does not own.
    case notAnOwnedTemporaryRoot
}

/// A synthetic directory tree that a test owns outright.
///
/// Every fixture lives inside a unique temporary directory created by this
/// type. Relative paths are validated so a test cannot accidentally reach
/// outside that directory, and `close()` refuses to remove anything it did not
/// create. Tests never operate on the user's real files.
///
/// `removeItem` here is deliberate and confined to test support: it deletes
/// only this tree's own temporary root. Production cleanup uses the Trash.
public final class FixtureTree {
    private static let prefix = "macdevclean-fixture-"

    /// The owned temporary directory. Everything this tree creates is inside it.
    public let root: URL

    private var isClosed = false

    public init() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .resolvingSymlinksInPath()
        let candidate = base.appendingPathComponent(
            Self.prefix + UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: candidate,
            withIntermediateDirectories: false
        )
        // Resolve after creation so comparisons against enumerated paths agree
        // on macOS, where the temporary directory is itself a symlink.
        root = candidate.resolvingSymlinksInPath()
    }

    /// Creates a directory, and any missing parents, at a validated relative path.
    @discardableResult
    public func directory(_ relativePath: String) throws -> URL {
        let url = try resolve(relativePath)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    /// Creates a file of exactly `bytes` length, creating parent directories.
    @discardableResult
    public func file(_ relativePath: String, bytes: Int) throws -> URL {
        let url = try resolve(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard bytes > 0 else { return url }

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let chunkSize = 64 * 1024
        var remaining = bytes
        let chunk = Data(repeating: 0x41, count: min(chunkSize, remaining))
        while remaining > 0 {
            let count = min(chunkSize, remaining)
            try handle.write(contentsOf: count == chunk.count ? chunk : chunk.prefix(count))
            remaining -= count
        }
        return url
    }

    /// Creates a symbolic link at a validated relative path. The destination is
    /// not required to exist; scanning must never follow it.
    @discardableResult
    public func symlink(_ relativePath: String, to target: URL) throws -> URL {
        let url = try resolve(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        return url
    }

    /// Removes the owned temporary root. Calling it twice is harmless.
    public func close() throws {
        guard !isClosed else { return }
        guard isOwnedTemporaryRoot(root) else {
            throw FixtureTreeError.notAnOwnedTemporaryRoot
        }
        isClosed = true
        try FileManager.default.removeItem(at: root)
    }

    // MARK: - Validation

    private func resolve(_ relativePath: String) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        guard !relativePath.isEmpty,
            !relativePath.hasPrefix("/"),
            !components.isEmpty,
            !components.contains("..")
        else {
            throw FixtureTreeError.invalidRelativePath
        }
        return components.reduce(root) { $0.appendingPathComponent(String($1)) }
    }

    private func isOwnedTemporaryRoot(_ url: URL) -> Bool {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .resolvingSymlinksInPath()
        return url.deletingLastPathComponent().standardizedFileURL == base.standardizedFileURL
            && url.lastPathComponent.hasPrefix(Self.prefix)
    }
}
