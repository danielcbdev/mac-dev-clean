import Domain
import Foundation

/// One registered global cache location set.
///
/// A global rule is an allowlist entry, not a search. It names exact
/// home-relative locations; nothing discovers cache directories by pattern, and
/// nothing asks a tool where its cache lives by running it.
public struct GlobalCacheRule: Sendable, Equatable {
    public let id: CleanupRuleID
    /// Home-relative locations, in the order they are offered.
    public let relativePaths: [String]
    public let category: CleanupCategory
    public let risk: RiskLevel
    public let consequenceKey: String

    public init(
        id: CleanupRuleID,
        relativePaths: [String],
        category: CleanupCategory,
        risk: RiskLevel,
        consequenceKey: String
    ) {
        self.id = id
        self.relativePaths = relativePaths
        self.category = category
        self.risk = risk
        self.consequenceKey = consequenceKey
    }
}

/// The complete global cache allowlist.
///
/// Deliberately absent, and not an oversight:
///
/// - `~/.gradle` as a whole — it holds wrapper distributions and user settings,
///   not only caches. Only `~/.gradle/caches` is listed.
/// - `~/.cargo/bin` and other installed binaries — removing them uninstalls
///   tools rather than freeing a cache.
/// - Homebrew's Cellar — that is the installation, not the download cache.
/// - `CoreSimulator/Devices` — simulator device data is user state, including
///   installed apps and their databases.
/// - SDKs, Android emulator images and toolchains — expensive to replace and
///   not caches.
///
/// Custom cache locations require an explicit choice in Settings. MacDevClean
/// never runs a login shell or a tool to discover where a cache lives.
public enum GlobalCacheRules {
    public static let all: [GlobalCacheRule] = [
        GlobalCacheRule(
            id: "dart.hosted",
            relativePaths: [".pub-cache/hosted"],
            category: .flutter,
            risk: .low,
            consequenceKey: ConsequenceKey.refetchPackages
        ),
        GlobalCacheRule(
            id: "npm.cache",
            relativePaths: [".npm/_cacache"],
            category: .node,
            risk: .low,
            consequenceKey: ConsequenceKey.refetchPackages
        ),
        GlobalCacheRule(
            id: "yarn.cache",
            relativePaths: [".cache/yarn", "Library/Caches/Yarn"],
            category: .yarn,
            risk: .low,
            consequenceKey: ConsequenceKey.refetchPackages
        ),
        GlobalCacheRule(
            id: "pnpm.store",
            relativePaths: ["Library/pnpm/store", "Library/Caches/pnpm"],
            category: .pnpm,
            risk: .low,
            consequenceKey: ConsequenceKey.refetchPackages
        ),
        GlobalCacheRule(
            id: "bun.cache",
            relativePaths: [".bun/install/cache"],
            category: .bun,
            risk: .low,
            consequenceKey: ConsequenceKey.refetchPackages
        ),
        GlobalCacheRule(
            id: "gradle.cache",
            relativePaths: [".gradle/caches"],
            category: .gradle,
            risk: .low,
            consequenceKey: ConsequenceKey.rebuildSlowerNextTime
        ),
        GlobalCacheRule(
            id: "pip.cache",
            relativePaths: ["Library/Caches/pip", ".cache/pip"],
            category: .python,
            risk: .low,
            consequenceKey: ConsequenceKey.refetchPackages
        ),
        GlobalCacheRule(
            id: "cargo.registry",
            relativePaths: [".cargo/registry"],
            category: .rust,
            risk: .low,
            consequenceKey: ConsequenceKey.refetchPackages
        ),
        GlobalCacheRule(
            id: "cargo.git",
            relativePaths: [".cargo/git"],
            category: .rust,
            risk: .low,
            consequenceKey: ConsequenceKey.refetchPackages
        ),
        GlobalCacheRule(
            id: "brew.cache",
            relativePaths: ["Library/Caches/Homebrew"],
            category: .homebrew,
            risk: .low,
            consequenceKey: ConsequenceKey.redownloadTooling
        ),
        GlobalCacheRule(
            id: "pods.cache",
            relativePaths: ["Library/Caches/CocoaPods"],
            category: .cocoaPods,
            risk: .low,
            consequenceKey: ConsequenceKey.refetchPackages
        ),
        GlobalCacheRule(
            id: "xcode.derived",
            relativePaths: ["Library/Developer/Xcode/DerivedData"],
            category: .xcode,
            risk: .low,
            consequenceKey: ConsequenceKey.rebuildSlowerNextTime
        ),
        GlobalCacheRule(
            id: "xcode.archives",
            relativePaths: ["Library/Developer/Xcode/Archives"],
            category: .xcode,
            // Archives can hold the only copy of a shipped build and its
            // symbols. Nothing regenerates them.
            risk: .high,
            consequenceKey: ConsequenceKey.loseArchivedBuilds
        ),
        GlobalCacheRule(
            id: "xcode.devices",
            relativePaths: ["Library/Developer/Xcode/iOS DeviceSupport"],
            category: .xcode,
            risk: .medium,
            consequenceKey: ConsequenceKey.reprocessDeviceSupport
        ),
        GlobalCacheRule(
            id: "simulator.cache",
            relativePaths: ["Library/Developer/CoreSimulator/Caches"],
            category: .simulator,
            risk: .low,
            consequenceKey: ConsequenceKey.rebuildSlowerNextTime
        ),
    ]

    public static let byID: [CleanupRuleID: GlobalCacheRule] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )
}
