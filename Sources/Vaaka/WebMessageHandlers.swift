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
/// Forward JS console messages to the system logger (helpful when Web Inspector is unreliable)
final class ConsoleMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var siteTab: SiteTab?

    init(siteTab: SiteTab) {
        self.siteTab = siteTab
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let tab = siteTab else { return }
        guard let body = message.body as? [String: Any], let level = body["level"] as? String, let msg = body["message"] as? String else { return }

        let siteName = tab.site.name
        let line = "[JS] [\(siteName)] [\(level)] \(msg)"
        Logger.shared.debug(line)
    }
}