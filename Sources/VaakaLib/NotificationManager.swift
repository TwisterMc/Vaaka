import Foundation
import UserNotifications
import AppKit

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private var center: UNUserNotificationCenter?

    private override init() {
        super.init()
    }

    private func ensureCenter(completion: (() -> Void)? = nil) {
        // If already initialized, run completion and return
        if center != nil {
            Logger.shared.debug("[DEBUG] ensureCenter: center already initialized")
            completion?()
            return
        }

        // Ensure we perform initialization on main thread
        if !Thread.isMainThread {
            Logger.shared.debug("[DEBUG] ensureCenter: not on main thread, dispatching")
            DispatchQueue.main.async { self.ensureCenter(completion: completion) }
            return
        }

        // In unit-test contexts notifications aren't available
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            Logger.shared.debug("[DEBUG] Running in test context, notifications not available")
            completion?()
            return
        }

        // Only initialize after app is fully running
        guard NSApp.isRunning else {
            Logger.shared.debug("[DEBUG] ensureCenter: NSApp not running yet, retrying shortly")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.ensureCenter(completion: completion)
            }
            return
        }

        initializeCenter(completion: completion)
    }

    /// Request user permission for notifications
    func requestPermission(completion: @escaping (Bool) -> Void) {
        Logger.shared.debug("[DEBUG] requestPermission called")
        ensureCenter { [weak self] in
            guard let self = self else { Logger.shared.debug("[DEBUG] requestPermission: self became nil"); completion(false); return }
            // If center couldn't be initialized, treat as unavailable
            guard let center = self.center else { Logger.shared.debug("[DEBUG] requestPermission: notification center unavailable"); completion(false); return }

            // Check existing settings first
            center.getNotificationSettings { settings in
                Logger.shared.debug("[DEBUG] requestPermission: current authorizationStatus = \(settings.authorizationStatus.rawValue)")
                switch settings.authorizationStatus {
                case .notDetermined:
                    print("[DEBUG] requestPermission: requesting authorization")
                    center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                        if let error = error {
                            Logger.shared.log("[ERROR] Notification permission request failed: \(error)")
                        } else {
                            Logger.shared.debug("[DEBUG] Notification permission request result: granted=\(granted)")
                        }
                        DispatchQueue.main.async { completion(granted) }
                    }
                case .denied:
                    print("[DEBUG] requestPermission: authorization previously denied")
                    // Present a user-facing prompt guiding the user to enable notifications
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Notifications are disabled"
                        alert.informativeText = "Notifications for Vaaka are disabled in System Preferences. Open Notification Settings to enable them."
                        alert.addButton(withTitle: "Open Settings")
                        alert.addButton(withTitle: "Cancel")

                        // Prefer presenting as a sheet to avoid blocking the main runloop
                        if let win = NSApp.keyWindow ?? NSApp.mainWindow {
                            alert.beginSheetModal(for: win) { response in
                                if response == .alertFirstButtonReturn {
                                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                completion(false)
                            }
                        } else {
                            // Fallback to runModal if no window is available
                            if alert.runModal() == .alertFirstButtonReturn {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            completion(false)
                        }
                    }
                case .authorized, .provisional, .ephemeral:
                    print("[DEBUG] requestPermission: already authorized")
                    DispatchQueue.main.async { completion(true) }
                @unknown default:
                    print("[DEBUG] requestPermission: unknown authorization status")
                    DispatchQueue.main.async { completion(false) }
                }
            }
        }
    }

    /// Send a notification using UserNotifications framework
    func sendNotification(title: String, body: String, siteId: String, jsNotificationId: String? = nil) {
        // Check if notifications are enabled for this site (opt-in: default to disabled)
        guard isEnabledForSite(siteId) else { return }

        // Ensure center exists - if initialization cannot complete (e.g. no bundle ID), skip silently
        ensureCenter { [weak self] in
            guard let self = self, let center = self.center else { return }

            DispatchQueue.main.async {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                content.threadIdentifier = siteId
                if let jsId = jsNotificationId { content.userInfo["vaaka.notificationId"] = jsId }

                let identifier = "vaaka.\(siteId).\(jsNotificationId ?? UUID().uuidString)"
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
                center.add(request) { error in
                    if let error = error {
                        print("[ERROR] Failed to schedule notification: \(error)")
                    } else {
                        print("[DEBUG] Notification sent for site: \(siteId) id=\(jsNotificationId ?? "<none>")")
                    }
                }
            }
        }
    }

    /// Check if notifications are enabled for a specific site
    func isEnabledForSite(_ siteId: String) -> Bool {
        let defaults = UserDefaults.standard
        let key = "Vaaka.NotificationsEnabled.\(siteId)"
        // Default to false (opt-in) if key doesn't exist
        return defaults.object(forKey: key) as? Bool ?? false
    }

    /// Enable/disable notifications for a site. Requests system permission when enabling;
    /// reverts the stored preference if permission is denied.
    func setEnabled(_ enabled: Bool, forSite siteId: String) {
        let defaults = UserDefaults.standard
        let key = "Vaaka.NotificationsEnabled.\(siteId)"
        defaults.set(enabled, forKey: key)

        guard enabled else { return }
        // Without a bundle ID (swift run / tests) we can't request system permission —
        // persist the preference as-is and bail out.
        guard Bundle.main.bundleIdentifier != nil else { return }

        requestPermission { granted in
            if !granted {
                DispatchQueue.main.async { defaults.set(false, forKey: key) }
            }
        }
    }

    // Delegate: ensure notifications show while app is frontmost
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // Handle a user interacting with a delivered notification (click)
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        let siteId = content.threadIdentifier
        let jsId = content.userInfo["vaaka.notificationId"] as? String

        Logger.shared.debug("[DEBUG] Notification clicked - site=\(siteId) id=\(jsId ?? "<none>")")

        // Attempt to find the tab for this site and invoke the JS onclick handler
        if let tab = SiteTabManager.shared.tabs.first(where: { $0.site.id == siteId }) {
            if let jsNotificationId = jsId {
                let js = "try { if (window.__vaaka_notifications && window.__vaaka_notifications['\(jsNotificationId)'] && typeof window.__vaaka_notifications['\(jsNotificationId)'].onclick === 'function') { window.__vaaka_notifications['\(jsNotificationId)'].onclick(); } } catch(e) { console.error(e); }"
                DispatchQueue.main.async {
                    tab.webView.evaluateJavaScript(js) { _, err in
                        if let err = err { Logger.shared.debug("[DEBUG] Failed to call onclick in webview: \(err)") }
                    }
                }
            }
        }

        completionHandler()
    }
    private func initializeCenter(completion: (() -> Void)?) {
        guard self.center == nil else {
            completion?()
            return
        }
        
        // Wrap in autoreleasepool and check for valid bundle
        autoreleasepool {
            let bid = Bundle.main.bundleIdentifier
            Logger.shared.debug("[DEBUG] initializeCenter: bundle identifier = \(bid ?? "<nil>")")
            guard bid != nil else {
                Logger.shared.debug("[WARN] No bundle identifier, skipping notification center")
                completion?()
                return
            }

            let c = UNUserNotificationCenter.current()
            c.delegate = self
            self.center = c
            Logger.shared.debug("[DEBUG] Notification center initialized")
        }

        completion?()
    }
}
