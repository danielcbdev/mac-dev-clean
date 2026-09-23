import Domain
import Foundation
import Observation

/// Drives Large Files analysis.
///
/// Nothing is scanned until the user picks folders, nothing is selected by a
/// scan or by re-sorting, and every result is high risk — a big file is not a
/// disposable file.
@MainActor
@Observable
final class LargeFilesModel {
    enum Sort: String, CaseIterable, Identifiable {
        case size, age, name, location
        var id: String { rawValue }
    }

    private(set) var rows: [LargeFileRow] = []
    private(set) var snapshot: ScanSnapshot?
    private(set) var isScanning = false
    private(set) var issueCodes: [String] = []
    private(set) var chosenFolders: [URL] = []
    private(set) var visited = 0

    var selectedIDs: Set<UUID> = []
    var sort: Sort = .size

    /// Changing the threshold invalidates the results, because they were
    /// gathered under a different question.
    var minimumBytes: UInt64 = LargeFileThreshold.default {
        didSet {
            guard minimumBytes != oldValue else { return }
            rows = []
            snapshot = nil
            selectedIDs = []
        }
    }

    private let scanner: any LargeFileScanning
    private let picker: any FolderPicking
    private let workspace: any WorkspaceOpening
    private let applyRoots: ([URL]) async -> Void
    private let work = CancellableWork()
    private var activeGeneration: UUID?

    init(
        scanner: any LargeFileScanning,
        picker: any FolderPicking,
        workspace: any WorkspaceOpening,
        applyRoots: @escaping ([URL]) async -> Void
    ) {
        self.scanner = scanner
        self.picker = picker
        self.workspace = workspace
        self.applyRoots = applyRoots
    }

    deinit {
        work.cancel()
    }

    // MARK: - Choosing and scanning

    /// Opens the folder picker and, if the user chose something, scans it.
    ///
    /// Cancelling the picker returns nothing and leaves previous results alone.
    func chooseAndScan() async {
        let folders = await picker.chooseFolders()
        guard !folders.isEmpty else { return }
        chosenFolders = folders
        // The chosen folders become the Large Files scope, which also bumps the
        // policy revision and invalidates anything selected under the old one.
        await applyRoots(folders)
        start()
    }

    func start() {
        guard !isScanning, !chosenFolders.isEmpty else { return }
        work.cancel()
        rows = []
        snapshot = nil
        selectedIDs = []
        issueCodes = []
        visited = 0
        isScanning = true

        let generation = UUID()
        activeGeneration = generation
        let request = LargeFileRequest(
            roots: chosenFolders.map { ScanRoot(url: $0) }, minimumBytes: minimumBytes)

        work.replace(
            with: Task { [weak self, scanner] in
                do {
                    for try await event in scanner.scan(request) {
                        guard !Task.isCancelled,
                            await self?.activeGeneration == generation
                        else { break }
                        await self?.receive(event, generation: generation)
                    }
                    await self?.settle(generation)
                } catch {
                    await self?.settle(generation)
                }
            })
    }

    func cancel() {
        work.cancel()
        activeGeneration = nil
        isScanning = false
    }

    private func receive(_ event: LargeFileEvent, generation: UUID) {
        guard activeGeneration == generation else { return }
        switch event {
        case .progress(let count):
            visited = count
        case .issue(let code):
            if !issueCodes.contains(code) { issueCodes.append(code) }
        case .completed(let result, let value):
            rows = result
            snapshot = value
        }
    }

    private func settle(_ generation: UUID) {
        guard activeGeneration == generation else { return }
        isScanning = false
        activeGeneration = nil
    }

    // MARK: - Presentation

    /// Sorting never changes the selection, and every order has a stable
    /// tie-break so the table does not shuffle between renders.
    func sortedRows(by order: Sort) -> [LargeFileRow] {
        rows.sorted { left, right in
            switch order {
            case .size:
                if left.logicalBytes != right.logicalBytes {
                    return left.logicalBytes > right.logicalBytes
                }
            case .age:
                if left.modifiedAt != right.modifiedAt {
                    return left.modifiedAt < right.modifiedAt
                }
            case .name:
                let a = left.url.lastPathComponent.lowercased()
                let b = right.url.lastPathComponent.lowercased()
                if a != b { return a < b }
            case .location:
                let a = left.url.deletingLastPathComponent().path.lowercased()
                let b = right.url.deletingLastPathComponent().path.lowercased()
                if a != b { return a < b }
            }
            return left.url.standardizedFileURL.path < right.url.standardizedFileURL.path
        }
    }

    var visibleRows: [LargeFileRow] { sortedRows(by: sort) }

    func isSelected(_ id: UUID) -> Bool { selectedIDs.contains(id) }

    func toggle(_ row: LargeFileRow) {
        guard row.canSelect else { return }
        if selectedIDs.contains(row.id) {
            selectedIDs.remove(row.id)
        } else {
            selectedIDs.insert(row.id)
        }
    }

    /// There is no "select all" here on purpose. Large files are chosen one at
    /// a time, because nothing about them says they are disposable.
    func clearSelection() { selectedIDs = [] }

    func reveal(id: UUID) {
        guard let row = rows.first(where: { $0.id == id }) else { return }
        workspace.reveal(row.url)
    }

    var selectedBytes: UInt64 {
        rows.filter { selectedIDs.contains($0.id) }
            .map(\.logicalBytes)
            .reduce(UInt64(0)) { total, size in
                total.addingReportingOverflow(size).overflow ? total : total + size
            }
    }

    var informationalRowCount: Int { rows.filter { !$0.canSelect }.count }

    /// Restores a previously gathered result set. Used to model "the user
    /// already has results and then cancels the folder picker".
    func setValue(rows newRows: [LargeFileRow], snapshot newSnapshot: ScanSnapshot?) {
        rows = newRows
        snapshot = newSnapshot
    }
}
