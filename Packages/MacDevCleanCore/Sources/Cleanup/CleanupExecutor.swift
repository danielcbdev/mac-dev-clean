import Domain
import Foundation

/// Performs an authorised plan, one item at a time, re-checking each item
/// immediately before it acts.
///
/// The properties that matter:
///
/// - **A plan is consumed once.** Confirming twice does not act twice.
/// - **Every item is re-checked at the last possible moment**, including the
///   whole ancestor chain, because a scan and even a validation are both in the
///   past by the time the side effect runs.
/// - **Failure is per item.** One permission error does not abandon the rest.
/// - **The journal is written ahead.** If it cannot record the intent, nothing
///   moves. If it fails *after* something moved, the session stops and the item
///   is marked unrecorded — the move is never repeated to tidy up history.
/// - **Every scheduled item ends with a status**, including the ones that were
///   never reached.
public struct CleanupExecutor: CleanupExecuting {
    private let runner: Runner

    public init(
        store: any CandidateStore,
        context: any SafetyContextProviding,
        pathPolicy: any PathPolicyChecking,
        files: any FileSystemClient,
        rules: any RuleEvidenceChecking,
        trash: any TrashClient,
        docker: any DockerClient,
        journal: any CleanupJournal,
        clock: any ClockProviding,
        freeSpace: any FreeSpaceObserving = VolumeFreeSpace()
    ) {
        runner = Runner(
            store: store,
            context: context,
            pathPolicy: pathPolicy,
            files: files,
            rules: rules,
            trash: trash,
            docker: docker,
            journal: journal,
            clock: clock,
            freeSpace: freeSpace
        )
    }

    public func execute(_ plan: ValidatedCleanupPlan) -> AsyncStream<CleanupEvent> {
        AsyncStream(CleanupEvent.self, bufferingPolicy: .unbounded) { continuation in
            let work = Task { await runner.run(plan, into: continuation) }
            continuation.onTermination = { _ in work.cancel() }
        }
    }
}

/// Serialises every run, and remembers which plans have already been spent.
private actor Runner {
    private let store: any CandidateStore
    private let context: any SafetyContextProviding
    private let pathPolicy: any PathPolicyChecking
    private let files: any FileSystemClient
    private let rules: any RuleEvidenceChecking
    private let trash: any TrashClient
    private let docker: any DockerClient
    private let journal: any CleanupJournal
    private let clock: any ClockProviding
    private let freeSpace: any FreeSpaceObserving

    private var consumed: Set<UUID> = []

    init(
        store: any CandidateStore,
        context: any SafetyContextProviding,
        pathPolicy: any PathPolicyChecking,
        files: any FileSystemClient,
        rules: any RuleEvidenceChecking,
        trash: any TrashClient,
        docker: any DockerClient,
        journal: any CleanupJournal,
        clock: any ClockProviding,
        freeSpace: any FreeSpaceObserving
    ) {
        self.store = store
        self.context = context
        self.pathPolicy = pathPolicy
        self.files = files
        self.rules = rules
        self.trash = trash
        self.docker = docker
        self.journal = journal
        self.clock = clock
        self.freeSpace = freeSpace
    }

    func run(
        _ plan: ValidatedCleanupPlan,
        into continuation: AsyncStream<CleanupEvent>.Continuation
    ) async {
        continuation.yield(.started(plan.id))

        guard consumed.insert(plan.id).inserted else {
            finish(plan, refusing: .usedPlan, outcome: .skipped, into: continuation)
            return
        }
        guard clock.now() <= plan.expiresAt else {
            finish(plan, refusing: .expiredPlan, outcome: .skipped, into: continuation)
            return
        }
        guard let safety = try? await context.current() else {
            finish(plan, refusing: .unavailable, outcome: .failed, into: continuation)
            return
        }
        guard safety.revision == plan.policyRevision else {
            finish(plan, refusing: .staleScan, outcome: .failed, into: continuation)
            return
        }

        let candidates = plan.items.map(\.candidate)
        do {
            // Write-ahead. If the intent cannot be recorded, nothing moves.
            try await journal.begin(
                sessionID: plan.id, candidates: candidates, at: clock.now())
        } catch {
            finish(plan, refusing: .journalUnavailable, outcome: .failed, into: continuation)
            return
        }

        let probe = plan.items.compactMap { item -> URL? in
            if case .file(let url) = item.candidate.location { return url }
            return nil
        }.first
        let before = probe.map { url in Task { await freeSpace.availableBytes(on: url) } }
        let beforeBytes = await before?.value ?? nil

        var records: [CleanupRecord] = []
        var stop: PolicyError?

        for item in plan.items {
            if Task.isCancelled {
                records.append(
                    Self.record(item.candidate, .cancelled, code: .cancelled, at: clock.now()))
                continuation.yield(.item(records[records.count - 1]))
                continue
            }
            if let stop {
                records.append(Self.record(item.candidate, .skipped, code: stop, at: clock.now()))
                continuation.yield(.item(records[records.count - 1]))
                continue
            }

            var record = await perform(item, safety: safety)

            do {
                try await journal.record(sessionID: plan.id, record: record)
            } catch {
                // The side effect already happened. Recording it failed, so the
                // history is incomplete. Stop scheduling, mark this item
                // unrecorded, and never repeat the move to "fix" history.
                record = CleanupRecord(
                    id: record.id,
                    candidate: record.candidate,
                    outcome: record.outcome,
                    resultingTrashURL: record.resultingTrashURL,
                    errorCode: PolicyError.journalUnavailable.rawValue,
                    finishedAt: record.finishedAt
                )
                stop = .journalUnavailable
            }

            records.append(record)
            continuation.yield(.item(record))
        }

        let afterBytes = probe.map { url in Task { await freeSpace.availableBytes(on: url) } }
        let after = await afterBytes?.value ?? nil

        let summary = CleanupSummary(
            sessionID: plan.id,
            records: records,
            // Only confirmed moves, and only logical sizes. This is what was
            // moved to the Trash — never what was freed.
            bytesMovedToTrash: records.reduce(into: UInt64(0)) { total, record in
                guard record.outcome == .movedToTrash, let size = record.candidate.size else {
                    return
                }
                total =
                    total.addingReportingOverflow(size).overflow
                    ? total : total + size
            },
            // An observation, reported as it is. A negative value is real and
            // is never clamped to zero or called reclaimed space.
            observedFreeSpaceDelta: Self.delta(from: beforeBytes, to: after)
        )
        try? await journal.finish(summary, at: clock.now())
        continuation.yield(.finished(summary))
        continuation.finish()
    }

    // MARK: - One item

    private func perform(
        _ item: ValidatedCleanupItem,
        safety: SafetyContext
    ) async -> CleanupRecord {
        let candidate = item.candidate
        let now = clock.now()

        switch candidate.location {
        case .file(let url):
            do {
                // The last possible moment. The path policy walks the whole
                // ancestor chain again, so a component swapped since validation
                // is caught here rather than trusted.
                try await pathPolicy.check(url, ruleID: candidate.ruleID, context: safety)
                if safety.exclusions.contains(.category(candidate.category)) {
                    throw PolicyError.excluded
                }
                let entry = try await files.entry(at: url)
                guard let recorded = item.evidence.identity, entry.identity == recorded else {
                    throw PolicyError.changed
                }
                try await rules.verify(candidate, evidence: item.evidence)
            } catch let error as PolicyError {
                return Self.record(candidate, .skipped, code: error, at: now)
            } catch {
                return Self.record(candidate, .failed, code: .unavailable, at: now)
            }

            do {
                let destination = try await trash.moveToTrash(url)
                return CleanupRecord(
                    id: candidate.id,
                    candidate: candidate,
                    outcome: .movedToTrash,
                    resultingTrashURL: destination,
                    errorCode: nil,
                    finishedAt: now
                )
            } catch TrashOutcomeError.movedButResultingLocationUnknown {
                // It moved. Where it landed is unknown, so the outcome is
                // indeterminate and its bytes are not counted as moved.
                return CleanupRecord(
                    id: candidate.id,
                    candidate: candidate,
                    outcome: .indeterminate,
                    resultingTrashURL: nil,
                    errorCode: "movedButResultingLocationUnknown",
                    finishedAt: now
                )
            } catch let error as PolicyError {
                return Self.record(candidate, .failed, code: error, at: now)
            } catch {
                return Self.record(candidate, .failed, code: .unavailable, at: now)
            }

        case .docker:
            do {
                try await docker.revalidate(candidate, evidence: item.evidence)
            } catch let error as PolicyError {
                return Self.record(candidate, .skipped, code: error, at: now)
            } catch {
                return Self.record(candidate, .failed, code: .unavailable, at: now)
            }

            do {
                try await docker.remove(candidate)
                return CleanupRecord(
                    id: candidate.id,
                    candidate: candidate,
                    outcome: .removed,
                    resultingTrashURL: nil,
                    errorCode: nil,
                    finishedAt: now
                )
            } catch let error as PolicyError {
                // A Docker write interrupted part way cannot be rolled back and
                // is not claimed to have been.
                return Self.record(
                    candidate,
                    error == .cancelled ? .indeterminate : .failed,
                    code: error,
                    at: now
                )
            } catch {
                return Self.record(candidate, .failed, code: .unavailable, at: now)
            }
        }
    }

    // MARK: - Helpers

    private func finish(
        _ plan: ValidatedCleanupPlan,
        refusing code: PolicyError,
        outcome: ItemOutcome,
        into continuation: AsyncStream<CleanupEvent>.Continuation
    ) {
        let now = clock.now()
        let records = plan.items.map {
            Self.record($0.candidate, outcome, code: code, at: now)
        }
        for record in records { continuation.yield(.item(record)) }
        continuation.yield(
            .finished(
                CleanupSummary(
                    sessionID: plan.id,
                    records: records,
                    bytesMovedToTrash: 0,
                    observedFreeSpaceDelta: nil
                )
            )
        )
        continuation.finish()
    }

    private static func record(
        _ candidate: CleanupCandidate,
        _ outcome: ItemOutcome,
        code: PolicyError,
        at now: Date
    ) -> CleanupRecord {
        CleanupRecord(
            id: candidate.id,
            candidate: candidate,
            outcome: outcome,
            resultingTrashURL: nil,
            errorCode: code.rawValue,
            finishedAt: now
        )
    }

    private static func delta(from before: Int64?, to after: Int64?) -> Int64? {
        guard let before, let after else { return nil }
        return after - before
    }
}
