import Domain
import Foundation

public enum MeasurementError: Error, Equatable {
    /// Byte totals exceeded what can be represented. The total is reported as
    /// unknown rather than wrapped around into a small, confident lie.
    case overflow
}

/// Sums file sizes without double counting and without wrapping around.
///
/// Two properties matter more than speed here:
///
/// - **Hard links are counted once.** The same data reachable through several
///   names occupies one set of bytes. Counting each name would inflate the
///   number the user is shown.
/// - **Unknown stays unknown.** A file whose size could not be read does not
///   silently contribute zero. The accumulator remembers that something was
///   unmeasurable, and the reported total becomes `nil`.
public struct SizeAccumulator: Sendable {
    private struct FileKey: Hashable {
        let device: UInt64
        let inode: UInt64
    }

    /// The running sum of everything successfully measured.
    public private(set) var logicalBytes: UInt64 = 0
    /// The running sum of allocated space, where the filesystem reported it.
    public private(set) var allocatedBytes: UInt64 = 0
    /// True once anything could not be measured.
    public private(set) var hasUnknownSizes = false
    /// How many distinct files were counted.
    public private(set) var countedFiles = 0

    private var seen: Set<FileKey> = []

    public init() {}

    /// The total to present, or `nil` when part of it could not be measured.
    public var reportedLogicalBytes: ByteCount? {
        hasUnknownSizes ? nil : logicalBytes
    }

    /// The allocated total to present, or `nil` when part of it is unknown.
    public var reportedAllocatedBytes: ByteCount? {
        hasUnknownSizes ? nil : allocatedBytes
    }

    /// Adds one entry. Repeating an identity — a hard link — changes nothing.
    ///
    /// On overflow the accumulator is left at its last valid value and the call
    /// throws; nothing is partially applied.
    public mutating func add(
        logical: UInt64?,
        allocated: UInt64?,
        identity: FileIdentity
    ) throws {
        let key = FileKey(device: identity.device, inode: identity.inode)
        guard seen.insert(key).inserted else { return }

        countedFiles += 1

        guard let logical, let allocated else {
            hasUnknownSizes = true
            return
        }

        let (nextLogical, logicalOverflow) = logicalBytes.addingReportingOverflow(logical)
        guard !logicalOverflow else { throw MeasurementError.overflow }
        let (nextAllocated, allocatedOverflow) = allocatedBytes.addingReportingOverflow(allocated)
        guard !allocatedOverflow else { throw MeasurementError.overflow }

        logicalBytes = nextLogical
        allocatedBytes = nextAllocated
    }

    /// Records that something could not be measured at all.
    public mutating func noteUnknown() {
        hasUnknownSizes = true
    }
}
