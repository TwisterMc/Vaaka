import Foundation
import UserNotifications

class NotificationManager {
    static let shared = NotificationManager()

    private override init() {}

    /// Request user permission for notifications
    func requestPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[ERROR] Notification permission request failed: \(error)")
            }
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    /// Send a notification to the system
    func sendNotification(title: String, body: String, siteId: String) {
        // Check if notifications are globally enabled
        let globalEnabled = UserDefaults.standard.object(forKey: "Vaaka.NotificationsEnabledGlobal") == nil || UserDefaults.standard.bool(forKey: "Vaaka.NotificationsEnabledGlobal")
        guard globalEnabled else { return }
        
        // Check if user has granted permission
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else {
                print("[DEBUG] Notifications not authorized by user")
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.badge = NSNumber(value: UIApplication.shared.applicationIconBadgeNumber + 1)
            // Add custom data so we can identify which site this came from
            content.userInfo = ["siteId": siteId]

            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("[ERROR] Failed to send notification: \(error)")
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
}
