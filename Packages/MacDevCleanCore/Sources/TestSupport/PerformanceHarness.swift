import CleanupRules
import Domain
import Foundation
import Scanning

public struct PerformanceRun: Sendable {
    public let task: Task<Void, Never>

    public init(task: Task<Void, Never>) {
        self.task = task
    }
}

/// Starts the production scanner over a synthetic, valid Node project.
public enum PerformanceHarness {
    public static func start(files: SyntheticFileSystem) async throws -> PerformanceRun {
        let context = MemoryContext(
            value: SafetyContext(
                home: URL(fileURLWithPath: "/synthetic"),
                projectRoots: [SyntheticFileSystem.root],
                largeFileRoots: [],
                globalRuleRoots: [:],
                exclusions: [],
                revision: 1
            )
        )
        let scanner = DeveloperScanner(
            files: files,
            catalog: RuleCatalog(),
            git: FakeGitStatus(),
            context: context,
            store: InMemoryCandidateStore()
        )
        let request = ScanRequest(
            roots: [ScanRoot(url: SyntheticFileSystem.root)],
            includeGlobalCaches: false
        )

        return PerformanceRun(
            task: Task {
                await withTaskCancellationHandler {
                    do {
                        for try await _ in scanner.scan(request) {}
                    } catch is CancellationError {
                        // The regression intentionally cancels this task.
                    } catch {
                        // The fixture has no expected failures; preserving the
                        // task's non-throwing interface keeps it easy to use.
                    }
                } onCancel: {
                    files.requestCancellation()
                }
            })
    }
}
