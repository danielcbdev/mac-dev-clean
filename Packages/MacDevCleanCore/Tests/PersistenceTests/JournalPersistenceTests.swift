import Domain
import TestSupport
import XCTest

@testable import Persistence

final class JournalPersistenceTests: XCTestCase {

    func testBeginWritesEveryCandidateAsPendingBeforeAnythingMoves() async throws {
        let repository = try SwiftDataRepositories.make(containerURL: nil, inMemory: true)
        let sessionID = UUID()
        let candidates = [Self.candidate(), Self.candidate()]

        try await repository.begin(
            sessionID: sessionID, candidates: candidates, at: Self.start)

        let stored = try await repository.sessions()
        let session = try XCTUnwrap(stored.first)
        XCTAssertEqual(session.records.count, 2)
        XCTAssertTrue(session.records.allSatisfy { $0.outcome == .pending })
        XCTAssertNil(session.completedAt)
        XCTAssertNil(session.summary, "an unfinished session has no summary")
    }

    func testBeginningTheSameSessionTwiceIsRefused() async throws {
        let repository = try SwiftDataRepositories.make(containerURL: nil, inMemory: true)
        let sessionID = UUID()
        try await repository.begin(
            sessionID: sessionID, candidates: [Self.candidate()], at: Self.start)

        do {
            try await repository.begin(
                sessionID: sessionID, candidates: [Self.candidate()], at: Self.start)
            XCTFail("beginning twice would reset progress already recorded")
        } catch {
            XCTAssertEqual(error as? PersistenceError, .duplicateSession)
        }
    }

    func testAnInterruptedSessionBecomesIndeterminateAndIsNeverRemoved() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let store = tree.root.appendingPathComponent("store/macdevclean.sqlite")
        let sessionID = UUID()
        let candidate = Self.candidate()

        do {
            let repository = try SwiftDataRepositories.make(containerURL: store)
            try await repository.begin(
                sessionID: sessionID, candidates: [candidate], at: Self.start)
            // The app is quit here: nothing records an outcome.
        }

        let reopened = try SwiftDataRepositories.make(containerURL: store)
        try await reopened.recoverInterruptedSessions()
        let stored = try await reopened.sessions()
        let session = try XCTUnwrap(stored.first)
        let record = try XCTUnwrap(session.records.first)

        XCTAssertEqual(record.outcome, .indeterminate)
        XCTAssertEqual(record.errorCode, "session.interrupted")
        XCTAssertNotEqual(record.outcome, .movedToTrash, "never assumed successful")
        XCTAssertNotEqual(record.outcome, .failed, "never assumed failed either")
    }

    func testOutcomesAndSummarySurviveAReopen() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let store = tree.root.appendingPathComponent("store/macdevclean.sqlite")
        let sessionID = UUID()
        let candidate = Self.candidate(size: 4_096)

        do {
            let repository = try SwiftDataRepositories.make(containerURL: store)
            try await repository.begin(
                sessionID: sessionID, candidates: [candidate], at: Self.start)
            let record = CleanupRecord(
                id: candidate.id,
                candidate: candidate,
                outcome: .movedToTrash,
                resultingTrashURL: URL(fileURLWithPath: "/fixture/Trash/payload"),
                errorCode: nil,
                finishedAt: Self.start.addingTimeInterval(1)
            )
            try await repository.record(sessionID: sessionID, record: record)
            try await repository.finish(
                CleanupSummary(
                    sessionID: sessionID, records: [record], bytesMovedToTrash: 4_096,
                    observedFreeSpaceDelta: -1_000),
                at: Self.start.addingTimeInterval(2))
        }

        let reopened = try SwiftDataRepositories.make(containerURL: store)
        let stored = try await reopened.sessions()
        let session = try XCTUnwrap(stored.first)

        XCTAssertEqual(session.records.first?.outcome, .movedToTrash)
        XCTAssertEqual(session.summary?.bytesMovedToTrash, 4_096)
        XCTAssertEqual(
            session.summary?.observedFreeSpaceDelta, -1_000,
            "a negative observation is stored as measured")
        XCTAssertNotNil(session.records.first?.resultingTrashURL)
    }

    func testRecordingIntoAnUnknownSessionFails() async throws {
        let repository = try SwiftDataRepositories.make(containerURL: nil, inMemory: true)
        let candidate = Self.candidate()

        do {
            try await repository.record(
                sessionID: UUID(),
                record: CleanupRecord(
                    id: candidate.id, candidate: candidate, outcome: .movedToTrash,
                    resultingTrashURL: nil, errorCode: nil, finishedAt: Self.start))
            XCTFail("expected a journal failure")
        } catch {
            XCTAssertEqual(error as? PolicyError, .journalUnavailable)
        }
    }

    func testAnUnreadableRecordDoesNotHideTheRestOfTheSession() async throws {
        let repository = try SwiftDataRepositories.make(containerURL: nil, inMemory: true)
        let sessionID = UUID()
        let good = Self.candidate()
        try await repository.begin(sessionID: sessionID, candidates: [good], at: Self.start)

        // A record whose payload cannot be decoded at all.
        try await repository.insertCorruptRecord(sessionID: sessionID)

        let stored = try await repository.sessions()
        let session = try XCTUnwrap(stored.first)

        XCTAssertEqual(session.records.count, 2, "the good record is still there")
        XCTAssertTrue(
            session.records.contains { $0.candidate.ruleID == "record.unreadable" },
            "the unreadable entry is shown rather than dropped")
    }

    func testHistoryNeverStoresFileContents() async throws {
        let repository = try SwiftDataRepositories.make(containerURL: nil, inMemory: true)
        let sessionID = UUID()
        try await repository.begin(
            sessionID: sessionID, candidates: [Self.candidate()], at: Self.start)

        let stored = try await repository.sessions()
        let session = try XCTUnwrap(stored.first)
        let candidate = try XCTUnwrap(session.records.first?.candidate)

        // Only metadata: identifier, rule, location, size, risk, method.
        XCTAssertEqual(candidate.ruleID, "node.modules")
        XCTAssertNotNil(candidate.size)
    }

    // MARK: - Helpers

    static let start = Date(timeIntervalSince1970: 1_700_000_000)

    static func candidate(size: UInt64? = 1_024) -> CleanupCandidate {
        CleanupCandidate(
            id: UUID(),
            ruleID: "node.modules",
            location: .file(URL(fileURLWithPath: "/fixture/app/node_modules")),
            category: .node,
            size: size,
            allocatedSize: size,
            risk: .low,
            method: .trash,
            consequenceKey: ConsequenceKey.reinstallDependencies
        )
    }
}
