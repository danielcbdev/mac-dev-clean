import Domain
import Foundation

/// Decides whether one path may be cleaned under one rule and one scope.
///
/// Comparison is component-wise after canonicalisation, never
/// `path.hasPrefix(root.path)`: `/work/application` is not inside `/work/app`,
/// and a string prefix cannot tell the difference. Volume identity and the
/// volume's case behaviour are both taken into account.
///
/// This type answers questions about *paths*. Category exclusions are applied
/// by the callers that know a candidate's category — the scanner and the
/// cleanup validator — because `check` is given a rule identifier, not a
/// category.
public struct PathPolicy: PathPolicyChecking {
    private let files: any FileSystemClient

    public init(files: any FileSystemClient) {
        self.files = files
    }

    /// Absolute locations whose descendants are all off limits.
    private static let protectedSubtrees = ["/System", "/Library", "/Applications"]

    /// Absolute locations protected as whole directories, while their
    /// descendants may still be eligible.
    private static let protectedDirectories = ["/", "/Users", "/Volumes", "/private", "/var"]

    public func check(
        _ url: URL,
        ruleID: CleanupRuleID,
        context: SafetyContext
    ) async throws {
        let scope = try Self.scope(for: ruleID, context: context)

        // Read the target as it is on disk before resolving anything, so a
        // symbolic link is seen as a link rather than as its destination.
        let entry = try await files.entry(at: url)
        guard entry.kind != .symbolicLink else { throw PolicyError.symbolicLink }
        guard !entry.isMount else { throw PolicyError.protectedPath }
        guard !entry.isCloudPlaceholder else { throw PolicyError.unsupported }

        let target = Self.canonical(url)
        let caseSensitive = Self.volumeIsCaseSensitive(url)

        try Self.rejectProtectedLocations(
            target,
            context: context,
            caseSensitive: caseSensitive
        )

        let allowedRoot = try Self.allowedRoot(
            for: target,
            scope: scope,
            caseSensitive: caseSensitive
        )

        try await verifyAncestry(from: allowedRoot, to: target, target: entry)

        try await rejectExclusions(target, ruleID: ruleID, context: context)
    }

    public func matches(_ url: URL, exclusion: URL) async throws -> Bool {
        let candidate = Self.canonical(url)
        let excluded = Self.canonical(exclusion)
        let caseSensitive =
            Self.volumeIsCaseSensitive(url) && Self.volumeIsCaseSensitive(exclusion)

        // Different volumes cannot contain one another, whatever the paths look
        // like. Only decide this when both really exist.
        if let left = try? await files.entry(at: url),
            let right = try? await files.entry(at: exclusion),
            left.identity.device != right.identity.device
        {
            return false
        }

        let a = Self.components(candidate, caseSensitive: caseSensitive)
        let b = Self.components(excluded, caseSensitive: caseSensitive)

        // Equal, the exclusion is an ancestor, or the exclusion sits inside the
        // candidate. The last case matters: cleaning the candidate as a whole
        // would take the excluded child with it.
        return a == b
            || Self.componentDescendant(a, of: b)
            || Self.componentDescendant(b, of: a)
    }

    // MARK: - Scope

    private enum Scope {
        case project([URL])
        case largeFile([URL])
        case globalCache([URL])
    }

    private static func scope(
        for ruleID: CleanupRuleID,
        context: SafetyContext
    ) throws -> Scope {
        if let roots = context.globalRuleRoots[ruleID] {
            return .globalCache(roots)
        }
        if ruleID == manualLargeFileRuleID {
            return .largeFile(context.largeFileRoots)
        }
        guard projectRuleIDs.contains(ruleID) else {
            // An identifier nobody registered cannot be used to widen scope.
            throw PolicyError.unsupported
        }
        return .project(context.projectRoots)
    }

    private static func allowedRoot(
        for target: URL,
        scope: Scope,
        caseSensitive: Bool
    ) throws -> URL {
        let targetComponents = components(target, caseSensitive: caseSensitive)

        switch scope {
        case .globalCache(let roots):
            // A global cache rule accepts its exact registered location, or
            // something inside it — nothing else.
            for root in roots {
                let rootComponents = components(canonical(root), caseSensitive: caseSensitive)
                if targetComponents == rootComponents
                    || componentDescendant(targetComponents, of: rootComponents)
                {
                    return canonical(root)
                }
            }
        case .project(let roots), .largeFile(let roots):
            // Project artifacts and user-selected files must be strictly inside
            // their root; the root itself is never a candidate.
            for root in roots {
                let rootComponents = components(canonical(root), caseSensitive: caseSensitive)
                if componentDescendant(targetComponents, of: rootComponents) {
                    return canonical(root)
                }
            }
        }

        throw PolicyError.outsideScope
    }

    // MARK: - Protected locations

    private static func rejectProtectedLocations(
        _ target: URL,
        context: SafetyContext,
        caseSensitive: Bool
    ) throws {
        let targetComponents = components(target, caseSensitive: caseSensitive)

        for subtree in protectedSubtrees {
            let root = components(
                canonical(URL(fileURLWithPath: subtree)),
                caseSensitive: caseSensitive
            )
            if targetComponents == root || componentDescendant(targetComponents, of: root) {
                throw PolicyError.protectedPath
            }
        }

        for directory in protectedDirectories {
            let root = components(
                canonical(URL(fileURLWithPath: directory)),
                caseSensitive: caseSensitive
            )
            if targetComponents == root { throw PolicyError.protectedPath }
        }

        // The user's home as a whole, and the root of any mounted volume.
        let home = components(canonical(context.home), caseSensitive: caseSensitive)
        if targetComponents == home { throw PolicyError.protectedPath }

        let volumes = components(
            canonical(URL(fileURLWithPath: "/Volumes")),
            caseSensitive: caseSensitive
        )
        if targetComponents.count == volumes.count + 1,
            componentDescendant(targetComponents, of: volumes)
        {
            throw PolicyError.protectedPath
        }

        // A configured project root, and everything above it, is structure the
        // user owns. It can hold candidates; it can never be one.
        for projectRoot in context.projectRoots {
            let root = components(canonical(projectRoot), caseSensitive: caseSensitive)
            if targetComponents == root || componentDescendant(root, of: targetComponents) {
                throw PolicyError.protectedPath
            }
        }
    }

    // MARK: - Ancestry

    /// Walks every directory between the allowed root and the target.
    ///
    /// Canonicalisation already defeats a symlinked ancestor by moving the path
    /// out of scope, but this second pass also rejects a mount point appearing
    /// mid-path and a target that has crossed onto another volume.
    private func verifyAncestry(from root: URL, to target: URL, target entry: FileEntry)
        async throws
    {
        var chain: [URL] = []
        var cursor = target
        let rootPath = root.standardizedFileURL.path

        while cursor.standardizedFileURL.path != rootPath {
            let parent = cursor.deletingLastPathComponent()
            if parent.standardizedFileURL.path == cursor.standardizedFileURL.path { break }
            cursor = parent
            if cursor.standardizedFileURL.path == rootPath { break }
            chain.append(cursor)
        }

        for ancestor in chain {
            let info = try await files.entry(at: ancestor)
            guard info.kind == .directory else { throw PolicyError.outsideScope }
            guard !info.isMount else { throw PolicyError.protectedPath }
            guard info.identity.device == entry.identity.device else {
                throw PolicyError.outsideScope
            }
        }
    }

    // MARK: - Exclusions

    private func rejectExclusions(
        _ target: URL,
        ruleID: CleanupRuleID,
        context: SafetyContext
    ) async throws {
        for exclusion in context.exclusions {
            switch exclusion {
            case .rule(let excludedRule):
                if excludedRule == ruleID { throw PolicyError.excluded }
            case .path(let excludedPath):
                if try await matches(target, exclusion: excludedPath) {
                    throw PolicyError.excluded
                }
            case .category:
                // Applied by the caller that knows the candidate's category.
                continue
            }
        }
    }

    // MARK: - Path arithmetic

    /// True when `candidate` is strictly inside `root`.
    static func componentDescendant(_ candidate: [String], of root: [String]) -> Bool {
        candidate.count > root.count && Array(candidate.prefix(root.count)) == root
    }

    /// Standardises the path and resolves symbolic links, which also collapses
    /// the `/var`, `/tmp` and `/etc` aliases onto their `/private` originals.
    ///
    /// Resolution here is for comparison only. Recursive scanning never follows
    /// a link.
    static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func components(_ url: URL, caseSensitive: Bool) -> [String] {
        let raw = url.pathComponents
        return caseSensitive ? raw : raw.map { $0.lowercased() }
    }

    /// Defaults to case-insensitive when the volume cannot be asked, because
    /// treating more paths as equal protects more, never less.
    private static func volumeIsCaseSensitive(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?
            .volumeSupportsCaseSensitiveNames ?? false
    }
}
