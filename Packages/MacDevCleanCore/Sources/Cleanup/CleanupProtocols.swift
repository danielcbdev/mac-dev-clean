import Domain
import Foundation

/// One reason a selected candidate cannot be cleaned, for the interface to
/// present. Nothing is ever dropped silently.
public struct ValidationIssue: Sendable, Equatable {
    public let candidateID: UUID
    public let code: PolicyError

    public init(candidateID: UUID, code: PolicyError) {
        self.candidateID = candidateID
        self.code = code
    }
}

public protocol CleanupPlanValidating: Sendable {
    /// Builds an authorisation, or throws the reason the selection cannot be
    /// authorised. A partially valid selection never becomes a partial plan.
    func validate(_ selection: CleanupSelection) async throws -> ValidatedCleanupPlan

    /// Every reason the selection would be refused, without throwing, so the
    /// interface can explain the situation and offer a rescan.
    func inspect(_ selection: CleanupSelection) async -> [ValidationIssue]
}

public enum CleanupEvent: Sendable {
    case started(UUID)
    case item(CleanupRecord)
    case finished(CleanupSummary)
}

public protocol CleanupExecuting: Sendable {
    func execute(_ plan: ValidatedCleanupPlan) -> AsyncStream<CleanupEvent>
}
