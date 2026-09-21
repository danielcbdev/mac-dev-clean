import Domain
import Foundation
import Observation

/// Owns navigation, the feature models and the services behind them.
///
/// Views talk to this and to their own model. They do not build services, and
/// they cannot start a second scan by being revisited — the state says whether
/// one is already running.
@MainActor
@Observable
final class RootCoordinator {
    private(set) var state: AppState = .idle
    var destination: Destination = .overview
    /// Set when the review screen is open.
    var isReviewing = false

    let dependencies: AppDependencies
    let scanModel: ScanModel
    let reviewModel: ReviewModel
    let rootSelection: RootSelectionModel

    private(set) var roots: [ScanRoot] = []
    private(set) var includeGlobalCaches = true

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        scanModel = ScanModel(scanner: dependencies.scanner)
        reviewModel = ReviewModel(
            validator: dependencies.validator, executor: dependencies.executor)
        rootSelection = RootSelectionModel(
            settings: dependencies.settings,
            picker: dependencies.picker,
            home: dependencies.home)
    }

    // MARK: - Lifecycle

    func load() async {
        roots = (try? await dependencies.settings.roots()) ?? []
        if roots.isEmpty {
            state = .onboarding
            rootSelection.loadProposals()
        } else {
            state = .idle
        }
    }

    func confirmRoots() async {
        guard await rootSelection.confirm() else { return }
        await dependencies.context.invalidate()
        roots = (try? await dependencies.settings.roots()) ?? []
        state = .idle
    }

    // MARK: - Scanning

    var canScan: Bool { !roots.isEmpty && !scanModel.isScanning }

    func startScan() {
        guard canScan else { return }
        state = .scanning
        scanModel.start(
            ScanRequest(
                roots: roots, includeGlobalCaches: includeGlobalCaches))
        observeScan()
    }

    func cancelScan() {
        scanModel.cancel()
        state = scanModel.snapshot == nil ? .idle : .results
    }

    private func observeScan() {
        Task { [weak self] in
            // Settle the coordinator's state once the model stops, whatever
            // path it took to stop.
            while let self, self.scanModel.isScanning {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard let self else { return }
            if self.scanModel.snapshot != nil {
                self.state = .results
            } else if self.state == .scanning {
                self.state = .idle
            }
        }
    }

    // MARK: - Review

    func openReview() {
        guard !scanModel.selectedIDs.isEmpty else {
            // Nothing selected yet: send the user where selection happens
            // rather than opening an empty review.
            destination = .caches
            return
        }
        reviewModel.contentChanged(to: scanModel.selectedIDs)
        isReviewing = true
        state = .reviewing
    }

    func closeReview() {
        isReviewing = false
        state = scanModel.snapshot == nil ? .idle : .results
    }

    func confirmCleanup() async {
        guard let scanID = scanModel.snapshot?.id, dependencies.cleanupEnabled else { return }
        state = .cleaning
        await reviewModel.confirm(scanID: scanID, ids: scanModel.selectedIDs)
        state = .completed
    }

    // MARK: - Exclusions and scope

    /// Adding an exclusion changes the scope, which invalidates every snapshot
    /// and any review built from one.
    func exclude(_ exclusion: Exclusion) async {
        var current = (try? await dependencies.settings.exclusions()) ?? []
        guard !current.contains(exclusion) else { return }
        current.append(exclusion)
        try? await dependencies.settings.saveExclusions(current)
        await dependencies.context.invalidate()
        isReviewing = false
        scanModel.clearSelection()
        state = .idle
    }

    func reveal(_ url: URL) { dependencies.workspace.reveal(url) }
    func openTrash() { dependencies.workspace.openTrash() }
}
