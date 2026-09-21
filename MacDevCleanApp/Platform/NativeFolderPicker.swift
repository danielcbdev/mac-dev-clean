import AppKit
import Foundation

/// The real folder chooser.
///
/// Directories only, multiple selection allowed, and cancelling returns nothing
/// — which the caller treats as "change nothing", not as "clear the roots".
@MainActor
struct NativeFolderPicker: FolderPicking {
    func chooseFolders() async -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        panel.prompt = String(localized: "Use these folders")
        panel.message = String(
            localized:
                """
                Choose the folders that contain your projects. MacDevClean only looks inside \
                folders you add here.
                """
        )

        guard panel.runModal() == .OK else { return [] }
        return panel.urls.map { URL(fileURLWithPath: $0.path, isDirectory: false) }
    }
}
