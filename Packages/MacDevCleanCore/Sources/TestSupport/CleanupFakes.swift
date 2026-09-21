import Cleanup
import Domain
import Foundation

/// A clock a test can move forward, to exercise plan expiry without waiting.
public final class MutableTestClock: ClockProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    public init(now: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        value = now
    }

    public func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    public func advance(seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        value = value.addingTimeInterval(seconds)
    }
}

/// A Trash that records what it was asked to move and moves nothing.
///
/// No test ever touches the real Trash.
public actor RecordingTrash: TrashClient {
    private var requests: [URL] = []
    private var failures: [String: any Error] = [:]
    private var pauseAfterCalls = Int.max
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func calls() -> [URL] { requests }

    public func fail(for url: URL, with error: any Error = PolicyError.permissionDenied) {
        failures[url.standardizedFileURL.path] = error
    }

    /// Blocks once this many moves have been requested, so a test can hold the
    /// executor mid-run and observe what it does next instead of racing it.
    public func pause(after calls: Int) {
        pauseAfterCalls = calls
    }

    public func release() {
        released = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }

    private func pauseIfNeeded() async {
        guard !released, requests.count >= pauseAfterCalls else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    public func moveToTrash(_ url: URL) async throws -> URL {
        await pauseIfNeeded()
        if let failure = failures[url.standardizedFileURL.path] {
            throw failure
        }
        requests.append(url)
        // A deterministic stand-in for the URL the real Trash would return.
        return URL(fileURLWithPath: "/fixture/Trash").appendingPathComponent(
            url.lastPathComponent
        )
    }
}

/// A Docker daemon a test describes, which removes nothing.
public actor RecordingDocker: DockerClient {
    private var stored = DockerInventory(fingerprint: "fixture", candidates: [], evidence: [:])
    private var removals: [UUID] = []
    private var revalidations: [UUID] = []
    private var failures: [UUID: PolicyError] = [:]

    public init() {}

    public func setInventory(_ value: DockerInventory) { stored = value }
    public func fail(for id: UUID, with error: PolicyError = .unavailable) {
        failures[id] = error
    }
    public func removalCalls() -> [UUID] { removals }
    public func revalidationCalls() -> [UUID] { revalidations }

    public func inventory() async throws -> DockerInventory { stored }

    public func revalidate(_ item: CleanupCandidate, evidence: CandidateEvidence) async throws {
        revalidations.append(item.id)
        if let failure = failures[item.id] { throw failure }
    }

    public func remove(_ item: CleanupCandidate) async throws {
        if let failure = failures[item.id] { throw failure }
        removals.append(item.id)
    }
}

/// A Docker client for filesystem-only tests: every call refuses.
///
/// Using this proves a filesystem test never reached the Docker path.
public struct UnavailableDockerClient: DockerClient {
    public init() {}

    public func inventory() async throws -> DockerInventory {
        throw PolicyError.unavailable
    }

    public func revalidate(_ item: CleanupCandidate, evidence: CandidateEvidence) async throws {
        throw PolicyError.unavailable
    }

    public func remove(_ item: CleanupCandidate) async throws {
        throw PolicyError.unavailable
    }
}

/// A journal that keeps sessions in memory and can be told to fail once.
public actor InMemoryJournal: HistoryRepository {
    private var stored: [UUID: HistorySession] = [:]
    private var order: [UUID] = []
    private var failNextBeginCall = false
    private var failNextRecordCall = false
    private var recordedWrites = 0

    public init() {}

    // MARK: - Failure injection

    public func failNextBegin() { failNextBeginCall = true }
    public func failNextRecord() { failNextRecordCall = true }
    public func writeCount() -> Int { recordedWrites }

    // MARK: - CleanupJournal

    public func begin(sessionID: UUID, candidates: [CleanupCandidate], at: Date) async throws {
        if failNextBeginCall {
            failNextBeginCall = false
            throw PolicyError.journalUnavailable
        }
        // Write-ahead: every candidate exists as pending before anything moves.
        let pending = candidates.map {
            CleanupRecord(
                id: $0.id,
                candidate: $0,
                outcome: .pending,
                resultingTrashURL: nil,
                errorCode: nil,
                finishedAt: nil
            )
        }
        stored[sessionID] = HistorySession(
            id: sessionID,
            startedAt: at,
            completedAt: nil,
            summary: nil,
            records: pending
        )
        order.append(sessionID)
    }

    public func record(sessionID: UUID, record: CleanupRecord) async throws {
        if failNextRecordCall {
            failNextRecordCall = false
            throw PolicyError.journalUnavailable
        }
        guard let session = stored[sessionID] else { throw PolicyError.journalUnavailable }
        var records = session.records
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }
        stored[sessionID] = HistorySession(
            id: session.id,
            startedAt: session.startedAt,
            completedAt: session.completedAt,
            summary: session.summary,
            records: records
        )
        recordedWrites += 1
    }

    public func finish(_ summary: CleanupSummary, at: Date) async throws {
        guard let session = stored[summary.sessionID] else {
            throw PolicyError.journalUnavailable
        }
        stored[summary.sessionID] = HistorySession(
            id: session.id,
            startedAt: session.startedAt,
            completedAt: at,
            summary: summary,
            records: session.records
        )
    }

    // MARK: - HistoryRepository

    public func sessions() async throws -> [HistorySession] {
        order.compactMap { stored[$0] }
    }

    public func clear() async throws {
        stored.removeAll()
        order.removeAll()
    }

    public func applyRetention(_ retention: HistoryRetention, now: Date) async throws {
        guard retention != .forever else { return }
        let cutoff = now.addingTimeInterval(-Double(retention.rawValue) * 86_400)
        for id in order where (stored[id]?.startedAt ?? .distantFuture) < cutoff {
            stored[id] = nil
        }
        order = order.filter { stored[$0] != nil }
    }

    public func recoverInterruptedSessions() async throws {
        for id in order {
            guard let session = stored[id], session.completedAt == nil else { continue }
            // A pending row after a restart is never assumed successful.
            let recovered = session.records.map { record in
                record.outcome == .pending
                    ? CleanupRecord(
                        id: record.id,
                        candidate: record.candidate,
                        outcome: .indeterminate,
                        resultingTrashURL: record.resultingTrashURL,
                        errorCode: record.errorCode,
                        finishedAt: record.finishedAt
                    )
                    : record
            }
            stored[id] = HistorySession(
                id: session.id,
                startedAt: session.startedAt,
                completedAt: session.completedAt,
                summary: session.summary,
                records: recovered
            )
        }
    }
}

/// Free space a test states outright, so a summary's observed delta is
/// deterministic instead of depending on the machine running the test.
public actor StubFreeSpace: FreeSpaceObserving {
    private var readings: [Int64?]
    private var index = 0

    public init(readings: [Int64?] = [nil]) {
        self.readings = readings
    }

    public func availableBytes(on url: URL) async -> Int64? {
        defer { index += 1 }
        return index < readings.count ? readings[index] : readings.last ?? nil
    }
}

public enum CleanupCollectorError: Error, Equatable {
    /// The stream ended without a terminal summary.
    case noSummary
}

/// Drains a cleanup stream and returns its terminal summary.
public enum CleanupCollector {
    public static func collect(_ stream: AsyncStream<CleanupEvent>) async throws -> CleanupSummary {
        var summary: CleanupSummary?
        for await event in stream {
            if case .finished(let value) = event { summary = value }
        }
        guard let summary else { throw CleanupCollectorError.noSummary }
        return summary
    }
}
