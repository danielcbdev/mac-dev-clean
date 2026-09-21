import Foundation

/// A Large Files analysis request.
///
/// `roots` are folders the user chose for this feature specifically. Project
/// roots grant no Large Files scope, and vice versa.
public struct LargeFileRequest: Sendable, Equatable {
    public let roots: [ScanRoot]
    public let minimumBytes: UInt64

    public init(roots: [ScanRoot], minimumBytes: UInt64) {
        self.roots = roots
        self.minimumBytes = minimumBytes
    }
}

/// One row in the Large Files table.
public struct LargeFileRow: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let url: URL
    public let logicalBytes: UInt64
    public let modifiedAt: Date
    public let kindDescription: String
    /// False for anything that is shown for information only — a symbolic link,
    /// for instance. Such a row has no action and no checkbox.
    public let canSelect: Bool

    public init(
        id: UUID,
        url: URL,
        logicalBytes: UInt64,
        modifiedAt: Date,
        kindDescription: String,
        canSelect: Bool
    ) {
        self.id = id
        self.url = url
        self.logicalBytes = logicalBytes
        self.modifiedAt = modifiedAt
        self.kindDescription = kindDescription
        self.canSelect = canSelect
    }
}

public enum LargeFileEvent: Sendable {
    case progress(Int)
    case issue(String)
    case completed(rows: [LargeFileRow], snapshot: ScanSnapshot)
}

public protocol LargeFileScanning: Sendable {
    func scan(_ request: LargeFileRequest) -> AsyncThrowingStream<LargeFileEvent, Error>
}

/// The thresholds the interface offers. Decimal, matching how the rest of the
/// app formats byte counts.
public enum LargeFileThreshold {
    public static let presets: [UInt64] = [
        100_000_000, 500_000_000, 1_000_000_000, 5_000_000_000, 10_000_000_000,
    ]
    public static let `default`: UInt64 = 1_000_000_000
}
