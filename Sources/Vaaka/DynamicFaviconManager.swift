import Foundation
import AppKit

class DynamicFaviconManager {
    static let shared = DynamicFaviconManager()

    private init() {}

    private let dynamicFaviconSites = [
        "calendar.google.com"
    ]

    func shouldRefreshFavicon(for url: URL) -> Bool {
        guard let host = url.host else { return false }
        return dynamicFaviconSites.contains { host.contains($0) }
    }

    func refreshInterval(for url: URL) -> TimeInterval? {
        guard let host = url.host else { return nil }

        if host.contains("calendar.google.com") {
            return timeUntilNextMidnight()
        }

        return nil
    }

    private func timeUntilNextMidnight() -> TimeInterval {
        let calendar = Calendar.current
        let now = Date()

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
              let midnight = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: tomorrow) else {
            return 86400
        }

        return max(midnight.timeIntervalSince(now), 60)
    }
}
