import Domain
import Foundation
import Observation

/// Why a scan cannot start.
///
/// A control that cannot act must not look like one that can. The reason is
/// modelled rather than implied, so the interface can disable the control,
/// say why, and offer whatever resolves it.
enum ScanUnavailableReason: Equatable {
    /// No folders have been added, so there is nothing to look through.
    case noRoots
    /// A scan is already running.
    case alreadyScanning
}

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
    let largeFiles: LargeFilesModel
    let history: HistoryModel
    let exclusionsModel: ExclusionsModel
    let settings: SettingsModel

    private(set) var roots: [ScanRoot] = []
    /// Which snapshot and which identifiers the open review refers to. Set by
    /// `review(scanID:ids:)` so Caches and Large Files share one path.
    private(set) var activeScanID: UUID?
    private(set) var activeSelection: Set<UUID> = []
    private(set) var includeGlobalCaches = true

    var interfaceLocale: Locale { settings.preferences.language.interfaceLocale }

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        scanModel = ScanModel(scanner: dependencies.scanner)
        reviewModel = ReviewModel(
            validator: dependencies.validator, executor: dependencies.executor)
        rootSelection = RootSelectionModel(
            settings: dependencies.settings,
            picker: dependencies.picker,
            home: dependencies.home)
        let context = dependencies.context
        history = HistoryModel(
            repository: dependencies.history, workspace: dependencies.workspace)
        exclusionsModel = ExclusionsModel(
            repository: dependencies.settings,
            invalidate: { await context.invalidateAfterSettingsChange() },
            picker: dependencies.picker)
        settings = SettingsModel(
            repository: dependencies.settings,
            invalidate: { await context.invalidateAfterSettingsChange() },
            picker: dependencies.picker)
        largeFiles = LargeFilesModel(
            scanner: dependencies.largeFileScanner,
            picker: dependencies.picker,
            workspace: dependencies.workspace,
            applyRoots: { roots in await context.setLargeFileRoots(roots) }
        )
    }

    // MARK: - Lifecycle

    func load() async {
        await settings.load()
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

    var canScan: Bool { scanUnavailableReason == nil }

    /// Why a scan cannot start, or `nil` when it can.
    ///
    /// `startScan()` used to open with `guard canScan else { return }` and
    /// return in silence, while the control that called it stayed enabled. The
    /// user pressed a button and the application did not answer. The refusal
    /// is a value now, so the interface can disable the control, say why, and
    /// offer whatever resolves it.
    var scanUnavailableReason: ScanUnavailableReason? {
        if scanModel.isScanning { return .alreadyScanning }
        if roots.isEmpty { return .noRoots }
        return nil
    }

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

    /// Opens the review for an explicit snapshot and selection.
    ///
    /// Shared by Caches and Large Files, so both go through the same
    /// validation, the same acknowledgments and the same results screen.
    func review(scanID: UUID, ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        activeScanID = scanID
        activeSelection = ids
        reviewModel.contentChanged(to: ids)
        isReviewing = true
        state = .reviewing
    }

    func openReview() {
        guard !scanModel.selectedIDs.isEmpty else {
            // Nothing selected yet: send the user where selection happens
            // rather than opening an empty review.
            destination = .caches
            return
        }
        review(scanID: scanModel.snapshot?.id ?? UUID(), ids: scanModel.selectedIDs)
    }

    func closeReview() {
        isReviewing = false
        state = scanModel.snapshot == nil ? .idle : .results
    }

    func confirmCleanup() async {
        guard let scanID = activeScanID, dependencies.cleanupEnabled else { return }
        state = .cleaning
        await reviewModel.confirm(scanID: scanID, ids: activeSelection)
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
        await dependencies.context.invalidateAfterSettingsChange()
        await exclusionsModel.load()
        isReviewing = false
        scanModel.clearSelection()
        state = .idle
    }

    /// The candidates the open review refers to, resolved from whichever
    /// snapshot they came from.
    var reviewedCandidates: [CleanupCandidate] {
        let fromScan = scanModel.candidates.filter { activeSelection.contains($0.id) }
        guard fromScan.isEmpty else { return fromScan }
        return largeFiles.snapshot?.candidates
            .filter { activeSelection.contains($0.id) } ?? []
    }

    func reveal(_ url: URL) { dependencies.workspace.reveal(url) }
    func openTrash() { dependencies.workspace.openTrash() }
}
