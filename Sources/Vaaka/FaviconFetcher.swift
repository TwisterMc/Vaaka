import Foundation
import AppKit

class FaviconFetcher {
    static let shared = FaviconFetcher()

    private let session = URLSession(configuration: .ephemeral)

    func fetchFavicon(for url: URL, completion: @escaping (NSImage?) -> Void) {
        guard let host = url.host else { completion(nil); return }
        let candidates = ["https://\(host)/favicon.ico", "https://www.\(host)/favicon.ico"]
        fetchFromCandidates(candidates, completion: completion)
    }

    private func fetchFromCandidates(_ urls: [String], completion: @escaping (NSImage?) -> Void) {
        guard let first = urls.first else { completion(nil); return }
        guard let u = URL(string: first) else { fetchFromCandidates(Array(urls.dropFirst()), completion: completion); return }
        let task = session.dataTask(with: u) { data, resp, err in
            if let d = data, let img = NSImage(data: d) {
                completion(img)
            } else {
                self.fetchFromCandidates(Array(urls.dropFirst()), completion: completion)
            }
        }
        task.resume()
    }
}
