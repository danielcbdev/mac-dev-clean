import Foundation

// Deliberate near misses: the checker must not flag a word that merely
// contains one of the forbidden names, nor the Trash API this product uses.
func moveToTrash(_ url: URL) throws -> URL? {
    var resulting: NSURL?
    try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
    return resulting as URL?
}

func confirm(_ platform: String) -> Bool {
    !platform.isEmpty
}
