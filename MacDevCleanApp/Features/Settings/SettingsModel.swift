import Domain
import Foundation
import Observation

/// Preferences and project roots.
///
/// Semantic values are stored, never translated strings: the language setting is
/// `portugueseBrazil`, so switching the interface language cannot corrupt it.
@MainActor
@Observable
final class SettingsModel {
    private(set) var roots: [ScanRoot] = []
    private(set) var failureCode: String?
    var preferences = AppPreferences()

    private let repository: any SettingsRepository
    private let invalidate: () async -> Void
    private let picker: any FolderPicking

    init(
        repository: any SettingsRepository,
        invalidate: @escaping () async -> Void,
        picker: any FolderPicking
    ) {
        self.repository = repository
        self.invalidate = invalidate
        self.picker = picker
    }

    func load() async {
        preferences = (try? await repository.preferences()) ?? AppPreferences()
        roots = (try? await repository.roots()) ?? []
    }

    func savePreferences() async {
        do {
            try await repository.savePreferences(preferences)
            failureCode = nil
        } catch {
            failureCode = PolicyError.unavailable.rawValue
        }
    }

    func addRoots() async {
        let chosen = await picker.chooseFolders()
        guard !chosen.isEmpty else { return }
        let existing = Set(roots.map { $0.url.standardizedFileURL.path })
        let added =
            chosen
            .filter { !existing.contains($0.standardizedFileURL.path) }
            .map { ScanRoot(url: $0) }
        await apply(roots + added)
    }

    func remove(_ root: ScanRoot) async {
        await apply(roots.filter { $0 != root })
    }

    private func apply(_ updated: [ScanRoot]) async {
        let previous = roots
        do {
            try await repository.saveRoots(updated)
            roots = updated
            failureCode = nil
            // Changing scope invalidates every registered snapshot.
            await invalidate()
        } catch {
            roots = previous
            failureCode = PolicyError.unavailable.rawValue
        }
    }

    /// Scanning on launch is offered only once there is something to scan, and
    /// is off until the user turns it on.
    var canEnableScanOnLaunch: Bool { !roots.isEmpty }
}
