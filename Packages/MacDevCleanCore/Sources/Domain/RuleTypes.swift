import Foundation

/// Rule identifier for a file the user picked in Large Files.
///
/// It is not a catalog rule: nothing detects it, and it is only valid for a
/// path inside a folder the user explicitly selected for that feature.
public let manualLargeFileRuleID: CleanupRuleID = "manual.largeFile"

/// The project-artifact rules the catalog can produce.
///
/// The set is fixed and shared: path policy uses it to reject an identifier it
/// does not recognise, so a caller cannot invent a rule name to widen scope.
public let projectRuleIDs: Set<CleanupRuleID> = [
    "node.modules",
    "node.turbo",
    "web.dist",
    "flutter.build",
    "flutter.dartTool",
    "flutter.plugins",
    "flutter.pluginDependencies",
]

/// The most an evidence file may weigh before it is refused outright.
///
/// A manifest is a few kilobytes. Anything past this is not something to parse
/// hopefully; the artifact is reported as unsupported instead.
public let maximumEvidenceBytes = 256 * 1024

/// Codes for problems that do not stop a scan.
///
/// They are localisation keys, not messages, and they never carry a path,
/// command output or environment detail.
public enum ScanIssueCode {
    /// A subtree could not be read. Everything else in the scan still counts.
    public static let permissionDenied = "issue.permissionDenied"
    /// A subtree could not be read for a reason other than permissions.
    public static let unreadable = "issue.unreadable"
    /// The item exists but its size could not be measured. It stays visible and
    /// stays out of every total.
    public static let sizeUnavailable = "issue.sizeUnavailable"
    /// Byte totals exceeded what can be represented, so the total is unknown
    /// rather than wrapped around.
    public static let sizeOverflow = "issue.sizeOverflow"
    /// The directory matches a known artifact name but the evidence required to
    /// call it disposable is missing. Shown for manual review, never as a
    /// cleanup candidate.
    public static let ambiguousArtifact = "issue.ambiguousArtifact"
    /// Git metadata could not be read, so an ambiguous artifact was skipped.
    public static let gitUnavailable = "issue.gitUnavailable"
    /// The entry is a symbolic link. It is never traversed and never cleaned.
    public static let symbolicLinkSkipped = "issue.symbolicLinkSkipped"
    /// The entry is the root of another volume. Scanning stops there.
    public static let mountSkipped = "issue.mountSkipped"
    /// The file's data lives in a cloud provider. Measuring it would download
    /// it, so it is left alone.
    public static let cloudPlaceholderSkipped = "issue.cloudPlaceholderSkipped"
}

/// Localisation keys for the consequence copy shown before cleanup.
public enum ConsequenceKey {
    public static let reinstallDependencies = "impact.reinstallDependencies"
    public static let rebuildOutput = "impact.rebuildOutput"
    public static let redeployArtifact = "impact.redeployArtifact"
    public static let refetchPackages = "impact.refetchPackages"
    public static let rebuildSlowerNextTime = "impact.rebuildSlowerNextTime"
    public static let redownloadTooling = "impact.redownloadTooling"
    public static let loseArchivedBuilds = "impact.loseArchivedBuilds"
    public static let reprocessDeviceSupport = "impact.reprocessDeviceSupport"
    public static let userSelectedFile = "impact.userSelectedFile"
}
