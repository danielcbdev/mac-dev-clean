import Domain
import Foundation

/// Replays a scripted sequence of scan events.
///
/// It is gated rather than timed: the consumer releases each event explicitly,
/// so a test can hold a scan mid-stream and observe what happens next without
/// sleeping and hoping.
public actor ReplayScanService: ScanService {
    private let events: [ScanEvent]
    private let failure: (any Error)?
    private var gateAfter: Int
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var startedRuns = 0

    public init(events: [ScanEvent], failure: (any Error)? = nil, gateAfter: Int = .max) {
        self.events = events
        self.failure = failure
        self.gateAfter = gateAfter
    }

    public func runCount() -> Int { startedRuns }

    /// Lets a gated stream continue.
    public func release() {
        released = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }

    private func noteStart() { startedRuns += 1 }

    private func waitIfGated(at index: Int) async {
        guard !released, index >= gateAfter else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    public nonisolated func scan(
        _ request: ScanRequest
    ) -> AsyncThrowingStream<ScanEvent, Error> {
        AsyncThrowingStream(ScanEvent.self, bufferingPolicy: .unbounded) { continuation in
            let work = Task {
                await noteStart()
                for (index, event) in await events.enumerated() {
                    await waitIfGated(at: index)
                    if Task.isCancelled {
                        continuation.finish(throwing: CancellationError())
                        return
                    }
                    continuation.yield(event)
                }
                if let failure = await failure {
                    continuation.finish(throwing: failure)
                } else {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }
}

/// Builders for scan events a test wants to replay.
public enum ScanFixtures {
    public static func candidate(
        rule: CleanupRuleID = "node.modules",
        path: String = "/fixture/app/node_modules",
        category: CleanupCategory = .node,
        size: ByteCount? = 1_024,
        risk: RiskLevel = .low,
        method: CleanupMethod = .trash
    ) -> CleanupCandidate {
        CleanupCandidate(
            id: UUID(),
            ruleID: rule,
            location: method == .trash
                ? .file(URL(fileURLWithPath: path))
                : .docker(context: "desktop-linux", builder: nil, kind: .volume, id: "vol"),
            category: category,
            size: size,
            allocatedSize: size,
            risk: risk,
            method: method,
            consequenceKey: ConsequenceKey.reinstallDependencies
        )
    }

    public static func snapshot(
        _ candidates: [CleanupCandidate],
        revision: UInt64 = 1
    ) -> ScanSnapshot {
        ScanSnapshot(
            id: UUID(),
            policyRevision: revision,
            candidates: candidates,
            evidence: Dictionary(
                uniqueKeysWithValues: candidates.map {
                    (
                        $0.id,
                        CandidateEvidence(
                            identity: nil, allowedRoot: nil, contextFingerprint: "fixture",
                            ruleEvidenceDigest: "fixture")
                    )
                })
        )
    }
}
