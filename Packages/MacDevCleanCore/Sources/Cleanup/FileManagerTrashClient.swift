import Domain
import Foundation

/// The only filesystem removal mechanism in the product.
///
/// It calls `FileManager.trashItem(at:resultingItemURL:)` and nothing else.
/// There is no fallback to `removeItem`, no `unlink`, and no way to empty the
/// Trash: if the Trash is unavailable, the item stays where it is.
public struct FileManagerTrashClient: TrashClient {
    private let queue: DispatchQueue

    public init() {
        queue = DispatchQueue(
            label: "dev.macdevclean.trash",
            qos: .utility,
            autoreleaseFrequency: .workItem
        )
    }

    public func moveToTrash(_ url: URL) async throws -> URL {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<URL, Error>) in
            queue.async {
                continuation.resume(with: Result { try Self.trash(url) })
            }
        }
    }

    private static func trash(_ url: URL) throws -> URL {
        var resultingURL: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        } catch let error as NSError {
            throw translate(error)
        }

        guard let result = resultingURL as URL? else {
            // The move already happened. Not knowing where it landed is a
            // reporting gap, never a reason to move it again.
            throw TrashOutcomeError.movedButResultingLocationUnknown
        }
        return result
    }

    private static func translate(_ error: NSError) -> any Error {
        switch error.code {
        case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
            return PolicyError.missing
        case NSFileWriteNoPermissionError, NSFileReadNoPermissionError:
            return PolicyError.permissionDenied
        default:
            return PolicyError.unavailable
        }
    }
}

/// Reads free space on the volume containing a path.
public struct VolumeFreeSpace: FreeSpaceObserving {
    public init() {}

    public func availableBytes(on url: URL) async -> Int64? {
        let values = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
