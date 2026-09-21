import Domain
import Foundation
import SwiftData

/// The stored shape, version 1.
///
/// Everything is stored as identifiers, dates, raw enumeration strings and
/// bounded encoded payloads. Nothing stores file contents, and nothing stores a
/// translated string — a language setting is `portugueseBrazil`, never
/// "Português (Brasil)", so changing the interface language cannot corrupt it.
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            StoredPreferences.self,
            StoredRoot.self,
            StoredExclusion.self,
            StoredSession.self,
            StoredRecord.self,
        ]
    }
}

/// The migration plan.
///
/// One version, and no invented future stages. A stage is added when a schema
/// change actually happens, together with the test that proves data survives
/// it.
public enum MacDevCleanMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

/// Preferences, held as one row so a partial write cannot leave a half-changed
/// settings state.
@Model
public final class StoredPreferences {
    /// Fixed key for the single row. Unique, so a second row cannot appear.
    @Attribute(.unique) public var key: String
    public var payload: Data

    public init(key: String = StoredPreferences.singletonKey, payload: Data) {
        self.key = key
        self.payload = payload
    }

    public static let singletonKey = "preferences"
}

@Model
public final class StoredRoot {
    @Attribute(.unique) public var path: String
    public var addedAt: Date

    public init(path: String, addedAt: Date) {
        self.path = path
        self.addedAt = addedAt
    }
}

@Model
public final class StoredExclusion {
    /// `kind:value`, unique so the same exclusion cannot be stored twice.
    @Attribute(.unique) public var identifier: String
    /// `path`, `category` or `rule`.
    public var kind: String
    public var value: String
    public var addedAt: Date

    public init(kind: String, value: String, addedAt: Date) {
        identifier = "\(kind):\(value)"
        self.kind = kind
        self.value = value
        self.addedAt = addedAt
    }
}

@Model
public final class StoredSession {
    @Attribute(.unique) public var id: UUID
    public var startedAt: Date
    public var completedAt: Date?
    public var bytesMovedToTrash: Int64
    public var observedFreeSpaceDelta: Int64?

    @Relationship(deleteRule: .cascade, inverse: \StoredRecord.session)
    public var records: [StoredRecord]

    public init(
        id: UUID,
        startedAt: Date,
        completedAt: Date? = nil,
        bytesMovedToTrash: Int64 = 0,
        observedFreeSpaceDelta: Int64? = nil,
        records: [StoredRecord] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.bytesMovedToTrash = bytesMovedToTrash
        self.observedFreeSpaceDelta = observedFreeSpaceDelta
        self.records = records
    }
}

@Model
public final class StoredRecord {
    @Attribute(.unique) public var id: UUID
    /// Raw `ItemOutcome` value.
    public var outcome: String
    public var errorCode: String?
    public var finishedAt: Date?
    /// Where the Trash reported the item landed. A path, kept only so "Show in
    /// Trash" can check whether it still resolves.
    public var resultingTrashPath: String?
    /// The candidate, JSON-encoded. Never file contents.
    public var candidatePayload: Data
    public var session: StoredSession?

    public init(
        id: UUID,
        outcome: String,
        errorCode: String?,
        finishedAt: Date?,
        resultingTrashPath: String?,
        candidatePayload: Data
    ) {
        self.id = id
        self.outcome = outcome
        self.errorCode = errorCode
        self.finishedAt = finishedAt
        self.resultingTrashPath = resultingTrashPath
        self.candidatePayload = candidatePayload
    }
}
