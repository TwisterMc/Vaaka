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
            completion?()
            return
        }

        // Ensure we perform initialization on main thread
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.ensureCenter(completion: completion) }
            return
        }

        // In unit-test contexts notifications aren't available
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            print("[DEBUG] Running in test context, notifications not available")
            completion?()
            return
        }

        // Only initialize after app is fully running
        guard NSApp.isRunning else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.ensureCenter(completion: completion)
            }
            return
        }

        initializeCenter(completion: completion)
    }

    /// Request user permission for notifications
    func requestPermission(completion: @escaping (Bool) -> Void) {
        ensureCenter { [weak self] in
            guard let self = self else { completion(false); return }
            // If center couldn't be initialized, treat as unavailable
            guard let center = self.center else { completion(false); return }

            // Check existing settings first
            center.getNotificationSettings { settings in
                switch settings.authorizationStatus {
                case .notDetermined:
                    center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                        if let error = error {
                            print("[ERROR] Notification permission request failed: \(error)")
                        }
                        DispatchQueue.main.async { completion(granted) }
                    }
                case .denied:
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
                    DispatchQueue.main.async { completion(true) }
                @unknown default:
                    DispatchQueue.main.async { completion(false) }
                }
            }
        }
    }

    /// Send a notification using UserNotifications framework
    func sendNotification(title: String, body: String, siteId: String) {
        // Check if notifications are globally enabled (opt-in: default to disabled if key doesn't exist)
        let globalEnabled = UserDefaults.standard.object(forKey: "Vaaka.NotificationsEnabledGlobal") as? Bool ?? false
        guard globalEnabled else { return }

        // Check if notifications are enabled for this site (opt-in: default to disabled)
        guard isEnabledForSite(siteId) else { return }

        // Ensure center exists - if initialization cannot complete, skip
        ensureCenter { [weak self] in
            guard let self = self else { return }
            guard let center = self.center else { return }

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
    }

    /// Check if notifications are enabled for a specific site
    func isEnabledForSite(_ siteId: String) -> Bool {
        let defaults = UserDefaults.standard
        let key = "Vaaka.NotificationsEnabled.\(siteId)"
        // Default to false (opt-in) if key doesn't exist
        return defaults.object(forKey: key) as? Bool ?? false
    }

    /// Enable/disable notifications for a site
    func setEnabled(_ enabled: Bool, forSite siteId: String) {
        let defaults = UserDefaults.standard
        let key = "Vaaka.NotificationsEnabled.\(siteId)"
        defaults.set(enabled, forKey: key)

        // If enabling, ensure we have system permission; if not, revert the setting
        if enabled {
            requestPermission { granted in
                if !granted {
                    DispatchQueue.main.async {
                        defaults.set(false, forKey: key)
                    }
                }
            }
        }
    }

    /// Enable/disable notifications globally (opt-in). Calls requestPermission when enabling and calls completion with result.
    func setGlobalEnabled(_ enabled: Bool, completion: ((Bool) -> Void)? = nil) {
        let defaults = UserDefaults.standard
        let key = "Vaaka.NotificationsEnabledGlobal"

        if enabled {
            // Request permission; persist only if granted
            requestPermission { granted in
                DispatchQueue.main.async {
                    if granted {
                        defaults.set(true, forKey: key)
                    } else {
                        defaults.set(false, forKey: key)
                    }
                    completion?(granted)
                }
            }
        } else {
            // Disabling is immediate
            defaults.set(false, forKey: key)
            completion?(true)
        }
    }

    // Delegate: ensure notifications show while app is frontmost
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    private func initializeCenter(completion: (() -> Void)?) {
        guard self.center == nil else {
            completion?()
            return
        }
        
        // Wrap in autoreleasepool and check for valid bundle
        autoreleasepool {
            guard Bundle.main.bundleIdentifier != nil else {
                print("[WARN] No bundle identifier, skipping notification center")
                completion?()
                return
            }
            
            let c = UNUserNotificationCenter.current()
            c.delegate = self
            self.center = c
            print("[DEBUG] Notification center initialized")
        }
        
        completion?()
    }
}
