import Foundation
import UserNotifications

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private var center: UNUserNotificationCenter?

    private override init() {
        super.init()
    }

    private func ensureCenter() {
        guard center == nil else { return }
        guard Thread.isMainThread else {
            DispatchQueue.main.sync { self.ensureCenter() }
            return
        }
        
        // In a package/test context, notification center might not be available
        // This is fine - notifications just won't work in that context
        if Bundle.main.bundleIdentifier == nil {
            print("[DEBUG] Running in package context, notifications not available")
            return
        }
        
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        self.center = c
    }

    /// Request user permission for notifications
    func requestPermission(completion: @escaping (Bool) -> Void) {
        ensureCenter()
        guard let center = center else {
            completion(false)
            return
        }
        
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("[ERROR] Notification permission request failed: \(error)")
            }
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// Send a notification using UserNotifications framework
    func sendNotification(title: String, body: String, siteId: String) {
        // Check if notifications are globally enabled
        let globalEnabled = UserDefaults.standard.object(forKey: "Vaaka.NotificationsEnabledGlobal") == nil || UserDefaults.standard.bool(forKey: "Vaaka.NotificationsEnabledGlobal")
        guard globalEnabled else { return }
        
        // Check if notifications are enabled for this site
        guard isEnabledForSite(siteId) else { return }

        ensureCenter()
        guard let center = center else { return }

        DispatchQueue.main.async {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.threadIdentifier = siteId

            let request = UNNotificationRequest(identifier: "vaaka.\(siteId).\(UUID().uuidString)", content: content, trigger: nil)
            center.add(request) { error in
                if let error = error {
                    print("[ERROR] Failed to schedule notification: \(error)")
                } else {
                    print("[DEBUG] Notification sent for site: \(siteId)")
                }
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

    // Delegate: ensure notifications show while app is frontmost
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
