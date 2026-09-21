import Foundation

/// The composition root.
///
/// The application constructs every concrete service here. Views receive
/// protocols or feature models; they never build scanners, repositories,
/// `FileManager` or `Process` themselves.
///
/// Services are added by the plan that introduces them. At the foundation
/// milestone this only carries the launch environment, so the shell can be
/// verified end to end before any service exists. It is deliberately a
/// `Sendable` value with no actor isolation: the core service protocols it will
/// hold are `Sendable`, and only the feature models above it are `@MainActor`.
struct AppDependencies: Sendable, Equatable {
    /// True when the process was launched by an automated UI test.
    ///
    /// UI tests select fake destructive adapters through this flag. It is read
    /// from the launch arguments only, never from a persisted setting, and the
    /// fake adapters it selects are compiled in DEBUG only so they cannot reach
    /// a shipping binary.
    let isUITesting: Bool

    static func live(arguments: [String] = CommandLine.arguments) -> AppDependencies {
        AppDependencies(isUITesting: arguments.contains("--ui-testing"))
    }
}
