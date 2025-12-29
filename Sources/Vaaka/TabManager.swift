import Foundation
import AppKit
import WebKit

extension Notification.Name {
    static let TabsChanged = Notification.Name("Vaaka.TabsChanged")
    static let ActiveTabChanged = Notification.Name("Vaaka.ActiveTabChanged")
}

/// Manages the 1:1 Site -> SiteTab relationship and ensures all SiteTabs exist at launch
/// and are kept in order. Tabs are immutable at runtime except when `SiteManager` replaces the sites.
final class SiteTabManager: NSObject {
    static let shared = SiteTabManager()

    private var isBootstrapping: Bool = true

    private(set) var tabs: [SiteTab] = [] {
        didSet {
            // Avoid posting notifications during initialization to prevent re-entrant observers
            if !isBootstrapping {
                NotificationCenter.default.post(name: .TabsChanged, object: self)
            }
        }
    }

    private(set) var activeIndex: Int = 0 {
        didSet {
            NotificationCenter.default.post(name: .ActiveTabChanged, object: self)
            persistLastActiveSite()
        }
    }

    private let lastActiveKey = "Vaaka.LastActiveSiteID"

    private override init() {
        super.init()
        print("[DEBUG] SiteTabManager.init start")
        // Build tabs from current sites
        rebuildTabs()
        print("[DEBUG] SiteTabManager.init after rebuild: tabs=\(tabs.count)")
        NotificationCenter.default.addObserver(self, selector: #selector(sitesChanged), name: .SitesChanged, object: nil)
        restoreLastActiveSite()
        // Initialization complete — flip flag and notify observers once (defer notifications to next run loop to avoid re-entrancy during static init)
        isBootstrapping = false
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .TabsChanged, object: self)
            NotificationCenter.default.post(name: .ActiveTabChanged, object: self)
        }
        print("[DEBUG] SiteTabManager.init done: activeIndex=\(activeIndex)")
    }

    @objc private func sitesChanged() {
        // Rebuild SiteTabs when SiteManager replaces sites. Create new webviews for new sites, destroy removed ones.
        rebuildTabs()
    }

    private func rebuildTabs() {
        let sites = SiteManager.shared.sites
        // Diagnostic: log currently existing tabs and their URLs to help track unexpected blanking
        let existingInfo = tabs.map { "\($0.site.id):\($0.webView.url?.absoluteString ?? "<no-url>")" }
        print("[DEBUG] rebuildTabs: existing tabs count=\(tabs.count) info=\(existingInfo)")

        // Create tabs in same order; reuse existing SiteTab instances where the site id is unchanged
        var newTabs: [SiteTab] = []
        print("[DEBUG] rebuildTabs: sites.count=\(sites.count)")

        // Map existing tabs by site id for reuse
        var existingById: [String: SiteTab] = [:]
        for t in tabs { existingById[t.site.id] = t }

        for site in sites {
            if let existing = existingById[site.id] {
                print("[DEBUG] rebuildTabs: reusing tab for site id=\(site.id) name=\(site.name)")
                newTabs.append(existing)
                // Remove from existingById map — remaining entries will be considered removed
                existingById.removeValue(forKey: site.id)
                continue
            }

            print("[DEBUG] rebuildTabs: creating tab for site id=\(site.id) name=\(site.name)")
            let config = WKWebViewConfiguration()
            let webpagePreferences = WKWebpagePreferences()
            webpagePreferences.allowsContentJavaScript = true
            config.defaultWebpagePreferences = webpagePreferences

            // Diagnostics: forward console.* messages from pages to the host app for debugging
            let userContent = WKUserContentController()
            let consoleScript = """
            (function () {
              function serializeArgs(args) {
                return Array.prototype.slice.call(args).map(function (a) {
                  try { return typeof a === 'string' ? a : JSON.stringify(a); } catch (e) { return String(a); }
                });
              }
              ['log','warn','error','info'].forEach(function(level) {
                var orig = console[level];
                console[level] = function() {
                  try {
                     window.webkit.messageHandlers.vaakaConsole.postMessage({level: level, args: serializeArgs(arguments)});
                  } catch (e) {}
                  orig && orig.apply(console, arguments);
                };
              });
            })();
            """
            let script = WKUserScript(source: consoleScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            userContent.addUserScript(script)
            userContent.add(ConsoleMessageHandler(siteId: site.id), name: "vaakaConsole")
            config.userContentController = userContent

            // Each WebView gets its own configuration
            let tab = SiteTab(site: site, configuration: config)
            // Make the WebView appear like Safari to servers that vary content by UA
            tab.webView.customUserAgent = UserAgent.safari
            // Navigation delegate to enforce whitelist (keep strong reference on the tab)
            let nav = SelfNavigationDelegate(site: site)
            tab.navigationDelegateStored = nav
            tab.webView.navigationDelegate = nav
            // UI delegate to handle window.open and similar; keep strong reference
            let ui = SelfUIDelegate(site: site)
            tab.webView.uiDelegate = ui
            tab.uiDelegateStored = ui
            // Keep webviews loaded but hidden in UI (hide/show handled by BrowserWindow)
            newTabs.append(tab)
        }
        // Any site ids still present in `existingById` are removed — their webviews should be cleaned by BrowserWindow
        if !existingById.isEmpty {
            print("[DEBUG] rebuildTabs: removed site ids=\(Array(existingById.keys))")
        }
        tabs = newTabs
        let newInfo = tabs.map { "\($0.site.id):\($0.webView.url?.absoluteString ?? "<no-url>")" }
        print("[DEBUG] rebuildTabs: new tabs count=\(tabs.count) info=\(newInfo)")
        // Adjust active index to valid range
        if tabs.isEmpty {
            activeIndex = 0
        } else if activeIndex >= tabs.count {
            activeIndex = 0
        }
    }

    func setActiveIndex(_ idx: Int) {
        guard idx >= 0 && idx < tabs.count else { return }
        activeIndex = idx
    }

    func activeTab() -> SiteTab? {
        guard activeIndex >= 0 && activeIndex < tabs.count else { return nil }
        return tabs[activeIndex]
    }

    // MARK: - Persistence
    private func persistLastActiveSite() {
        guard let site = activeTab()?.site else { UserDefaults.standard.removeObject(forKey: lastActiveKey); return }
        UserDefaults.standard.set(site.id, forKey: lastActiveKey)
    }

    private func restoreLastActiveSite() {
        guard let lastId = UserDefaults.standard.string(forKey: lastActiveKey) else {
            // default to first site when available
            if !tabs.isEmpty { activeIndex = 0 }
            return
        }
        if let idx = tabs.firstIndex(where: { $0.site.id == lastId }) {
            activeIndex = idx
        } else {
            // If last active site was removed, activate first site per spec.
            activeIndex = tabs.isEmpty ? 0 : 0
        }
    }
}

// MARK: - Navigation Delegate enforcing whitelist
private final class SelfNavigationDelegate: NSObject, WKNavigationDelegate {
    private let site: Site

    init(site: Site) {
        self.site = site
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { return decisionHandler(.cancel) }
        // Allow data/blob/about:blank navigations (no external open)
        if let scheme = url.scheme?.lowercased(), scheme == "data" || scheme == "blob" || scheme == "about" || url.absoluteString.hasPrefix("about:") {
            return decisionHandler(.allow)
        }
        // Allow in-page navigation and navigations that remain within the owning site's domain (subdomains allowed)
        if SiteManager.shared.site(for: url) == site {
            return decisionHandler(.allow)
        }

        // If this navigation is the result of a user clicking a link, open externally and cancel in-app.
        if navigationAction.navigationType == .linkActivated {
            let abs = url.absoluteString
            if let sch = url.scheme?.lowercased(), sch == "data" || sch == "blob" || sch == "about" || abs.hasPrefix("about:") {
                // treat as internal — allow quietly
                print("[DEBUG] Ignoring internal navigation attempt to \(url)")
                return decisionHandler(.allow)
            }
            print("[DEBUG] User clicked external link -> opening in default browser: \(url)")
            NSWorkspace.shared.open(url)
            return decisionHandler(.cancel)
        }

        // For non-user-initiated navigations (e.g., redirects, script-driven), allow them — resources from other domains are permitted.
        return decisionHandler(.allow)
    }

    // Notify BrowserWindow about start/finish to allow UI updates (loading indicators)
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        print("[DEBUG] navigation: didStartProvisionalNavigation for site.id=\(site.id) url=\(webView.url?.absoluteString ?? "<no-url>") hidden=\(webView.isHidden) navigationNonNil=\(navigation != nil)")
        NotificationCenter.default.post(name: Notification.Name("Vaaka.SiteTabDidStartLoading"), object: site.id)
        // Telemetry: record navigation start
        Telemetry.shared.recordNavigationStart(siteId: site.id, url: webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("[DEBUG] navigation: didFinish for site.id=\(site.id) url=\(webView.url?.absoluteString ?? "<no-url>") hidden=\(webView.isHidden)")
        NotificationCenter.default.post(name: Notification.Name("Vaaka.SiteTabDidFinishLoading"), object: site.id)
        // Telemetry: record navigation finish
        Telemetry.shared.recordNavigationFinish(siteId: site.id, url: webView.url)
        // For diagnostics: capture the effective navigator.userAgent seen by pages so we can
        // verify servers and scripts will see the desired Safari-like UA.
        webView.evaluateJavaScript("navigator.userAgent") { result, error in
            if let ua = result as? String {
                print("[DEBUG] navigator.userAgent: site.id=\(self.site.id) ua=\(ua)")
            } else if let err = error {
                print("[DEBUG] navigator.userAgent: site.id=\(self.site.id) error=\(err)")
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsErr = error as NSError
        print("[WARN] navigation: didFailProvisionalNavigation for site.id=\(site.id) url=\(webView.url?.absoluteString ?? "<no-url>") errorDomain=\(nsErr.domain) code=\(nsErr.code) desc=\(nsErr.localizedDescription) hidden=\(webView.isHidden)")
        NotificationCenter.default.post(name: Notification.Name("Vaaka.SiteTabDidFinishLoading"), object: site.id)
        // Telemetry: record failure
        Telemetry.shared.recordNavigationFailure(siteId: site.id, url: webView.url, domain: nsErr.domain, code: nsErr.code, description: nsErr.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let nsErr = error as NSError
        print("[WARN] navigation: didFail for site.id=\(site.id) url=\(webView.url?.absoluteString ?? "<no-url>") errorDomain=\(nsErr.domain) code=\(nsErr.code) desc=\(nsErr.localizedDescription) hidden=\(webView.isHidden)")
        NotificationCenter.default.post(name: Notification.Name("Vaaka.SiteTabDidFinishLoading"), object: site.id)
        // Telemetry: record failure
        Telemetry.shared.recordNavigationFailure(siteId: site.id, url: webView.url, domain: nsErr.domain, code: nsErr.code, description: nsErr.localizedDescription)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(.allow)
    }
}

private final class ConsoleMessageHandler: NSObject, WKScriptMessageHandler {
    private let siteId: String
    init(siteId: String) {
        self.siteId = siteId
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "vaakaConsole" {
            if let body = message.body as? [String: Any] {
                let level = body["level"] as? String ?? "log"
                let args = body["args"] as? [String] ?? []
                print("[JS-\(level)] site.id=\(siteId) message=\(args.joined(separator: " "))")
            } else {
                print("[JS] site.id=\(siteId) message=\(message.body)")
            }
        }
    }
}

// Handle UI-level requests such as window.open. For safety, any attempt to open a URL outside the originating site's host is blocked and opened in the external browser instead.
private final class SelfUIDelegate: NSObject, WKUIDelegate {
    private let site: Site

    init(site: Site) {
        self.site = site
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        // Ignore about/data/blob requests here — they are internal
        if let scheme = url.scheme?.lowercased(), scheme == "data" || scheme == "blob" || scheme == "about" || url.absoluteString.hasPrefix("about:") {
            // Let the existing webview handle it if needed
            return nil
        }
        if SiteManager.shared.site(for: url) == site {
            // load in existing webview (no new window)
            webView.load(URLRequest(url: url))
            return nil
        }
        // Open external URLs in default browser and do not create new WebViews
        let abs = url.absoluteString
        if let sch = url.scheme?.lowercased(), sch == "data" || sch == "blob" || sch == "about" || abs.hasPrefix("about:") {
            print("[DEBUG] Ignoring internal createWebView request for \(url)")
            return nil
        }
        print("[DEBUG] Opening external URL from UI delegate: \(url)")
        NSWorkspace.shared.open(url)
        return nil
    }
}
