import Cleanup
import CleanupRules
import DockerIntegration
import Domain
import Foundation
import Persistence
import Scanning

/// The composition root.
///
/// Every concrete service is built here. Views receive feature models or
/// protocols; they never construct a scanner, a repository, a `FileManager` or
/// a `Process` themselves.
@MainActor
struct AppDependencies {
    let scanner: any ScanService
    let largeFileScanner: any LargeFileScanning
    let validator: any CleanupPlanValidating
    let executor: any CleanupExecuting
    let settings: any SettingsRepository
    let history: any HistoryRepository
    let store: any CandidateStore
    let context: AppSafetyContextProvider
    let picker: any FolderPicking
    let workspace: any WorkspaceOpening
    /// The home directory this launch reasons about. A fixture launch points it
    /// at a temporary tree, so automation never proposes the user's real
    /// folders or reads their real caches.
    let home: URL

    /// False until a durable journal exists.
    ///
    /// A cleanup whose record disappears when the app quits is not something to
    /// offer: the user would have no way to see what happened. Until plan 07
    /// composes SwiftData, the release build scans and explains but the cleanup
    /// action reports itself unavailable.
    let cleanupEnabled: Bool

    /// True when the process was launched by automated UI tests.
    let isUITesting: Bool

    /// Set when durable storage could not be opened. The store on disk is left
    /// exactly as it is — never deleted, never recreated — cleanup is disabled,
    /// and the interface says why.
    let storageFailureCode: String?

    /// Where durable storage lives.
    static func storeURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        return
            support
            .appendingPathComponent("MacDevClean", isDirectory: true)
            .appendingPathComponent("store.sqlite")
    }

    static func live(arguments: [String] = CommandLine.arguments) -> AppDependencies {
        let isUITesting = arguments.contains("--ui-testing")

        #if DEBUG
            if isUITesting, let scenario = PreviewScenario.parse(arguments) {
                return fixture(scenario: scenario)
            }
        #endif

        // Release, and ordinary Debug launches: the real services over durable
        // storage. If that storage cannot be opened, the app still scans and
        // explains, but it will not act: a cleanup nobody can audit afterwards
        // is not offered.
        let store = InMemoryCandidateStore()
        var storageFailureCode: String?
        let durable: SwiftDataRepositories?
        do {
            durable = try SwiftDataRepositories.make(containerURL: try storeURL())
        } catch {
            durable = nil
            storageFailureCode = PolicyError.journalUnavailable.rawValue
        }
        let settings: any SettingsRepository & HistoryRepository =
            durable ?? SessionRepositories()
        let context = AppSafetyContextProvider(settings: settings, store: store)
        let files = LocalFileSystem()
        let catalog = RuleCatalog()
        let git = ReadOnlyGitClient()
        let rules = RuleEvidenceChecker(files: files, git: git, catalog: catalog)
        let policy = PathPolicy(files: files)
        let developerScanner = DeveloperScanner(
            files: files,
            catalog: catalog,
            git: git,
            context: context,
            store: InMemoryCandidateStore(),
        )
        let docker: (any DockerClient)? = nil

        return AppDependencies(
            scanner: CompositeScanService(
                filesystem: developerScanner, docker: docker, store: store, context: context),
            largeFileScanner: LargeFileScanner(
                files: files, context: context, store: store),
            validator: CleanupPlanValidator(
                store: store, context: context, pathPolicy: policy, files: files,
                rules: rules, docker: UnavailableDockerClient(), clock: SystemClock()),
            executor: CleanupExecutor(
                store: store, context: context, pathPolicy: policy, files: files,
                rules: rules, trash: FileManagerTrashClient(),
                docker: UnavailableDockerClient(), journal: settings, clock: SystemClock()),
            settings: settings,
            history: settings,
            store: store,
            context: context,
            picker: NativeFolderPicker(),
            workspace: NativeWorkspaceOpener(),
            home: URL(fileURLWithPath: NSHomeDirectory()),
            // Real side effects are offered only when the record of them will
            // survive quitting the app.
            cleanupEnabled: durable != nil,
            isUITesting: isUITesting,
            storageFailureCode: storageFailureCode
        )
    }

    #if DEBUG
        /// The fixture stack. Real scanner, real policy, real validator; fake
        /// Trash, fake Docker, in-memory storage, and a temporary tree of
        /// synthetic artifacts this process created.
        static func fixture(scenario: PreviewScenario) -> AppDependencies {
            let home =
                (try? PreviewFixtureWorld.build())
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let projects = home.appendingPathComponent("projects")
            let media = home.appendingPathComponent("media")

            let store = InMemoryCandidateStore()
            let settings = SessionRepositories(
                roots: scenario == .firstRun ? [] : [ScanRoot(url: projects)])
            let context = AppSafetyContextProvider(
                settings: settings, store: store, home: home)

            let files = LocalFileSystem()
            let catalog = RuleCatalog()
            let git = ReadOnlyGitClient()
            let rules = RuleEvidenceChecker(files: files, git: git, catalog: catalog)
            let policy = PathPolicy(files: files)
            let developerScanner = DeveloperScanner(
                files: files, catalog: catalog, git: git, context: context,
                store: InMemoryCandidateStore())

            let docker: any DockerClient =
                scenario == .dockerVolume
                ? PreviewDocker(inventory: PreviewFixtureWorld.dockerInventory())
                : UnavailablePreviewDocker()

            return AppDependencies(
                scanner: CompositeScanService(
                    filesystem: developerScanner,
                    docker: scenario == .dockerVolume ? docker : nil,
                    store: store,
                    context: context),
                largeFileScanner: LargeFileScanner(
                    files: files, context: context, store: store),
                validator: CleanupPlanValidator(
                    store: store, context: context, pathPolicy: policy, files: files,
                    rules: rules, docker: docker, clock: SystemClock()),
                executor: CleanupExecutor(
                    store: store, context: context, pathPolicy: policy, files: files,
                    rules: rules, trash: PreviewTrash(), docker: docker,
                    journal: settings, clock: SystemClock()),
                settings: settings,
                history: settings,
                store: store,
                context: context,
                picker: PreviewFolderPicker(
                    folders: scenario == .largeFiles ? [media] : [projects]),
                workspace: PreviewWorkspaceOpener(),
                home: home,
                // The side effects are fakes, so the flow can be exercised end
                // to end without touching anything real.
                cleanupEnabled: true,
                isUITesting: true,
                storageFailureCode: nil
            )
        }
    #endif
}

/// The clock production code uses.
struct SystemClock: ClockProviding {
    func now() -> Date { Date() }
}

/// Stands in for Docker when there is none. Every call refuses, which is what
/// keeps the Docker path unreachable rather than merely unused.
struct UnavailableDockerClient: DockerClient {
    func inventory() async throws -> DockerInventory { throw PolicyError.unavailable }
    func revalidate(_ item: CleanupCandidate, evidence: CandidateEvidence) async throws {
        throw PolicyError.unavailable
    }
    func remove(_ item: CleanupCandidate) async throws { throw PolicyError.unavailable }
}
