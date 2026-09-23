import Domain
import Foundation
import Observation

/// Drives one scan and holds what it found.
///
/// Two rules shape this type:
///
/// - **Nothing is selected by a scan.** `selectedIDs` starts empty and is
///   cleared whenever a new scan starts. Selection is something the user does.
/// - **A stale run cannot overwrite a newer one.** Each run carries a
///   generation; events from a superseded run are dropped rather than applied,
///   so cancelling and rescanning quickly cannot show the old results.
@MainActor
@Observable
final class ScanModel {
    enum Sort: String, CaseIterable, Identifiable {
        case size, name
        var id: String { rawValue }
    }

    private(set) var snapshot: ScanSnapshot?
    private(set) var isScanning = false
    private(set) var visited = 0
    private(set) var issueCodes: [String] = []
    private(set) var failureCode: String?
    private(set) var wasCancelled = false
    /// True once at least one scan has run to completion in this launch.
    private(set) var hasScanned = false

    var selectedIDs: Set<UUID> = []

    // Filtering is presentation only. It never changes what is selected, so a
    // selection made under one filter survives changing it.
    var ecosystemFilter: CleanupCategory?
    var riskFilter: RiskLevel?
    var sort: Sort = .size
    /// Categories whose high-risk detail the user has explicitly opened.
    var expandedHighRisk: Set<CleanupCategory> = []

    private let scanner: any ScanService
    private let work = CancellableWork()
    private var activeGeneration: UUID?

    init(scanner: any ScanService) {
        self.scanner = scanner
    }

    deinit {
        // Disposing the model stops the scan. Without this a discarded model
        // would keep a scan running against a scope nobody is looking at.
        work.cancel()
    }

    // MARK: - Running

    func start(_ request: ScanRequest) {
        guard !isScanning else { return }

        work.cancel()
        selectedIDs = []
        snapshot = nil
        issueCodes = []
        failureCode = nil
        wasCancelled = false
        visited = 0
        isScanning = true

        let generation = UUID()
        activeGeneration = generation
        work.replace(
            with: Task { [weak self, scanner] in
                do {
                    for try await event in scanner.scan(request) {
                        guard !Task.isCancelled, await self?.activeGeneration == generation else {
                            break
                        }
                        await self?.receive(event, generation: generation)
                    }
                    await self?.finishNormally(generation)
                } catch is CancellationError {
                    await self?.finishCancellation(generation)
                } catch {
                    await self?.finishFailure(generation, code: "scan.failed")
                }
            })
    }

    func cancel() {
        work.cancel()
        // The generation is retired immediately, so anything still in flight
        // from the old run is ignored even if it arrives later.
        activeGeneration = nil
        isScanning = false
        wasCancelled = true
    }

    // MARK: - Events

    private func receive(_ event: ScanEvent, generation: UUID) {
        guard activeGeneration == generation else { return }
        switch event {
        case .progress(let count):
            visited = count
        case .issue(let code, _):
            if !issueCodes.contains(code) { issueCodes.append(code) }
        case .completed(let value):
            snapshot = value
            hasScanned = true
        }
    }

    private func finishNormally(_ generation: UUID) {
        guard activeGeneration == generation else { return }
        isScanning = false
        activeGeneration = nil
    }

    private func finishCancellation(_ generation: UUID) {
        guard activeGeneration == generation else { return }
        isScanning = false
        wasCancelled = true
        activeGeneration = nil
    }

    private func finishFailure(_ generation: UUID, code: String) {
        guard activeGeneration == generation else { return }
        isScanning = false
        failureCode = code
        activeGeneration = nil
    }

    // MARK: - Selection

    /// High-risk items are never selectable from the list. They are selected
    /// from their own expanded detail section, which is what makes the choice
    /// deliberate.
    func canSelectFromList(_ candidate: CleanupCandidate) -> Bool {
        candidate.risk != .high
    }

    func isSelected(_ id: UUID) -> Bool { selectedIDs.contains(id) }

    func toggle(_ candidate: CleanupCandidate) {
        if selectedIDs.contains(candidate.id) {
            selectedIDs.remove(candidate.id)
        } else {
            selectedIDs.insert(candidate.id)
        }
    }

    /// Selects everything visible except high-risk items. A bulk action never
    /// reaches something irreversible.
    func selectAllSelectable() {
        for candidate in visibleCandidates where canSelectFromList(candidate) {
            selectedIDs.insert(candidate.id)
        }
    }

    func clearSelection() { selectedIDs = [] }

    /// Drops every filter, which is what the screen offers when the filters
    /// hide all of the results.
    func clearFilters() {
        ecosystemFilter = nil
        riskFilter = nil
    }

    /// Drops selections that are no longer in the current snapshot, which is
    /// what happens when a root is removed and the scope shrinks.
    func pruneSelectionToSnapshot() {
        let available = Set(candidates.map(\.id))
        selectedIDs.formIntersection(available)
    }

    // MARK: - Derived presentation

    var candidates: [CleanupCandidate] { snapshot?.candidates ?? [] }

    /// True when a scan found things and the filters hide all of them.
    ///
    /// Caches listed `visibleCandidates` but chose its empty state from
    /// `candidates`, so a filter that excluded everything produced an empty
    /// scroll area with no message at all — which happens the moment a
    /// category is tapped on Overview, because that sets `ecosystemFilter`.
    /// "Nothing was found" and "nothing matches what you asked for" are
    /// different answers, and the screen has to be able to tell them apart.
    var hasResultsHiddenByFilters: Bool {
        !candidates.isEmpty && visibleCandidates.isEmpty
    }

    var visibleCandidates: [CleanupCandidate] {
        var result = candidates
        if let ecosystemFilter { result = result.filter { $0.category == ecosystemFilter } }
        if let riskFilter { result = result.filter { $0.risk == riskFilter } }
        switch sort {
        case .size:
            // Unknown sizes sort last: they are not "zero bytes".
            result.sort { left, right in
                switch (left.size, right.size) {
                case (let l?, let r?): return l > r
                case (nil, _?): return false
                case (_?, nil): return true
                case (nil, nil): return Self.displayName(left) < Self.displayName(right)
                }
            }
        case .name:
            result.sort { Self.displayName($0) < Self.displayName($1) }
        }
        return result
    }

    struct CategorySummary: Identifiable, Equatable {
        let category: CleanupCategory
        let knownBytes: UInt64
        let unknownCount: Int
        let itemCount: Int
        let highestRisk: RiskLevel
        var id: CleanupCategory { category }
    }

    /// Filesystem categories only. Docker is summarised separately, because its
    /// bytes are a different kind of number and must never be added in.
    var filesystemSummaries: [CategorySummary] {
        Self.summaries(for: candidates.filter { $0.method == .trash })
    }

    var dockerSummaries: [CategorySummary] {
        Self.summaries(for: candidates.filter { $0.method != .trash })
    }

    /// The ring's denominator: the sum of filesystem candidate sizes that are
    /// actually known. Not the disk, and not including unknowns.
    var knownFilesystemBytes: UInt64 {
        candidates
            .filter { $0.method == .trash }
            .compactMap(\.size)
            .reduce(UInt64(0)) { total, size in
                total.addingReportingOverflow(size).overflow ? total : total + size
            }
    }

    var unknownFilesystemCount: Int {
        candidates.filter { $0.method == .trash && $0.size == nil }.count
    }

    /// Docker's own estimate, kept apart and labelled as an estimate: image
    /// layers are shared, so removing two images does not free the sum.
    var estimatedDockerBytes: UInt64 {
        candidates
            .filter { $0.method != .trash }
            .compactMap(\.size)
            .reduce(UInt64(0)) { total, size in
                total.addingReportingOverflow(size).overflow ? total : total + size
            }
    }

    var dockerUnknownCount: Int {
        candidates.filter { $0.method != .trash && $0.size == nil }.count
    }

    var selectedCandidates: [CleanupCandidate] {
        candidates.filter { selectedIDs.contains($0.id) }
    }

    var selectedKnownBytes: UInt64 {
        selectedCandidates
            .filter { $0.method == .trash }
            .compactMap(\.size)
            .reduce(UInt64(0)) { total, size in
                total.addingReportingOverflow(size).overflow ? total : total + size
            }
    }

    var hasIrreversibleSelection: Bool {
        selectedCandidates.contains { $0.method != .trash }
    }

    var hasHighRiskSelection: Bool {
        selectedCandidates.contains { $0.risk == .high }
    }

    // MARK: - Naming

    /// A short, stable label for a candidate. Never the user's full path.
    static func displayName(_ candidate: CleanupCandidate) -> String {
        switch candidate.location {
        case .file(let url):
            let parent = url.deletingLastPathComponent().lastPathComponent
            return parent.isEmpty
                ? url.lastPathComponent : "\(parent)/\(url.lastPathComponent)"
        case .docker(_, _, let kind, let id):
            return "\(kind.rawValue) \(String(id.prefix(12)))"
        }
    }

    /// The identifier UI automation uses. Built from the rule and a short hash
    /// of the location, so it is stable across runs and contains no path.
    static func accessibilityID(_ candidate: CleanupCandidate) -> String {
        "candidate.\(candidate.ruleID).select"
    }

    private static func summaries(for items: [CleanupCandidate]) -> [CategorySummary] {
        Dictionary(grouping: items, by: \.category)
            .map { category, items in
                CategorySummary(
                    category: category,
                    knownBytes: items.compactMap(\.size).reduce(UInt64(0)) { total, size in
                        total.addingReportingOverflow(size).overflow ? total : total + size
                    },
                    unknownCount: items.filter { $0.size == nil }.count,
                    itemCount: items.count,
                    highestRisk: items.map(\.risk).max(by: Self.riskOrder) ?? .low
                )
            }
            .sorted { left, right in
                left.knownBytes == right.knownBytes
                    ? left.category.rawValue < right.category.rawValue
                    : left.knownBytes > right.knownBytes
            }
    }

    private static func riskOrder(_ left: RiskLevel, _ right: RiskLevel) -> Bool {
        func rank(_ risk: RiskLevel) -> Int {
            switch risk {
            case .low: return 0
            case .medium: return 1
            case .high: return 2
            }
        }
        return rank(left) < rank(right)
    }
}
