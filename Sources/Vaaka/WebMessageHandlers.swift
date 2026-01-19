import Foundation
import WebKit


/// Weak wrapper for notification message handling
final class NotificationMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var siteTab: SiteTab?

    init(siteTab: SiteTab) {
        self.siteTab = siteTab
    }

    func userContentController(_ userContentController: WKUserContentController,
                              didReceive message: WKScriptMessage) {
        guard let tab = siteTab else { return }

        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        if type == "permissionRequest" {
            NotificationManager.shared.requestPermission { granted in
                let status = granted ? "granted" : "denied"
                let js = "window.nativeNotificationPermission = '\(status)'; if (window.notificationPermissionCallback) { window.notificationPermissionCallback('\(status)'); window.notificationPermissionCallback = null; } if (window.__vaaka_permissionResolver) { window.__vaaka_permissionResolver('\(status)'); window.__vaaka_permissionResolver = null; }"
                DispatchQueue.main.async {
                    tab.webView.evaluateJavaScript(js, completionHandler: nil)
                }
            }
            return
        }

        if type == "show" {
            let title = body["title"] as? String ?? ""
            let notificationBody = body["body"] as? String ?? ""
            let jsId = body["id"] as? String
            // Deduping is handled on native side; increment unread if tab not active
            let isActive = (SiteTabManager.shared.activeTab()?.site.id == tab.site.id)
            DispatchQueue.main.async {
                if !isActive { UnreadManager.shared.increment(for: tab.site.id) }
                NotificationManager.shared.sendNotification(title: title, body: notificationBody, siteId: tab.site.id, jsNotificationId: jsId)
            }
            return
        }
    }
}

/// Weak wrapper for badge count message handling
final class BadgeUpdateHandler: NSObject, WKScriptMessageHandler {
    private weak var siteTab: SiteTab?
    private var lastCount: Int = -1
    private var lastUpdateTime: Date = .distantPast

    init(siteTab: SiteTab) {
        self.siteTab = siteTab
    }

    func userContentController(_ userContentController: WKUserContentController,
                              didReceive message: WKScriptMessage) {
        guard let tab = siteTab else { return }

        guard let body = message.body as? [String: Any],
              let count = body["count"] as? Int else { return }

        // Rate limit: only update if count changed and at least 500ms since last update
        let now = Date()
        guard count != lastCount || now.timeIntervalSince(lastUpdateTime) > 0.5 else {
            return
        }

        lastCount = count
        lastUpdateTime = now

        DispatchQueue.main.async {
            UnreadManager.shared.set(count, for: tab.site.id)
        }
    }
}
/// Forward JS console messages to the system logger (helpful for JS debugging)
final class ConsoleMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var siteTab: SiteTab?

    // Simple in-memory throttling to avoid log floods: map of message key -> last logged time
    private static var recentMessages: [String: Date] = [:]
    private static let throttleInterval: TimeInterval = 60 // seconds

    init(siteTab: SiteTab) {
        self.siteTab = siteTab
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let tab = siteTab else { return }
        guard let body = message.body as? [String: Any], let level = body["level"] as? String, let msg = body["message"] as? String else { return }

        // Quick filters to drop unhelpful noise
        let trimmed = msg.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        if trimmed.contains("[Vaaka] Console forwarder installed") { return }
        // Many pages report bare Event objects which stringify to "[object Event]" — drop these if they provide no stack
        if let _ = trimmed.range(of: "^\\[object .*\\]$", options: .regularExpression), (body["stack"] as? String ?? "").isEmpty {
            return
        }

        // Throttle repeated identical messages to once per `throttleInterval`
        let siteName = tab.site.name
        var sanitized = trimmed
        if sanitized.count > 500 { sanitized = String(sanitized.prefix(500)) + "...[truncated]" }
        let key = "\(siteName)|\(level)|\(sanitized)"
        let now = Date()
        if let last = ConsoleMessageHandler.recentMessages[key], now.timeIntervalSince(last) < ConsoleMessageHandler.throttleInterval {
            return
        }
        ConsoleMessageHandler.recentMessages[key] = now

        // Only log warnings/errors by default. For "log" level we keep only notable messages.
        let shouldLog: Bool
        switch level.lowercased() {
        case "error", "warn", "warning":
            shouldLog = true
        case "log", "info", "debug":
            shouldLog = sanitized.contains("Vaaka") || sanitized.contains("UnhandledRejection") || sanitized.contains("Exception")
        default:
            shouldLog = false
        }
        if !shouldLog { return }

        // Include stack if present
        let stack = (body["stack"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var line = "[JS] [\(siteName)] [\(level)] \(sanitized)"
        if !stack.isEmpty {
            line += "\nStack:\n\(stack)"
        }
        Logger.shared.debug(line)
    }
} 

// Handle contextmenu events reported from the page (e.g., right-click on an <img>) so we can present
// a native Save dialog and handle the download natively (works around WebKit default menu limitations).
final class ContextMenuHandler: NSObject, WKScriptMessageHandler {
    private weak var siteTab: SiteTab?

    init(siteTab: SiteTab) {
        self.siteTab = siteTab
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let tab = siteTab else { return }
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }

        if type == "image", let src = body["src"] as? String {
            // Post notification so BrowserWindowController can present the menu at the proper location
            NotificationCenter.default.post(name: Notification.Name("Vaaka.ContextMenuImage"), object: nil, userInfo: ["siteId": tab.site.id, "src": src])
        }
    }
}
