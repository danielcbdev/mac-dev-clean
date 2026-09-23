import Foundation

func destroy(_ url: URL) throws {
    try FileManager.default.removeItem(at: url)
}
