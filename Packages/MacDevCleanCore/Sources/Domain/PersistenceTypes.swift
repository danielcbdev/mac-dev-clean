import Foundation

public enum AppLanguage: String, Codable, Sendable, CaseIterable {
    case system, english, portugueseBrazil
}

public enum AppAppearance: String, Codable, Sendable, CaseIterable {
    case system, light, dark
}

public enum HistoryRetention: Int, Codable, Sendable, CaseIterable {
    case forever = 0
    case days30 = 30
    case days90 = 90
}

/// User preferences.
///
/// The defaults are deliberately passive: MacDevClean never scans or deletes
/// anything without the user asking.
public struct AppPreferences: Codable, Sendable, Equatable {
    public var scanOnLaunch: Bool = false
    public var largeFileThreshold: UInt64 = 1_000_000_000
    public var language: AppLanguage = .system
    public var appearance: AppAppearance = .system
    public var retention: HistoryRetention = .forever

    public init(
        scanOnLaunch: Bool = false,
        largeFileThreshold: UInt64 = 1_000_000_000,
        language: AppLanguage = .system,
        appearance: AppAppearance = .system,
        retention: HistoryRetention = .forever
    ) {
        self.scanOnLaunch = scanOnLaunch
        self.largeFileThreshold = largeFileThreshold
        self.language = language
        self.appearance = appearance
        self.retention = retention
    }
}

/// One recorded cleanup session. History never stores file contents.
public struct HistorySession: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let startedAt: Date
    public let completedAt: Date?
    public let summary: CleanupSummary?
    public let records: [CleanupRecord]

    public init(
        id: UUID,
        startedAt: Date,
        completedAt: Date?,
        summary: CleanupSummary?,
        records: [CleanupRecord]
    ) {
        self.id = id
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.summary = summary
        self.records = records
    }
}

public protocol SettingsRepository: Sendable {
    func preferences() async throws -> AppPreferences
    func savePreferences(_ value: AppPreferences) async throws
    func roots() async throws -> [ScanRoot]
    func saveRoots(_ value: [ScanRoot]) async throws
    func exclusions() async throws -> [Exclusion]
    func saveExclusions(_ value: [Exclusion]) async throws
}

public protocol HistoryRepository: CleanupJournal {
    func sessions() async throws -> [HistorySession]
    func clear() async throws
    func applyRetention(_ retention: HistoryRetention, now: Date) async throws
    /// Sessions interrupted by a crash or quit become `indeterminate`.
    func recoverInterruptedSessions() async throws
}
