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
                print("[DEBUG] SiteTab: re-hiding webView after navigation started for site.id=\(self.site.id)")
                self.webView.isHidden = true
                self.temporarilyUnhiddenForLoad = false
            }

            self.navigationStuckWorkItem?.cancel()
            let stuckTimeout: TimeInterval = ProcessInfo.processInfo.arguments.contains("--test-short-wd") ? 5.0 : 20.0
            let wi = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                if self.navigationInProgress {
                    print("[WARN] SiteTab.navigation stuck watchdog fired: site.id=\(self.site.id) url=\(self.site.url.absoluteString) — attempting in-app recovery")
                    DispatchQueue.main.async {
                        // Try to recover by activating the tab (makes WebView visible) and reloading once.
                        if let idx = SiteTabManager.shared.tabs.firstIndex(where: { $0.site.id == self.site.id }) {
                            print("[DEBUG] SiteTab.navigation stuck: activating tab idx=\(idx) id=\(self.site.id) and reloading")
                            SiteTabManager.shared.setActiveIndex(idx)
                            self.webView.reload()
                            // Telemetry: note we've fired the stuck watchdog and attempted in-app recovery
                            Telemetry.shared.recordStuckWatchdog(siteId: self.site.id, phase: "recovery_attempt")
                            // Schedule a final fallback: open externally if reload doesn't finish within another `stuckTimeout` seconds.
                            self.navigationStuckWorkItem?.cancel()
                            let finalWi = DispatchWorkItem { [weak self] in
                                guard let self = self else { return }
                                if self.navigationInProgress {
                                    print("[WARN] SiteTab.navigation final watchdog fired: site.id=\(self.site.id) — opening externally")
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
        let req = URLRequest(url: site.url)

        // Optional diagnostic: temporarily unhide the WebView for the first load if the test flag is present.
        if ProcessInfo.processInfo.arguments.contains("--test-unhide-before-load") {
            print("[DEBUG] SiteTab.loadStartURLIfNeeded: temporarily un-hiding webView for site.id=\(site.id)")
            webView.isHidden = false
            temporarilyUnhiddenForLoad = true
        }

        print("[DEBUG] SiteTab.loadStartURLIfNeeded: site.id=\(site.id) url=\(site.url.absoluteString) webViewHidden=\(webView.isHidden) — calling webView.load")
        let nav = webView.load(req)
        print("[DEBUG] SiteTab.loadStartURLIfNeeded: webView.load returned navigation=\(nav != nil ? "non-nil" : "nil")")

        // Start a watchdog: if navigation hasn't begun in 10s, fall back and open externally.
        let wi = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.webView.url == nil {
                print("[WARN] SiteTab.load watchdog fired: site.id=\(self.site.id) url=\(self.site.url.absoluteString) — opening externally")
                Telemetry.shared.recordLoadWatchdog(siteId: self.site.id)
                NSWorkspace.shared.open(self.site.url)
                // Ensure UI spinner is not left running
                NotificationCenter.default.post(name: Notification.Name("Vaaka.SiteTabDidFinishLoading"), object: self.site.id)
            }
        }
        loadingWatchdogWorkItem = wi
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0, execute: wi)
    }
}
