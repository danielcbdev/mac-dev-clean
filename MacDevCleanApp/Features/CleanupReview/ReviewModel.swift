import Cleanup
import Domain
import Foundation
import Observation

/// Drives the final confirmation and reports what happened.
///
/// It holds identifiers and acknowledgments, never a prepared destructive
/// command. The plan is requested from the validator at the moment the user
/// confirms, so everything is checked against the world as it is then.
///
/// Both acknowledgments reset whenever the content under review changes. An
/// acknowledgment applies to what the user was looking at, not to whatever
/// happens to be selected later.
@MainActor
@Observable
final class ReviewModel {
    private(set) var results: [CleanupRecord] = []
    private(set) var isRunning = false
    private(set) var summary: CleanupSummary?
    private(set) var validationIssues: [ValidationIssue] = []
    private(set) var failureCode: String?

    var acknowledgeIrreversible = false
    var acknowledgeHighRisk = false

    private let validator: any CleanupPlanValidating
    private let executor: any CleanupExecuting
    private let work = CancellableWork()
    /// What the acknowledgments were given for. If this changes, they lapse.
    private var acknowledgedContent: Set<UUID> = []

    init(validator: any CleanupPlanValidating, executor: any CleanupExecuting) {
        self.validator = validator
        self.executor = executor
    }

    deinit {
        work.cancel()
    }

    // MARK: - Content changes

    /// Called whenever the review's contents change. Acknowledgments given for
    /// a different set of items do not carry over.
    func contentChanged(to ids: Set<UUID>) {
        guard ids != acknowledgedContent else { return }
        acknowledgedContent = ids
        acknowledgeIrreversible = false
        acknowledgeHighRisk = false
        validationIssues = []
        failureCode = nil
    }

    func reset() {
        results = []
        summary = nil
        validationIssues = []
        failureCode = nil
        acknowledgeIrreversible = false
        acknowledgeHighRisk = false
        acknowledgedContent = []
    }

    // MARK: - Confirming

    /// True only when everything the plan will contain has been acknowledged.
    func canConfirm(needsIrreversible: Bool, needsHighRisk: Bool) -> Bool {
        guard !isRunning else { return false }
        if needsIrreversible && !acknowledgeIrreversible { return false }
        if needsHighRisk && !acknowledgeHighRisk { return false }
        return true
    }

    func confirm(scanID: UUID, ids: Set<UUID>) async {
        // Serialised on the main actor: a second click while a run is in flight
        // does nothing at all.
        guard !isRunning, !ids.isEmpty else { return }
        isRunning = true
        results = []
        summary = nil
        validationIssues = []
        failureCode = nil

        let selection = CleanupSelection(
            scanID: scanID,
            candidateIDs: ids,
            acknowledgedIrreversible: acknowledgeIrreversible,
            acknowledgedHighRisk: acknowledgeHighRisk
        )

        do {
            let plan = try await validator.validate(selection)
            let stream = executor.execute(plan)
            let task = Task { [weak self] in
                for await event in stream {
                    await self?.receive(event)
                }
            }
            work.replace(with: task)
            await task.value
        } catch let error as PolicyError {
            // Nothing is approved automatically. The user is told which items
            // are affected and offered a rescan.
            validationIssues = await validator.inspect(selection)
            if validationIssues.isEmpty {
                validationIssues = ids.map { ValidationIssue(candidateID: $0, code: error) }
            }
            failureCode = error.rawValue
        } catch {
            failureCode = PolicyError.unavailable.rawValue
        }

        // Every path settles this, including the failures above.
        isRunning = false
        work.replace(with: nil)
    }

    func cancel() {
        work.cancel()
        isRunning = false
    }

    func receive(_ event: CleanupEvent) {
        switch event {
        case .started:
            results = []
        case .item(let record):
            if let index = results.firstIndex(where: { $0.id == record.id }) {
                results[index] = record
            } else {
                results.append(record)
            }
        case .finished(let value):
            summary = value
            results = value.records
        }
    }

    // MARK: - Results, grouped as the user needs to read them

    var completed: [CleanupRecord] {
        results.filter { $0.outcome == .movedToTrash || $0.outcome == .removed }
    }
    var skipped: [CleanupRecord] { results.filter { $0.outcome == .skipped } }
    var failed: [CleanupRecord] { results.filter { $0.outcome == .failed } }
    var cancelled: [CleanupRecord] { results.filter { $0.outcome == .cancelled } }
    var indeterminate: [CleanupRecord] { results.filter { $0.outcome == .indeterminate } }

    /// Items that went to the Trash, which the user may still be able to
    /// retrieve. Kept apart from irreversible removals on purpose.
    var recoverable: [CleanupRecord] { results.filter { $0.outcome == .movedToTrash } }
    var irreversiblyRemoved: [CleanupRecord] { results.filter { $0.outcome == .removed } }

    var diagnosticReport: String {
        guard let summary else { return "" }
        return CleanupDiagnostics.report(
            for: summary,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                as? String ?? "unknown"
        )
    }
}
