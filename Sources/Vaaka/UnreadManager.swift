import Foundation
import AppKit

extension Notification.Name {
    static let UnreadChanged = Notification.Name("Vaaka.UnreadChanged")
}

/// Tracks unread notification counts per site since last activation.
final class UnreadManager {
    static let shared = UnreadManager()

    private var counts: [String: Int] = [:] // siteId -> count
    private let queue = DispatchQueue(label: "vaaka.unread", qos: .userInitiated)

    private init() {}

    func count(for siteId: String) -> Int {
        return queue.sync { counts[siteId] ?? 0 }
    }

    func increment(for siteId: String) {
        queue.sync {
            let current = counts[siteId] ?? 0
            counts[siteId] = current + 1
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .UnreadChanged, object: siteId)
        }
    }

    func clear(for siteId: String) {
        queue.sync { counts[siteId] = 0 }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .UnreadChanged, object: siteId)
        }
    }
}
