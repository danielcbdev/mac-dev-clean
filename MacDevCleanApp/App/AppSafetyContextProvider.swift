import CleanupRules
import Domain
import Foundation
import Scanning

/// Derives the scope cleanup may act in, from the user's settings plus the
/// rule catalog's registered cache locations.
///
/// The revision increments whenever roots, Large Files scope or exclusions
/// change, and every registered scan snapshot is discarded at the same moment.
/// A snapshot taken under the old scope describes a world that no longer
/// exists, and the validator refuses it.
actor AppSafetyContextProvider: SafetyContextProviding {
    private let settings: any SettingsRepository
    private let store: any CandidateStore
    private let catalog: RuleCatalog
    private let home: URL

    private var revision: UInt64 = 1
    private var largeFileRoots: [URL] = []
    private var cached: SafetyContext?

    init(
        settings: any SettingsRepository,
        store: any CandidateStore,
        catalog: RuleCatalog = RuleCatalog(),
        home: URL = URL(fileURLWithPath: NSHomeDirectory())
    ) {
        self.settings = settings
        self.store = store
        self.catalog = catalog
        self.home = home
    }

    func current() async throws -> SafetyContext {
        if let cached { return cached }
        let context = SafetyContext(
            home: home,
            projectRoots: try await settings.roots().map(\.url),
            largeFileRoots: largeFileRoots,
            globalRuleRoots: catalog.globalRoots(home: home),
            exclusions: try await settings.exclusions(),
            revision: revision
        )
        cached = context
        return context
    }

    /// Called after anything that changes scope. Bumping the revision is what
    /// makes every outstanding review stale.
    func invalidate() async {
        revision += 1
        cached = nil
        await store.invalidate()
    }

    func setLargeFileRoots(_ roots: [URL]) async {
        largeFileRoots = roots
        await invalidate()
    }
}
