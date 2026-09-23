import AppKit
import Foundation

/// Reveals an item in Finder and opens the Trash.
///
/// `openTrash` opens the Trash in Finder and does nothing else. This app has no
/// code path that empties it: reclaiming space stays a deliberate act the user
/// performs themselves.
@MainActor
struct NativeWorkspaceOpener: WorkspaceOpening {
    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openTrash() {
        guard
            let trash = try? FileManager.default.url(
                for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        else { return }
        NSWorkspace.shared.open(trash)
    }
}
