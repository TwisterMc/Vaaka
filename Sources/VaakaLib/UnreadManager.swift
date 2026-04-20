import Foundation
import AppKit

extension Notification.Name {
    static let UnreadChanged = Notification.Name("Vaaka.UnreadChanged")
}

/// Tracks unread counts per site from two independent sources:
/// - badge counts from the page title/DOM (via BadgeDetector)
/// - notification counts from intercepted JS Notification API calls
///
/// The two sources no longer fight: `setBadgeCount` and `incrementNotification`
/// update separate buckets. `count(for:)` returns the badge count when the page
/// reports one (> 0), otherwise the accumulated notification count. Clearing
/// (e.g. "Mark as Read") resets both.
final class UnreadManager {
    static let shared = UnreadManager()

    private var badgeCounts: [String: Int] = [:]   // page title/DOM
    private var notifCounts: [String: Int] = [:]   // intercepted JS notifications
    private let queue = DispatchQueue(label: "vaaka.unread", qos: .userInitiated)

    private init() {}

    func count(for siteId: String) -> Int {
        queue.sync {
            let badge = badgeCounts[siteId] ?? 0
            let notif = notifCounts[siteId] ?? 0
            return badge > 0 ? badge : notif
        }
    }

    /// Called by BadgeDetector when the page title/DOM reports a count.
    func setBadgeCount(_ count: Int, for siteId: String) {
        queue.sync { badgeCounts[siteId] = max(0, count) }
        postChanged(for: siteId)
    }

    /// Called when an intercepted JS notification arrives for a site.
    func incrementNotification(for siteId: String) {
        queue.sync { notifCounts[siteId] = (notifCounts[siteId] ?? 0) + 1 }
        postChanged(for: siteId)
    }

    /// Clear all counts for a site (user marked as read, or explicit clear).
    func clear(for siteId: String) {
        queue.sync { badgeCounts[siteId] = 0; notifCounts[siteId] = 0 }
        postChanged(for: siteId)
    }

    private func postChanged(for siteId: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .UnreadChanged, object: siteId)
        }
    }
}
