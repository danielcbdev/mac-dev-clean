import Domain
import Foundation

public enum ScanCollectorError: Error, Equatable {
    /// The stream ended without a `completed` event. A scan that produced no
    /// terminal snapshot is a failure, not an empty result.
    case noCompletedEvent
}

/// Drains a scan stream and returns its terminal snapshot.
public enum ScanCollector {
    /// All events seen, in order, alongside the snapshot.
    public struct Result: Sendable {
        public let snapshot: ScanSnapshot
        public let progressUpdates: [Int]
        public let issueCodes: [String]
    }

    public static func collect(
        _ stream: AsyncThrowingStream<ScanEvent, Error>
    ) async throws -> ScanSnapshot {
        try await drain(stream).snapshot
    }

    public static func drain(
        _ stream: AsyncThrowingStream<ScanEvent, Error>
    ) async throws -> Result {
        var snapshot: ScanSnapshot?
        var progressUpdates: [Int] = []
        var issueCodes: [String] = []

        for try await event in stream {
            switch event {
            case .progress(let visited):
                progressUpdates.append(visited)
            case .issue(let code, _):
                issueCodes.append(code)
            case .completed(let value):
                snapshot = value
            }
        }

        guard let snapshot else { throw ScanCollectorError.noCompletedEvent }
        return Result(
            snapshot: snapshot,
            progressUpdates: progressUpdates,
            issueCodes: issueCodes
        )
    }
}
