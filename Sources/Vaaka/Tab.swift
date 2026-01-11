import Foundation
import WebKit
import AppKit

/// Represents a loaded Site tab: one `WKWebView` per `Site`.
final class SiteTab: NSObject {
    let site: Site
    let webView: WKWebView
    // Keep a strong reference to the navigation delegate used to enforce whitelist
    var navigationDelegateStored: WKNavigationDelegate?
    var uiDelegateStored: WKUIDelegate?

    private var hasLoadedStartURL: Bool = false
    private var loadingWatchdogWorkItem: DispatchWorkItem?
    private var navigationStuckWorkItem: DispatchWorkItem?
    private var navigationInProgress: Bool = false
    // When exercising the visibility experiment via `--test-unhide-before-load` we temporarily unhide
    // the WebView during the initial load; this flag lets us re-hide it after navigation actually starts.
    private var temporarilyUnhiddenForLoad: Bool = false

    init(site: Site, configuration: WKWebViewConfiguration = WKWebViewConfiguration()) {
        self.site = site
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        // Ensure every WebView presents itself with a Safari-like User-Agent so servers and scripts
        // that inspect navigator.userAgent or perform UA-based content negotiation treat us like Safari.
        self.webView.customUserAgent = UserAgent.safari

            // Observe start events for this site so we can cancel watchdogs
        NotificationCenter.default.addObserver(forName: Notification.Name("Vaaka.SiteTabDidStartLoading"), object: nil, queue: .main) { [weak self] note in
            guard let self = self, let id = note.object as? String, id == self.site.id else { return }
            // Cancel pre-start watchdog if navigation actually started
            self.loadingWatchdogWorkItem?.cancel()
            self.loadingWatchdogWorkItem = nil

            // Mark that navigation is in progress and start a stuck-navigation watchdog: if the navigation
            // has started but does not finish in `stuckTimeout` seconds, attempt in-app recovery then fallback.
            self.navigationInProgress = true

            // If we temporarily unhid the WebView for the initial load, re-hide it now that navigation started.
            if self.temporarilyUnhiddenForLoad {
                self.temporarilyUnhiddenForLoad = false
                self.webView.isHidden = true
            }

            self.navigationStuckWorkItem?.cancel()
            let stuckTimeout: TimeInterval = ProcessInfo.processInfo.arguments.contains("--test-short-wd") ? 5.0 : 20.0
            let wi = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                if self.navigationInProgress {
                    DispatchQueue.main.async {
                        // Try to recover by activating the tab (makes WebView visible) and reloading once.
                        if let idx = SiteTabManager.shared.tabs.firstIndex(where: { $0.site.id == self.site.id }) {
                            SiteTabManager.shared.setActiveIndex(idx)
                            self.webView.reload()
                            // Telemetry: note we've fired the stuck watchdog and attempted in-app recovery
                            Telemetry.shared.recordStuckWatchdog(siteId: self.site.id, phase: "recovery_attempt")
                            // Schedule a final fallback: open externally if reload doesn't finish within another `stuckTimeout` seconds.
                            self.navigationStuckWorkItem?.cancel()
                            let finalWi = DispatchWorkItem { [weak self] in
                                guard let self = self else { return }
                                if self.navigationInProgress {
                                    // Telemetry: final fallback
                                    Telemetry.shared.recordStuckWatchdog(siteId: self.site.id, phase: "final_fallback")
                                    NSWorkspace.shared.open(self.site.url)
                                    NotificationCenter.default.post(name: Notification.Name("Vaaka.SiteTabDidFinishLoading"), object: self.site.id)
                                    self.navigationInProgress = false
                                }
                            }
                            self.navigationStuckWorkItem = finalWi
                            DispatchQueue.main.asyncAfter(deadline: .now() + stuckTimeout, execute: finalWi)
                        } else {
                            // No tab index found — open externally as a fallback
                            print("[WARN] SiteTab.navigation stuck watchdog: no tab found for site.id=\(self.site.id), opening externally")
                            NSWorkspace.shared.open(self.site.url)
                            NotificationCenter.default.post(name: Notification.Name("Vaaka.SiteTabDidFinishLoading"), object: self.site.id)
                            self.navigationInProgress = false
                        }
                    }
                }
            }
            self.navigationStuckWorkItem = wi
            DispatchQueue.main.asyncAfter(deadline: .now() + stuckTimeout, execute: wi)
        }

        // Observe finish events to clear any stuck-navigation watchdogs
        NotificationCenter.default.addObserver(forName: Notification.Name("Vaaka.SiteTabDidFinishLoading"), object: nil, queue: .main) { [weak self] note in
            guard let self = self, let id = note.object as? String, id == self.site.id else { return }
            // Cancel any in-flight watchdogs and clear navigation state
            self.loadingWatchdogWorkItem?.cancel()
            self.loadingWatchdogWorkItem = nil
            self.navigationStuckWorkItem?.cancel()
            self.navigationStuckWorkItem = nil
            self.navigationInProgress = false
        }

        // Do not load the start URL immediately — wait until the WebView is attached to the window/content view.
        // This avoids spurious `open` attempts while the WebView is not yet part of the responder/window chain.

    }

    deinit {
        loadingWatchdogWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    /// Load the site's start URL if it hasn't been loaded already. Safe to call multiple times.
    func loadStartURLIfNeeded() {
        guard !hasLoadedStartURL else { return }
        hasLoadedStartURL = true
        // Try to restore last visited URL for this site
        var startURL: URL = site.url
        if let lastStr = UserDefaults.standard.string(forKey: "Vaaka.LastURL.\(site.id)"),
           let lastURL = URL(string: lastStr),
           SiteManager.hostMatches(host: lastURL.host, siteHost: site.url.host) {
            startURL = lastURL
        }
        var req = URLRequest(url: startURL)
        // If Send-DNT is enabled, include the DNT header for top-level loads
        if UserDefaults.standard.bool(forKey: "Vaaka.SendDNT") {
            req.setValue("1", forHTTPHeaderField: "DNT")
        }

        let _ = webView.load(req)

        // Inject dark mode CSS if the preference is not light-only
        injectDarkModeCSS()

        // Start a watchdog: if navigation hasn't begun in 10s, fall back and open externally.
        let wi = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.webView.url == nil {
                Telemetry.shared.recordLoadWatchdog(siteId: self.site.id)
                NSWorkspace.shared.open(self.site.url)
                // Ensure UI spinner is not left running
                NotificationCenter.default.post(name: Notification.Name("Vaaka.SiteTabDidFinishLoading"), object: self.site.id)
            }
        }
        loadingWatchdogWorkItem = wi
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0, execute: wi)
    }

    /// Inject dark mode CSS based on the preference.
    private func injectDarkModeCSS() {
        let preference = AppearanceManager.shared.darkModePreference
        guard preference != .light else { return }

        let isDarkMode: Bool
        switch preference {
        case .light:
            isDarkMode = false
        case .dark:
            isDarkMode = true
        case .system:
            // Use effectiveAppearance instead of deprecated NSAppearance.current
            isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }

        // Set the color-scheme on the document element to force dark or light mode
        let js = """
        (function() {
            document.documentElement.style.colorScheme = '\(isDarkMode ? "dark" : "light")';
        })();
        """

        webView.evaluateJavaScript(js)
    }

    /// Display an internal error page for the current site with Retry / Open in Browser / Dismiss buttons.
    func showErrorPage(errorDescription: String, failedURL: String, displayHost: String? = nil) {
        func escape(_ s: String) -> String {
            var r = s.replacingOccurrences(of: "&", with: "&amp;")
            r = r.replacingOccurrences(of: "<", with: "&lt;")
            r = r.replacingOccurrences(of: ">", with: "&gt;")
            r = r.replacingOccurrences(of: "\"", with: "&quot;")
            return r
        }

        let title = escape(site.name)
        let linkHref = escape(failedURL)
        let displayText = escape(displayHost ?? (URL(string: failedURL)?.host ?? failedURL))
        let desc = escape(errorDescription)
        let html = """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <style>
            body { font-family: -apple-system, Helvetica, Arial; margin: 40px; color: #333; background: #fff; }
            .container { max-width: 820px; margin: auto; text-align: left; }
            h1 { font-size: 20px; margin-bottom: 8px; }
            p { color: #666; margin-top: 0; }
            .desc { margin-top: 12px; color: #a00; }
            .actions { margin-top: 20px; }
            button { margin-right: 8px; padding: 8px 12px; font-size: 13px; border-radius: 6px; border: 1px solid #cfcfcf; background: #f7f7f7; }
            button.primary { background: #007aff; color: white; border: none; }
            a { color: #007aff; }
          </style>
        </head>
        <body>
          <div class="container">
            <h1>Failed to load \(title)</h1>
            <p>Could not load <a href="\(linkHref)" target="_blank">\(displayText)</a></p>
            <p class="desc">\(desc)</p>
            <div class="actions">
              <button class="primary" onclick='window.webkit.messageHandlers.vaakaError.postMessage({action: "retry"})'>Retry</button>
              <button onclick='window.webkit.messageHandlers.vaakaError.postMessage({action: "open"})'>Open in Browser</button>
              <button onclick='window.webkit.messageHandlers.vaakaError.postMessage({action: "dismiss"})'>Dismiss</button>
            </div>
          </div>
        </body>
        </html>
        """

        DispatchQueue.main.async {
            // Ensure the tab is visible
            if let idx = SiteTabManager.shared.tabs.firstIndex(where: { $0.site.id == self.site.id }) {
                SiteTabManager.shared.setActiveIndex(idx)
                self.webView.isHidden = false
            }
            self.webView.loadHTMLString(html, baseURL: nil)
        }
    }
}

