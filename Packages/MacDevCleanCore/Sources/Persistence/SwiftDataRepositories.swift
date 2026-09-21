import Domain
import Foundation
import SwiftData

public enum PersistenceError: Error, Equatable {
    /// A file-backed store was requested without a location, or an in-memory
    /// store with one.
    case invalidConfiguration
    /// The store exists but could not be opened. The existing file is left
    /// exactly as it is — never deleted, never recreated.
    case storeUnavailable
    /// A session identifier was begun twice. The first one keeps its progress.
    case duplicateSession
}

/// Durable settings, exclusions and cleanup history.
///
/// The whole store is confined to one model actor, so no `ModelContext` crosses
/// an isolation boundary; only `Codable`, `Sendable` snapshots do.
///
/// The single most important property here: **a corrupt store is never erased
/// or recreated.** Opening fails, the caller reports it, and cleanup is disabled
/// because its history could not be recorded. Silently starting a fresh
/// database would destroy the record of what this app had already done.
@ModelActor
public actor SwiftDataRepositories: SettingsRepository, HistoryRepository {

    /// Builds a repository. `containerURL` is required unless `inMemory`.
    public static func make(
        containerURL: URL?,
        inMemory: Bool = false
    ) throws -> SwiftDataRepositories {
        let configuration: ModelConfiguration
        switch (containerURL, inMemory) {
        case (nil, true):
            configuration = ModelConfiguration(
                schema: Schema(versionedSchema: SchemaV1.self), isStoredInMemoryOnly: true)
        case (let url?, false):
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            configuration = ModelConfiguration(
                schema: Schema(versionedSchema: SchemaV1.self), url: url)
        default:
            throw PersistenceError.invalidConfiguration
        }

        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: SchemaV1.self),
                migrationPlan: MacDevCleanMigrationPlan.self,
                configurations: [configuration]
            )
            return SwiftDataRepositories(modelContainer: container)
        } catch {
            // Deliberately not recovered by deleting anything.
            throw PersistenceError.storeUnavailable
        }
    }

    /// True. This is what lets the application enable cleanup: a cleanup whose
    /// record would vanish on quit is not offered.
    public nonisolated var isDurable: Bool { true }

    // MARK: - Preferences

    public func preferences() async throws -> AppPreferences {
        guard let row = try preferenceRow(createIfMissing: false) else { return AppPreferences() }
        // A payload that will not decode is replaced in memory by the defaults,
        // and the row is left alone rather than overwritten.
        return (try? JSONDecoder().decode(AppPreferences.self, from: row.payload))
            ?? AppPreferences()
    }

    public func savePreferences(_ value: AppPreferences) async throws {
        let data = try JSONEncoder().encode(value)
        let row = try preferenceRow(createIfMissing: true)
        row?.payload = data
        try modelContext.save()
    }

    private func preferenceRow(createIfMissing: Bool) throws -> StoredPreferences? {
        let key = StoredPreferences.singletonKey
        var descriptor = FetchDescriptor<StoredPreferences>(
            predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first { return existing }
        guard createIfMissing else { return nil }
        let created = StoredPreferences(payload: try JSONEncoder().encode(AppPreferences()))
        modelContext.insert(created)
        return created
    }

    // MARK: - Roots

    public func roots() async throws -> [ScanRoot] {
        try modelContext
            .fetch(FetchDescriptor<StoredRoot>(sortBy: [SortDescriptor(\.addedAt)]))
            .map { ScanRoot(url: URL(fileURLWithPath: $0.path, isDirectory: false)) }
    }

    public func saveRoots(_ value: [ScanRoot]) async throws {
        let wanted = value.map { $0.url.standardizedFileURL.path }
        let existing = try modelContext.fetch(FetchDescriptor<StoredRoot>())
        for row in existing where !wanted.contains(row.path) {
            modelContext.delete(row)
        }
        let present = Set(existing.map(\.path))
        for path in wanted where !present.contains(path) {
            modelContext.insert(StoredRoot(path: path, addedAt: Date()))
        }
        try modelContext.save()
    }

    // MARK: - Exclusions

    public func exclusions() async throws -> [Exclusion] {
        try modelContext
            .fetch(FetchDescriptor<StoredExclusion>(sortBy: [SortDescriptor(\.addedAt)]))
            .compactMap(Self.decode)
    }

    public func saveExclusions(_ value: [Exclusion]) async throws {
        let wanted = Dictionary(
            value.map { (Self.identifier(for: $0), $0) }, uniquingKeysWith: { first, _ in first })
        let existing = try modelContext.fetch(FetchDescriptor<StoredExclusion>())
        for row in existing where wanted[row.identifier] == nil {
            modelContext.delete(row)
        }
        let present = Set(existing.map(\.identifier))
        for (identifier, exclusion) in wanted where !present.contains(identifier) {
            let parts = Self.parts(of: exclusion)
            _ = identifier
            modelContext.insert(
                StoredExclusion(kind: parts.kind, value: parts.value, addedAt: Date()))
        }
        try modelContext.save()
    }

    private static func parts(of exclusion: Exclusion) -> (kind: String, value: String) {
        switch exclusion {
        // The path is stored exactly as normalised, never lower-cased: a
        // case-sensitive volume would treat a folded path as a different place.
        case .path(let url): return ("path", url.standardizedFileURL.path)
        case .category(let category): return ("category", category.rawValue)
        case .rule(let rule): return ("rule", rule)
        }
    }

    private static func identifier(for exclusion: Exclusion) -> String {
        let parts = parts(of: exclusion)
        return "\(parts.kind):\(parts.value)"
    }

    private static func decode(_ row: StoredExclusion) -> Exclusion? {
        switch row.kind {
        case "path": return .path(URL(fileURLWithPath: row.value, isDirectory: false))
        case "category": return CleanupCategory(rawValue: row.value).map { .category($0) }
        case "rule": return .rule(row.value)
        default:
            // An unrecognised kind is ignored in memory. The row stays on disk:
            // a newer version may understand it, and deleting it would destroy
            // a setting the user made.
            return nil
        }
    }

    // MARK: - Journal

    public func begin(sessionID: UUID, candidates: [CleanupCandidate], at: Date) async throws {
        var descriptor = FetchDescriptor<StoredSession>(
            predicate: #Predicate { $0.id == sessionID })
        descriptor.fetchLimit = 1
        guard try modelContext.fetch(descriptor).isEmpty else {
            // Beginning twice would reset progress already recorded. Refuse.
            throw PersistenceError.duplicateSession
        }

        let session = StoredSession(id: sessionID, startedAt: at)
        modelContext.insert(session)
        for candidate in candidates {
            let record = StoredRecord(
                id: candidate.id,
                outcome: ItemOutcome.pending.rawValue,
                errorCode: nil,
                finishedAt: nil,
                resultingTrashPath: nil,
                candidatePayload: try JSONEncoder().encode(candidate)
            )
            record.session = session
            modelContext.insert(record)
        }
        // Write-ahead: the intent is on disk before anything moves.
        try modelContext.save()
    }

    public func record(sessionID: UUID, record: CleanupRecord) async throws {
        guard let session = try session(sessionID) else {
            throw PolicyError.journalUnavailable
        }
        let recordID = record.id
        let row = session.records.first { $0.id == recordID }
        let payload = try JSONEncoder().encode(record.candidate)

        if let row {
            row.outcome = record.outcome.rawValue
            row.errorCode = record.errorCode
            row.finishedAt = record.finishedAt
            row.resultingTrashPath = record.resultingTrashURL?.path
            row.candidatePayload = payload
        } else {
            let created = StoredRecord(
                id: record.id,
                outcome: record.outcome.rawValue,
                errorCode: record.errorCode,
                finishedAt: record.finishedAt,
                resultingTrashPath: record.resultingTrashURL?.path,
                candidatePayload: payload
            )
            created.session = session
            modelContext.insert(created)
        }
        try modelContext.save()
    }

    public func finish(_ summary: CleanupSummary, at: Date) async throws {
        guard let session = try session(summary.sessionID) else {
            throw PolicyError.journalUnavailable
        }
        session.completedAt = at
        session.bytesMovedToTrash = Int64(
            clamping: Int(summary.bytesMovedToTrash.magnitude))
        session.observedFreeSpaceDelta = summary.observedFreeSpaceDelta
        try modelContext.save()
    }

    private func session(_ id: UUID) throws -> StoredSession? {
        var descriptor = FetchDescriptor<StoredSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    // MARK: - History

    public func sessions() async throws -> [HistorySession] {
        try modelContext
            .fetch(
                FetchDescriptor<StoredSession>(
                    sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
            )
            .map(Self.present)
    }

    public func clear() async throws {
        // Only history. Preferences, roots and exclusions are untouched, and no
        // file anywhere is affected: emptying the Trash is Finder's job.
        for session in try modelContext.fetch(FetchDescriptor<StoredSession>()) {
            modelContext.delete(session)
        }
        try modelContext.save()
    }

    public func applyRetention(_ retention: HistoryRetention, now: Date) async throws {
        guard retention != .forever else { return }
        let cutoff = now.addingTimeInterval(-Double(retention.rawValue) * 86_400)
        for session in try modelContext.fetch(FetchDescriptor<StoredSession>()) {
            // Only completed sessions expire. One still in progress, or one
            // whose outcome nobody knows, is kept however old it is.
            guard let completedAt = session.completedAt, completedAt < cutoff else { continue }
            modelContext.delete(session)
        }
        try modelContext.save()
    }

    public func recoverInterruptedSessions() async throws {
        let pending = ItemOutcome.pending.rawValue
        let rows = try modelContext.fetch(
            FetchDescriptor<StoredRecord>(predicate: #Predicate { $0.outcome == pending }))
        guard !rows.isEmpty else { return }
        for row in rows {
            // Never assumed successful, never assumed failed, and never retried:
            // nothing here touches the filesystem or Docker.
            row.outcome = ItemOutcome.indeterminate.rawValue
            row.errorCode = "session.interrupted"
        }
        try modelContext.save()
    }

    /// Test seam: writes a record whose payload cannot be decoded, so the
    /// "one bad row must not hide a session" behaviour can be exercised without
    /// corrupting a file by hand.
    func insertCorruptRecord(sessionID: UUID) throws {
        guard let session = try session(sessionID) else {
            throw PolicyError.journalUnavailable
        }
        let row = StoredRecord(
            id: UUID(),
            outcome: ItemOutcome.movedToTrash.rawValue,
            errorCode: nil,
            finishedAt: nil,
            resultingTrashPath: nil,
            candidatePayload: Data("not a candidate".utf8)
        )
        row.session = session
        modelContext.insert(row)
        try modelContext.save()
    }

    // MARK: - Presentation

    private static func present(_ session: StoredSession) -> HistorySession {
        let records = session.records
            .sorted { ($0.finishedAt ?? .distantFuture) < ($1.finishedAt ?? .distantFuture) }
            .map(presentRecord)
        return HistorySession(
            id: session.id,
            startedAt: session.startedAt,
            completedAt: session.completedAt,
            summary: session.completedAt.map { _ in
                CleanupSummary(
                    sessionID: session.id,
                    records: records,
                    bytesMovedToTrash: UInt64(max(0, session.bytesMovedToTrash)),
                    observedFreeSpaceDelta: session.observedFreeSpaceDelta
                )
            },
            records: records
        )
    }

    private static func presentRecord(_ row: StoredRecord) -> CleanupRecord {
        let candidate =
            (try? JSONDecoder().decode(CleanupCandidate.self, from: row.candidatePayload))
            ?? unreadableCandidate(id: row.id)
        return CleanupRecord(
            id: row.id,
            candidate: candidate,
            outcome: ItemOutcome(rawValue: row.outcome) ?? .indeterminate,
            resultingTrashURL: row.resultingTrashPath.map {
                URL(fileURLWithPath: $0, isDirectory: false)
            },
            errorCode: candidate.ruleID == unreadableRuleID
                ? unreadableRuleID : row.errorCode,
            finishedAt: row.finishedAt
        )
    }

    /// Stands in for a record whose payload will not decode.
    ///
    /// The row stays on disk untouched and the entry appears in history marked
    /// unreadable, so one bad record cannot hide a whole session.
    static let unreadableRuleID = "record.unreadable"

    private static func unreadableCandidate(id: UUID) -> CleanupCandidate {
        CleanupCandidate(
            id: id,
            ruleID: unreadableRuleID,
            location: .file(URL(fileURLWithPath: "/", isDirectory: false)),
            category: .largeFiles,
            size: nil,
            allocatedSize: nil,
            risk: .high,
            method: .trash,
            consequenceKey: ConsequenceKey.userSelectedFile
        )
    }
}
