import Domain
import Foundation
import Observation

/// First-run scope selection.
///
/// Nothing is scanned until the user accepts a set of roots. Proposed roots are
/// only the conventional locations that actually exist, and a proposal is never
/// an acceptance: the roots are saved when the user confirms, and not before.
@MainActor
@Observable
final class RootSelectionModel {
    /// Conventional project locations, home-relative. Offered only if present.
    static let conventionalNames = ["Projects", "Developer", "Code", "Projetos"]

    private(set) var proposals: [URL] = []
    private(set) var isSaving = false
    var chosen: Set<URL> = []

    private let settings: any SettingsRepository
    private let picker: any FolderPicking
    private let home: URL
    private let fileManager: FileManager

    init(
        settings: any SettingsRepository,
        picker: any FolderPicking,
        home: URL = URL(fileURLWithPath: NSHomeDirectory()),
        fileManager: FileManager = .default
    ) {
        self.settings = settings
        self.picker = picker
        self.home = home
        self.fileManager = fileManager
    }

    func loadProposals() {
        proposals = Self.conventionalNames
            .map { home.appendingPathComponent($0) }
            .filter { url in
                var isDirectory: ObjCBool = false
                let exists = fileManager.fileExists(
                    atPath: url.path, isDirectory: &isDirectory)
                return exists && isDirectory.boolValue
            }
    }

    func toggle(_ url: URL) {
        if chosen.contains(url) { chosen.remove(url) } else { chosen.insert(url) }
    }

    /// Opens the native folder picker. Cancelling returns nothing and changes
    /// nothing.
    func addFolders() async {
        let picked = await picker.chooseFolders()
        for url in picked where !proposals.contains(url) {
            proposals.append(url)
        }
        chosen.formUnion(picked)
    }

    var canConfirm: Bool { !chosen.isEmpty && !isSaving }

    /// Saves the accepted roots. This is the only place roots are written.
    func confirm() async -> Bool {
        guard canConfirm else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try await settings.saveRoots(
                chosen.sorted { $0.path < $1.path }.map { ScanRoot(url: $0) })
            return true
        } catch {
            return false
        }
    }
}

/// Chooses folders. Cancellation returns an empty array.
@MainActor
protocol FolderPicking {
    func chooseFolders() async -> [URL]
}

/// Reveals items in Finder and opens the Trash.
@MainActor
protocol WorkspaceOpening {
    func reveal(_ url: URL)
    /// Opens the system Trash. This app never empties it.
    func openTrash()
}
