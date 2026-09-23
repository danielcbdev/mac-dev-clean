import Domain
import TestSupport
import XCTest

@testable import MacDevClean

@MainActor
final class LargeFilesModelTests: XCTestCase {

    func testNothingIsScannedUntilTheUserChoosesFolders() async throws {
        let scanner = ReplayLargeFileScanner(events: [])
        let model = Self.model(scanner: scanner, picker: StubPicker(folders: []))

        await model.chooseAndScan()

        let runs = await scanner.runCount()
        XCTAssertEqual(runs, 0, "cancelling the picker must not start a scan")
        XCTAssertTrue(model.chosenFolders.isEmpty)
    }

    func testCancellingThePickerPreservesPreviousResults() async throws {
        let rows = [Self.row(name: "a.bin", bytes: 900)]
        let scanner = ReplayLargeFileScanner(
            events: [.completed(rows: rows, snapshot: Self.snapshot(rows))])
        let model = Self.model(
            scanner: scanner, picker: StubPicker(folders: [Self.folder]))

        await model.chooseAndScan()
        try await Self.settle(model)
        XCTAssertEqual(model.rows.count, 1)

        // The user opens the picker again and cancels.
        let cancelling = Self.model(scanner: scanner, picker: StubPicker(folders: []))
        cancelling.adopt(rows: model.rows, snapshot: model.snapshot)
        await cancelling.chooseAndScan()

        XCTAssertEqual(cancelling.rows.count, 1, "previous results survive a cancelled picker")
    }

    func testAScanSelectsNothing() async throws {
        let rows = [Self.row(name: "a.bin", bytes: 900), Self.row(name: "b.bin", bytes: 800)]
        let model = Self.model(
            scanner: ReplayLargeFileScanner(
                events: [.completed(rows: rows, snapshot: Self.snapshot(rows))]),
            picker: StubPicker(folders: [Self.folder]))

        await model.chooseAndScan()
        try await Self.settle(model)

        XCTAssertEqual(model.rows.count, 2)
        XCTAssertTrue(model.selectedIDs.isEmpty)
    }

    func testChangingTheThresholdClearsResultsAndSelection() async throws {
        let rows = [Self.row(name: "a.bin", bytes: 900)]
        let model = Self.model(
            scanner: ReplayLargeFileScanner(
                events: [.completed(rows: rows, snapshot: Self.snapshot(rows))]),
            picker: StubPicker(folders: [Self.folder]))
        await model.chooseAndScan()
        try await Self.settle(model)
        model.toggle(model.rows[0])
        XCTAssertFalse(model.selectedIDs.isEmpty)

        model.minimumBytes = 5_000_000_000

        XCTAssertTrue(model.rows.isEmpty, "results were gathered under a different question")
        XCTAssertNil(model.snapshot)
        XCTAssertTrue(model.selectedIDs.isEmpty)
    }

    func testAnInformationalRowCannotBeSelected() async throws {
        let link = LargeFileRow(
            id: UUID(), url: Self.folder.appendingPathComponent("alias"),
            logicalBytes: 900, modifiedAt: Date(timeIntervalSince1970: 0),
            kindDescription: "Alias", canSelect: false)
        let model = Self.model(
            scanner: ReplayLargeFileScanner(
                events: [.completed(rows: [link], snapshot: Self.snapshot([]))]),
            picker: StubPicker(folders: [Self.folder]))
        await model.chooseAndScan()
        try await Self.settle(model)

        model.toggle(link)

        XCTAssertTrue(model.selectedIDs.isEmpty)
        XCTAssertEqual(model.informationalRowCount, 1)
    }

    func testSortingIsStableAndNeverChangesTheSelection() async throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let first = LargeFileRow(
            id: UUID(), url: Self.folder.appendingPathComponent("b/same.bin"),
            logicalBytes: 1_000, modifiedAt: base, kindDescription: "Document", canSelect: true)
        let second = LargeFileRow(
            id: UUID(), url: Self.folder.appendingPathComponent("a/same.bin"),
            logicalBytes: 1_000, modifiedAt: base, kindDescription: "Document", canSelect: true)
        let model = Self.model(
            scanner: ReplayLargeFileScanner(
                events: [
                    .completed(rows: [first, second], snapshot: Self.snapshot([first, second]))
                ]),
            picker: StubPicker(folders: [Self.folder]))
        await model.chooseAndScan()
        try await Self.settle(model)
        model.toggle(first)

        // Equal size and equal date: the tie-break is the normalized path, so
        // the order is the same every time.
        let bySize = model.sortedRows(by: .size).map(\.id)
        let byAge = model.sortedRows(by: .age).map(\.id)
        XCTAssertEqual(bySize, [second.id, first.id])
        XCTAssertEqual(byAge, [second.id, first.id])
        XCTAssertEqual(model.sortedRows(by: .size).map(\.id), bySize, "sorting is stable")
        XCTAssertEqual(model.selectedIDs, [first.id], "sorting never changes the selection")
    }

    func testSelectedBytesCountOnlyWhatIsSelected() async throws {
        let rows = [Self.row(name: "a.bin", bytes: 900), Self.row(name: "b.bin", bytes: 100)]
        let model = Self.model(
            scanner: ReplayLargeFileScanner(
                events: [.completed(rows: rows, snapshot: Self.snapshot(rows))]),
            picker: StubPicker(folders: [Self.folder]))
        await model.chooseAndScan()
        try await Self.settle(model)

        model.toggle(model.rows.first { $0.url.lastPathComponent == "a.bin" }!)

        XCTAssertEqual(model.selectedBytes, 900)
    }

    // MARK: - Helpers

    private static let folder = URL(fileURLWithPath: "/fixture/chosen")

    private static func model(
        scanner: ReplayLargeFileScanner,
        picker: StubPicker
    ) -> LargeFilesModel {
        LargeFilesModel(
            scanner: scanner,
            picker: picker,
            workspace: SpyWorkspace(),
            applyRoots: { _ in }
        )
    }

    private static func row(name: String, bytes: UInt64) -> LargeFileRow {
        LargeFileRow(
            id: UUID(),
            url: folder.appendingPathComponent(name),
            logicalBytes: bytes,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            kindDescription: "Document",
            canSelect: true
        )
    }

    private static func snapshot(_ rows: [LargeFileRow]) -> ScanSnapshot {
        let candidates = rows.map { row in
            CleanupCandidate(
                id: row.id, ruleID: manualLargeFileRuleID, location: .file(row.url),
                category: .largeFiles, size: row.logicalBytes, allocatedSize: nil,
                risk: .high, method: .trash, consequenceKey: ConsequenceKey.userSelectedFile)
        }
        return ScanSnapshot(
            id: UUID(), policyRevision: 1, candidates: candidates, evidence: [:])
    }

    private static func settle(_ model: LargeFilesModel) async throws {
        for _ in 0..<200 where model.isScanning {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(model.isScanning)
    }
}

/// Replays scripted Large Files events and counts how often it was entered.
private actor ReplayLargeFileScanner: LargeFileScanning {
    private let events: [LargeFileEvent]
    private var runs = 0

    init(events: [LargeFileEvent]) { self.events = events }

    func runCount() -> Int { runs }
    private func note() { runs += 1 }

    nonisolated func scan(
        _ request: LargeFileRequest
    ) -> AsyncThrowingStream<LargeFileEvent, Error> {
        AsyncThrowingStream(LargeFileEvent.self, bufferingPolicy: .unbounded) { continuation in
            Task {
                await note()
                for event in await events { continuation.yield(event) }
                continuation.finish()
            }
        }
    }
}

private struct StubPicker: FolderPicking {
    let folders: [URL]
    func chooseFolders() async -> [URL] { folders }
}

@MainActor
private final class SpyWorkspace: WorkspaceOpening {
    private(set) var revealed: [URL] = []
    func reveal(_ url: URL) { revealed.append(url) }
    func openTrash() {}
}

extension LargeFilesModel {
    /// Test-only seam for restoring previously gathered results, so a cancelled
    /// picker can be shown to leave them alone.
    func adopt(rows: [LargeFileRow], snapshot: ScanSnapshot?) {
        setValue(rows: rows, snapshot: snapshot)
    }
}
