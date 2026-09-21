import Domain
import Foundation

/// Finds project directories under an approved root.
///
/// A project is a directory holding a manifest the catalog understands. The
/// walk deliberately does not descend into generated artifacts, so
/// `node_modules` inside `node_modules` is never mistaken for a project, and a
/// dependency tree with thousands of nested manifests costs nothing to skip.
///
/// Monorepos still work: the walk continues past a project directory to find
/// packages nested inside it.
public struct ProjectDiscovery: Sendable {
    /// Files that mark a directory as a project the catalog can reason about.
    static let manifestNames = ["package.json", "pubspec.yaml"]

    /// Directories the walk never enters. These are generated output, version
    /// control metadata or dependency trees.
    static let skippedDirectoryNames: Set<String> = [
        "node_modules", ".git", ".dart_tool", "build", "dist", ".turbo", ".build",
        "DerivedData", "Pods", ".next", ".nuxt", ".svelte-kit", ".gradle", ".venv",
        "vendor", "Carthage", ".cache",
    ]

    /// Package-like directories macOS presents as single documents. Walking
    /// into one treats an application or a project file as a folder.
    static let bundleExtensions: Set<String> = [
        "app", "framework", "bundle", "xcodeproj", "xcworkspace", "playground",
        "photoslibrary", "musiclibrary", "tvlibrary", "fcpbundle", "sparsebundle",
        "docset", "kext", "plugin", "appex", "xcassets",
    ]

    private let files: any FileSystemClient
    private let maximumDepth: Int

    public init(files: any FileSystemClient, maximumDepth: Int = 12) {
        self.files = files
        self.maximumDepth = maximumDepth
    }

    /// A subtree that could not be read, reported rather than swallowed.
    public struct DiscoveryIssue: Sendable, Equatable {
        public let code: String
        public let url: URL

        public init(code: String, url: URL) {
            self.code = code
            self.url = url
        }
    }

    public struct DiscoveryResult: Sendable {
        public let projects: [URL]
        public let issues: [DiscoveryIssue]
        /// Directory entries looked at, for progress reporting.
        public let visited: Int
    }

    public func projects(in root: URL) async throws -> [URL] {
        try await discover(in: root).projects
    }

    public func discover(in root: URL) async throws -> DiscoveryResult {
        var found: [URL] = []
        var issues: [DiscoveryIssue] = []
        var visited = 0
        var pending: [(url: URL, depth: Int)] = [(root, 0)]

        while let current = pending.popLast() {
            try Task.checkCancellation()

            let children: [FileEntry]
            do {
                children = try await files.children(of: current.url)
            } catch {
                // An unreadable subtree is not fatal: everything else the root
                // contains still counts. It is reported, never hidden.
                issues.append(
                    DiscoveryIssue(code: Self.issueCode(for: error), url: current.url)
                )
                continue
            }
            visited += children.count

            if children.contains(where: { Self.isManifest($0) }) {
                found.append(current.url)
            }

            guard current.depth < maximumDepth else { continue }

            for child in children where Self.isWalkable(child) {
                pending.append((child.url, current.depth + 1))
            }
        }

        return DiscoveryResult(
            projects: found.sorted { $0.path < $1.path },
            issues: issues,
            visited: visited
        )
    }

    static func issueCode(for error: any Error) -> String {
        switch error {
        case PolicyError.permissionDenied: return ScanIssueCode.permissionDenied
        default: return ScanIssueCode.unreadable
        }
    }

    static func isManifest(_ entry: FileEntry) -> Bool {
        entry.kind == .file && manifestNames.contains(entry.url.lastPathComponent)
    }

    static func isWalkable(_ entry: FileEntry) -> Bool {
        guard entry.kind == .directory else { return false }
        // Links are never followed, another volume is never entered, and a
        // cloud placeholder is never materialised.
        guard !entry.isMount, !entry.isCloudPlaceholder else { return false }
        let name = entry.url.lastPathComponent
        guard !skippedDirectoryNames.contains(name) else { return false }
        guard !bundleExtensions.contains(entry.url.pathExtension.lowercased()) else { return false }
        return true
    }
}
