import Domain
import TestSupport
import XCTest

@testable import Persistence

final class RetentionTests: XCTestCase {

    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testRetentionKeepsASessionExactlyAtTheBoundary() async throws {
        let repository = try SwiftDataRepositories.make(containerURL: nil, inMemory: true)
        let exactly30 = Self.now.addingTimeInterval(-30 * 86_400)
        let justOlder = Self.now.addingTimeInterval(-30 * 86_400 - 1)
        let keptID = try await Self.completed(repository, at: exactly30)
        let droppedID = try await Self.completed(repository, at: justOlder)

        try await repository.applyRetention(.days30, now: Self.now)

        let remaining = Set(try await repository.sessions().map(\.id))
        XCTAssertTrue(remaining.contains(keptID), "exactly at the cutoff is kept")
        XCTAssertFalse(remaining.contains(droppedID))
    }

    func testForeverRemovesNothing() async throws {
        let repository = try SwiftDataRepositories.make(containerURL: nil, inMemory: true)
        _ = try await Self.completed(repository, at: Self.now.addingTimeInterval(-3_650 * 86_400))

        try await repository.applyRetention(.forever, now: Self.now)

        let hoisted4 = try await repository.sessions().count
        XCTAssertEqual(hoisted4, 1)
    }

    func testAnUnfinishedSessionIsKeptHoweverOldItIs() async throws {
        let repository = try SwiftDataRepositories.make(containerURL: nil, inMemory: true)
        let sessionID = UUID()
        try await repository.begin(
            sessionID: sessionID,
            candidates: [JournalPersistenceTests.candidate()],
            at: Self.now.addingTimeInterval(-3_650 * 86_400))

        try await repository.applyRetention(.days30, now: Self.now)

        let remaining = try await repository.sessions()
        XCTAssertEqual(
            remaining.count, 1,
            "a session whose outcome nobody knows is not quietly discarded")
    }

    func testClearingHistoryLeavesPreferencesRootsAndExclusionsAlone() async throws {
        let repository = try SwiftDataRepositories.make(containerURL: nil, inMemory: true)
        var preferences = AppPreferences()
        preferences.retention = .days90
        try await repository.savePreferences(preferences)
        try await repository.saveRoots([ScanRoot(url: URL(fileURLWithPath: "/fixture/work"))])
        try await repository.saveExclusions([.rule("node.modules")])
        _ = try await Self.completed(repository, at: Self.now)

        try await repository.clear()

        let hoisted5 = try await repository.sessions().isEmpty
        XCTAssertTrue(hoisted5)
        let hoisted6 = try await repository.preferences().retention
        XCTAssertEqual(hoisted6, .days90)
        let hoisted7 = try await repository.roots().count
        XCTAssertEqual(hoisted7, 1)
        let hoisted8 = try await repository.exclusions().count
        XCTAssertEqual(hoisted8, 1)
    }

    // MARK: - Helpers

    @discardableResult
    private static func completed(
        _ repository: SwiftDataRepositories,
        at date: Date
    ) async throws -> UUID {
        let sessionID = UUID()
        let candidate = JournalPersistenceTests.candidate()
        try await repository.begin(sessionID: sessionID, candidates: [candidate], at: date)
        let record = CleanupRecord(
            id: candidate.id, candidate: candidate, outcome: .movedToTrash,
            resultingTrashURL: nil, errorCode: nil, finishedAt: date)
        try await repository.record(sessionID: sessionID, record: record)
        try await repository.finish(
            CleanupSummary(
                sessionID: sessionID, records: [record], bytesMovedToTrash: 0,
                observedFreeSpaceDelta: nil),
            at: date)
        return sessionID
    }
}
