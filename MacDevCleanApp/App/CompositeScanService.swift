import Domain
import Foundation

/// Runs the filesystem scan and, when Docker is available, folds its inventory
/// into the same snapshot.
///
/// One snapshot, one identifier. The review screen submits identifiers from a
/// single registered snapshot regardless of where a candidate came from, so
/// there is no second registry and no way for a Docker candidate to arrive
/// without provenance.
///
/// Docker being unavailable is reported as an issue and costs nothing else: the
/// filesystem results are unaffected, which is the behaviour the specification
/// requires.
struct CompositeScanService: ScanService {
    private let filesystem: any ScanService
    private let docker: (any DockerClient)?
    private let store: any CandidateStore
    private let context: any SafetyContextProviding

    init(
        filesystem: any ScanService,
        docker: (any DockerClient)?,
        store: any CandidateStore,
        context: any SafetyContextProviding
    ) {
        self.filesystem = filesystem
        self.docker = docker
        self.store = store
        self.context = context
    }

    func scan(_ request: ScanRequest) -> AsyncThrowingStream<ScanEvent, Error> {
        AsyncThrowingStream(ScanEvent.self, bufferingPolicy: .unbounded) { continuation in
            let work = Task {
                do {
                    var candidates: [CleanupCandidate] = []
                    var evidence: [UUID: CandidateEvidence] = [:]

                    for try await event in filesystem.scan(request) {
                        switch event {
                        case .completed(let snapshot):
                            candidates.append(contentsOf: snapshot.candidates)
                            evidence.merge(snapshot.evidence) { current, _ in current }
                        case .progress, .issue:
                            // Forwarded as they arrive; the interface shows
                            // partial results while the scan continues.
                            continuation.yield(event)
                        }
                    }

                    if let docker {
                        do {
                            let inventory = try await docker.inventory()
                            candidates.append(contentsOf: inventory.candidates)
                            evidence.merge(inventory.evidence) { current, _ in current }
                        } catch {
                            continuation.yield(
                                .issue(code: "issue.docker.unavailable", relativePath: nil))
                        }
                    }

                    try Task.checkCancellation()
                    let revision = (try? await context.current().revision) ?? 0
                    let snapshot = ScanSnapshot(
                        id: UUID(),
                        policyRevision: revision,
                        candidates: candidates,
                        evidence: evidence
                    )
                    await store.save(snapshot)
                    continuation.yield(.completed(snapshot))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }
}
