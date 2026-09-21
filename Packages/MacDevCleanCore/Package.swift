// swift-tools-version: 6.0
import PackageDescription

// Dependency direction always points inward toward Domain. Domain imports only
// Foundation. TestSupport is a test-support target and is never a production
// dependency of the application.
//
// Core targets stay nonisolated: the Swift 6 language mode's default actor
// isolation is nonisolated, and no core target opts into MainActor isolation.
// Only the application layer uses explicit @MainActor.

let coreSettings: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "MacDevCleanCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "MacDevCleanCore",
            targets: [
                "Domain", "CleanupRules", "Scanning",
                "Cleanup", "DockerIntegration", "Persistence",
            ]
        ),
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "CleanupRules", targets: ["CleanupRules"]),
        .library(name: "Scanning", targets: ["Scanning"]),
        .library(name: "Cleanup", targets: ["Cleanup"]),
        .library(name: "DockerIntegration", targets: ["DockerIntegration"]),
        .library(name: "Persistence", targets: ["Persistence"]),
    ],
    targets: [
        .target(name: "Domain", swiftSettings: coreSettings),
        .target(name: "CleanupRules", dependencies: ["Domain"], swiftSettings: coreSettings),
        .target(name: "Scanning", dependencies: ["Domain", "CleanupRules"], swiftSettings: coreSettings),
        .target(name: "Cleanup", dependencies: ["Domain"], swiftSettings: coreSettings),
        .target(name: "DockerIntegration", dependencies: ["Domain"], swiftSettings: coreSettings),
        .target(name: "Persistence", dependencies: ["Domain"], swiftSettings: coreSettings),

        // Test-support only. No production target may depend on this.
        .target(
            name: "TestSupport",
            dependencies: ["Domain", "CleanupRules", "Scanning", "Cleanup"],
            swiftSettings: coreSettings
        ),

        .testTarget(name: "DomainTests", dependencies: ["Domain"], swiftSettings: coreSettings),
        .testTarget(
            name: "ScanningTests",
            dependencies: ["Scanning", "Domain", "TestSupport"],
            swiftSettings: coreSettings
        ),
        .testTarget(
            name: "CleanupTests",
            dependencies: ["Cleanup", "Domain", "TestSupport"],
            // Type-checked by scripts/check-token-access.sh against the built
            // modules, deliberately not compiled as part of any target.
            exclude: ["CompileFailures"],
            swiftSettings: coreSettings
        ),
        .testTarget(
            name: "DockerIntegrationTests",
            dependencies: ["DockerIntegration", "Domain", "TestSupport"],
            resources: [.copy("Fixtures")],
            swiftSettings: coreSettings
        ),
        .testTarget(
            name: "CleanupRulesTests",
            dependencies: ["CleanupRules", "Scanning", "Domain", "TestSupport"],
            swiftSettings: coreSettings
        ),
        .testTarget(
            name: "TestSupportTests",
            dependencies: ["TestSupport", "Domain"],
            swiftSettings: coreSettings
        ),
    ]
)
