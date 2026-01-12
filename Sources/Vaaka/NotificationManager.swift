import Foundation
import AppKit

class NotificationManager: NSObject {
    static let shared = NotificationManager()

    private override init() {
        super.init()
    }

    /// Request user permission for notifications (AppleScript doesn't require explicit permission)
    func requestPermission(completion: @escaping (Bool) -> Void) {
        // AppleScript notifications work without explicit permission request
        DispatchQueue.main.async { completion(true) }
    }

    /// Send a notification to the system using AppleScript
    func sendNotification(title: String, body: String, siteId: String) {
        // Check if notifications are globally enabled
        let globalEnabled = UserDefaults.standard.object(forKey: "Vaaka.NotificationsEnabledGlobal") == nil || UserDefaults.standard.bool(forKey: "Vaaka.NotificationsEnabledGlobal")
        guard globalEnabled else { return }
        
        // Escape quotes in title and body
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedBody = body.replacingOccurrences(of: "\"", with: "\\\"")
        
        // Use AppleScript to display notification - works on all macOS versions without special permissions
        let script = """
        display notification "\(escapedBody)" with title "\(escapedTitle)"
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                print("[ERROR] Failed to send notification: \(error)")
            } else {
                print("[DEBUG] Notification sent for site: \(siteId)")
            }
        }
    }

    /// Check if notifications are enabled for a specific site
    func isEnabledForSite(_ siteId: String) -> Bool {
        let defaults = UserDefaults.standard
        let key = "Vaaka.NotificationsEnabled.\(siteId)"
        // Default to true if not explicitly disabled
        return defaults.object(forKey: key) == nil || defaults.bool(forKey: key)
    }

    /// Enable/disable notifications for a site
    func setEnabled(_ enabled: Bool, forSite siteId: String) {
        let defaults = UserDefaults.standard
        let key = "Vaaka.NotificationsEnabled.\(siteId)"
        defaults.set(enabled, forKey: key)
    }
}
