import Foundation

func upload(_ report: Data, to endpoint: URL) {
    URLSession.shared.dataTask(with: endpoint).resume()
}
