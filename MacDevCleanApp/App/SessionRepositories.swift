import Domain
import Foundation

/// Settings and history kept in memory for the duration of one launch.
///
/// This is the intermediate arrangement: it lets the shell be exercised end to
/// end before durable storage exists. Because it is **not** durable, the app
/// refuses to perform real cleanup while this is the composed journal — a
/// cleanup whose record would vanish on quit is not something to offer.
/// Plan 07 replaces it with SwiftData.
actor SessionRepositories: SettingsRepository, HistoryRepository {
    private var storedPreferences = AppPreferences()
    private var storedRoots: [ScanRoot] = []
    private var storedExclusions: [Exclusion] = []
    private var sessionsByID: [UUID: HistorySession] = [:]
    private var order: [UUID] = []

    init(roots: [ScanRoot] = [], preferences: AppPreferences = AppPreferences()) {
        storedRoots = roots
        storedPreferences = preferences
    }

    /// False, always. The caller uses this to decide whether real side effects
    /// may be offered at all.
    nonisolated var isDurable: Bool { false }

    // MARK: - SettingsRepository

    func preferences() async throws -> AppPreferences { storedPreferences }
    func savePreferences(_ value: AppPreferences) async throws { storedPreferences = value }
    func roots() async throws -> [ScanRoot] { storedRoots }
    func saveRoots(_ value: [ScanRoot]) async throws { storedRoots = value }
    func exclusions() async throws -> [Exclusion] { storedExclusions }
    func saveExclusions(_ value: [Exclusion]) async throws { storedExclusions = value }

    // MARK: - CleanupJournal

    func begin(sessionID: UUID, candidates: [CleanupCandidate], at: Date) async throws {
        sessionsByID[sessionID] = HistorySession(
            id: sessionID,
            startedAt: at,
            completedAt: nil,
            summary: nil,
            records: candidates.map {
                CleanupRecord(
                    id: $0.id, candidate: $0, outcome: .pending,
                    resultingTrashURL: nil, errorCode: nil, finishedAt: nil)
            }
        )
        order.append(sessionID)
    }

    func record(sessionID: UUID, record: CleanupRecord) async throws {
        guard let session = sessionsByID[sessionID] else {
            throw PolicyError.journalUnavailable
        }
        var records = session.records
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }
        sessionsByID[sessionID] = HistorySession(
            id: session.id, startedAt: session.startedAt, completedAt: session.completedAt,
            summary: session.summary, records: records)
    }

    func finish(_ summary: CleanupSummary, at: Date) async throws {
        guard let session = sessionsByID[summary.sessionID] else {
            throw PolicyError.journalUnavailable
        }
        sessionsByID[summary.sessionID] = HistorySession(
            id: session.id, startedAt: session.startedAt, completedAt: at,
            summary: summary, records: session.records)
    }

    // MARK: - HistoryRepository

    func sessions() async throws -> [HistorySession] { order.compactMap { sessionsByID[$0] } }

    func clear() async throws {
        sessionsByID.removeAll()
        order.removeAll()
    }

    func applyRetention(_ retention: HistoryRetention, now: Date) async throws {
        guard retention != .forever else { return }
        let cutoff = now.addingTimeInterval(-Double(retention.rawValue) * 86_400)
        for id in order where (sessionsByID[id]?.startedAt ?? .distantFuture) < cutoff {
            sessionsByID[id] = nil
        }
        order = order.filter { sessionsByID[$0] != nil }
    }

    func recoverInterruptedSessions() async throws {
        // Nothing survives a launch here, so there is nothing to recover. Said
        // out loud rather than left as an empty body.
    }
}
