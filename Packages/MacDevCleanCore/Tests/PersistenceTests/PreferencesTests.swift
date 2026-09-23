import Domain
import TestSupport
import XCTest

@testable import Persistence

final class PreferencesTests: XCTestCase {

    func testPreferencesRoundTrip() async throws {
        let repository = try SwiftDataRepositories.make(containerURL: nil, inMemory: true)
        var preferences = AppPreferences()
        preferences.language = .portugueseBrazil
        preferences.scanOnLaunch = true
        try await repository.savePreferences(preferences)
        let restored = try await repository.preferences()
        XCTAssertEqual(restored, preferences)
    }

    func testDefaultsAreReturnedBeforeAnythingIsSaved() async throws {
        let repository = try SwiftDataRepositories.make(containerURL: nil, inMemory: true)

        let preferences = try await repository.preferences()

        XCTAssertEqual(preferences, AppPreferences())
        XCTAssertFalse(preferences.scanOnLaunch, "nothing scans on launch by default")
    }

    func testSettingsSurviveAFreshContainerOnTheSameFile() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let store = tree.root.appendingPathComponent("store/macdevclean.sqlite")

        do {
            let repository = try SwiftDataRepositories.make(containerURL: store)
            var preferences = AppPreferences()
            preferences.retention = .days30
            preferences.appearance = .dark
            try await repository.savePreferences(preferences)
            try await repository.saveRoots([
                ScanRoot(url: tree.root.appendingPathComponent("work"))
            ])
            try await repository.saveExclusions([
                .path(tree.root.appendingPathComponent("work/keep")),
                .category(.docker),
                .rule("node.modules"),
            ])
        }

        // A completely new container over the same file.
        let reopened = try SwiftDataRepositories.make(containerURL: store)

        let preferences = try await reopened.preferences()
        XCTAssertEqual(preferences.retention, .days30)
        XCTAssertEqual(preferences.appearance, .dark)
        let restoredRoots = try await reopened.roots()
        XCTAssertEqual(restoredRoots.map(\.url.lastPathComponent), ["work"])
        let restoredExclusions = try await reopened.exclusions()
        XCTAssertEqual(Set(restoredExclusions).count, 3)
    }

    func testAnInMemoryStoreCannotBeGivenALocation() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }

        XCTAssertThrowsError(
            try SwiftDataRepositories.make(
                containerURL: tree.root.appendingPathComponent("x.sqlite"), inMemory: true)
        ) { error in
            XCTAssertEqual(error as? PersistenceError, .invalidConfiguration)
        }
        XCTAssertThrowsError(
            try SwiftDataRepositories.make(containerURL: nil, inMemory: false)
        ) { error in
            XCTAssertEqual(error as? PersistenceError, .invalidConfiguration)
        }
    }

    func testACorruptStoreFailsToOpenAndIsNotDestroyed() async throws {
        let tree = try FixtureTree()
        defer { try? tree.close() }
        let store = try tree.directory("store").appendingPathComponent("macdevclean.sqlite")
        let garbage = Data("this is not a database, it is something else entirely".utf8)
        try garbage.write(to: store)

        XCTAssertThrowsError(try SwiftDataRepositories.make(containerURL: store)) { error in
            XCTAssertEqual(error as? PersistenceError, .storeUnavailable)
        }

        // The point: the existing file is still exactly where it was, byte for
        // byte. Silently recreating it would destroy the record of what this
        // app had already done.
        XCTAssertEqual(try Data(contentsOf: store), garbage)
    }

    func testRootsAreReplacedWholesaleRatherThanAccumulating() async throws {
        let repository = try SwiftDataRepositories.make(containerURL: nil, inMemory: true)
        let a = URL(fileURLWithPath: "/fixture/a")
        let b = URL(fileURLWithPath: "/fixture/b")

        try await repository.saveRoots([ScanRoot(url: a), ScanRoot(url: b)])
        try await repository.saveRoots([ScanRoot(url: b)])

        let hoisted2 = try await repository.roots().map(\.url.path)
        XCTAssertEqual(hoisted2, ["/fixture/b"])
    }

    func testAPathExclusionKeepsItsExactCase() async throws {
        let repository = try SwiftDataRepositories.make(containerURL: nil, inMemory: true)
        let mixed = URL(fileURLWithPath: "/fixture/Work/KeepThis")

        try await repository.saveExclusions([.path(mixed)])

        guard case .path(let restored) = try await repository.exclusions().first else {
            return XCTFail("expected a path exclusion")
        }
        XCTAssertEqual(
            restored.path, "/fixture/Work/KeepThis",
            "a case-sensitive volume would treat a folded path as a different place")
    }

    func testTheSameExclusionIsNotStoredTwice() async throws {
        let repository = try SwiftDataRepositories.make(containerURL: nil, inMemory: true)
        let exclusion = Exclusion.rule("node.modules")

        try await repository.saveExclusions([exclusion, exclusion])

        let hoisted3 = try await repository.exclusions().count
        XCTAssertEqual(hoisted3, 1)
    }
}
