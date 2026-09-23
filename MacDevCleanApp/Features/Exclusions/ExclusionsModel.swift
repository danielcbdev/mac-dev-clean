import Domain
import Foundation
import Observation

/// The things the user has told MacDevClean to leave alone.
///
/// Every change bumps the policy revision and discards registered snapshots, so
/// a review built before the change cannot be confirmed afterwards. If a save
/// fails, the exclusion is **not** reported as active and the previous scope
/// stands.
@MainActor
@Observable
final class ExclusionsModel {
    private(set) var exclusions: [Exclusion] = []
    private(set) var failureCode: String?

    private let repository: any SettingsRepository
    private let invalidate: () async -> Void
    private let picker: any FolderPicking
    private let fileManager: FileManager

    init(
        repository: any SettingsRepository,
        invalidate: @escaping () async -> Void,
        picker: any FolderPicking,
        fileManager: FileManager = .default
    ) {
        self.repository = repository
        self.invalidate = invalidate
        self.picker = picker
        self.fileManager = fileManager
    }

    func load() async {
        exclusions = (try? await repository.exclusions()) ?? []
    }

    func addPaths() async {
        let chosen = await picker.chooseFolders()
        guard !chosen.isEmpty else { return }
        await apply(exclusions + chosen.map { Exclusion.path($0) })
    }

    func add(_ exclusion: Exclusion) async {
        guard !exclusions.contains(exclusion) else { return }
        await apply(exclusions + [exclusion])
    }

    func remove(_ exclusion: Exclusion) async {
        await apply(exclusions.filter { $0 != exclusion })
    }

    private func apply(_ updated: [Exclusion]) async {
        let previous = exclusions
        do {
            try await repository.saveExclusions(updated)
            exclusions = updated
            failureCode = nil
            await invalidate()
        } catch {
            // Do not pretend it took effect.
            exclusions = previous
            failureCode = PolicyError.unavailable.rawValue
        }
    }

    /// A path exclusion whose target no longer exists stays listed, with a
    /// status saying so. Removing it silently would lose the user's decision.
    func resolves(_ exclusion: Exclusion) -> Bool {
        guard case .path(let url) = exclusion else { return true }
        return fileManager.fileExists(atPath: url.path)
    }

    func title(for exclusion: Exclusion) -> String {
        switch exclusion {
        case .path(let url): return url.lastPathComponent
        case .category(let category): return CategoryNaming.title(category)
        case .rule(let rule): return rule
        }
    }

    func detail(for exclusion: Exclusion) -> String {
        switch exclusion {
        case .path(let url):
            return url.deletingLastPathComponent().lastPathComponent
        case .category:
            return String(localized: "Every item in this category")
        case .rule:
            return String(localized: "Every item this rule finds")
        }
    }

    func identifier(for exclusion: Exclusion) -> String {
        switch exclusion {
        case .path(let url): return "exclusion.path.\(url.lastPathComponent)"
        case .category(let category): return "exclusion.category.\(category.rawValue)"
        case .rule(let rule): return "exclusion.rule.\(rule)"
        }
    }
}
