import Foundation
import AppKit
import WebKit

extension Notification.Name {
    static let TabsChanged = Notification.Name("Vaaka.TabsChanged")
    static let ActiveTabChanged = Notification.Name("Vaaka.ActiveTabChanged")
    // Emitted when a navigation fails with error. userInfo may contain: "siteId" (String), "url" (String), "errorDomain" (String), "errorCode" (Int), "errorDescription" (String)
    static let SiteTabDidFailLoading = Notification.Name("Vaaka.SiteTabDidFailLoading")
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
            // NOTE: Do not automatically clear unread counts when a tab becomes active.
            // Unread counts are now preserved until explicitly cleared by user action.
        }
    }

    private let lastActiveKey = "Vaaka.LastActiveSiteID"

    private override init() {
        super.init()
        // Build tabs from current sites
        rebuildTabs()
        NotificationCenter.default.addObserver(self, selector: #selector(sitesChanged), name: .SitesChanged, object: nil)
        restoreLastActiveSite()
        // Initialization complete — flip flag and notify observers once (defer notifications to next run loop to avoid re-entrancy during static init)
        isBootstrapping = false
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .TabsChanged, object: self)
            NotificationCenter.default.post(name: .ActiveTabChanged, object: self)
        }
    }

    @objc private func sitesChanged() {
        // Rebuild SiteTabs when SiteManager replaces sites. Create new webviews for new sites, destroy removed ones.
        rebuildTabs()
    }

    private func rebuildTabs() {
        let sites = SiteManager.shared.sites
        // Create tabs in same order; reuse existing SiteTab instances where the site id is unchanged
        var newTabs: [SiteTab] = []

        // Map existing tabs by site id for reuse
        var existingById: [String: SiteTab] = [:]
        for t in tabs { existingById[t.site.id] = t }

        for site in sites {
            if let existing = existingById[site.id] {
                // Update the existing tab's Site value in case metadata (favicon, name) changed
                existing.site = site
                newTabs.append(existing)
                // Remove from existingById map — remaining entries will be considered removed
                existingById.removeValue(forKey: site.id)
                continue
            }

            let config = WKWebViewConfiguration()
            let webpagePreferences = WKWebpagePreferences()
            webpagePreferences.allowsContentJavaScript = true
            config.defaultWebpagePreferences = webpagePreferences

            let userContent = WKUserContentController()
            userContent.add(ErrorMessageHandler(siteId: site.id), name: "vaakaError")
            // Add tracker-blocking rules if the feature is enabled and compiled
            ContentBlockerManager.shared.addTo(userContentController: userContent)
            config.userContentController = userContent

            // Create a SiteTab that manages its own configuration internally
            let tab = SiteTab(site: site)
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
        tabs = newTabs
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
        // Allow in-page navigation and navigations that remain within the owning site's domain (subdomains allowed).
        // Use hostMatches directly to avoid relying on Site (value) equality which may be brittle across reloads.
        if let urlHost = url.host, SiteManager.hostMatches(host: urlHost, siteHost: site.url.host) {
            return decisionHandler(.allow)
        }

        // If this navigation is the result of a user clicking a link, determine policy (external for SSO IdPs or external links)
        if navigationAction.navigationType == .linkActivated {
            let abs = url.absoluteString
            if let sch = url.scheme?.lowercased(), sch == "data" || sch == "blob" || sch == "about" || abs.hasPrefix("about:") {
                return decisionHandler(.allow)
            }

            // If the link target actually belongs to the same site (including registrable root), allow it in-app
            if let urlHost = url.host, SiteManager.hostMatches(host: urlHost, siteHost: site.url.host) {
                return decisionHandler(.allow)
            }

            // If the link looks like an SSO/IdP target, open externally by default to avoid embedded-browser failures.
            let isSSO = SSODetector.isSSO(url)
            if isSSO {
                NSWorkspace.shared.open(url)
                return decisionHandler(.cancel)
            }

            NSWorkspace.shared.open(url)
            return decisionHandler(.cancel)
        }

        // For non-user-initiated navigations (e.g., redirects, script-driven), allow them — resources from other domains are permitted.
        return decisionHandler(.allow)
    }

    // Notify BrowserWindow about start/finish to allow UI updates (loading indicators)
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        NotificationCenter.default.post(name: Notification.Name("Vaaka.SiteTabDidStartLoading"), object: site.id)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        NotificationCenter.default.post(name: Notification.Name("Vaaka.SiteTabDidFinishLoading"), object: site.id)
        if let u = webView.url, let host = u.host, SiteManager.hostMatches(host: host, siteHost: site.url.host) {
            UserDefaults.standard.set(u.absoluteString, forKey: "Vaaka.LastURL.\(site.id)")
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsErr = error as NSError
        NotificationCenter.default.post(name: Notification.Name("Vaaka.SiteTabDidFinishLoading"), object: site.id)
        NotificationCenter.default.post(name: .SiteTabDidFailLoading, object: nil, userInfo: ["siteId": site.id, "url": webView.url?.absoluteString ?? "<no-url>", "errorDomain": nsErr.domain, "errorCode": nsErr.code, "errorDescription": nsErr.localizedDescription])
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let nsErr = error as NSError
        NotificationCenter.default.post(name: Notification.Name("Vaaka.SiteTabDidFinishLoading"), object: site.id)
        NotificationCenter.default.post(name: .SiteTabDidFailLoading, object: nil, userInfo: ["siteId": site.id, "url": webView.url?.absoluteString ?? "<no-url>", "errorDomain": nsErr.domain, "errorCode": nsErr.code, "errorDescription": nsErr.localizedDescription])
    }

    // Handle content process termination which can leave the WebView blank — attempt in-app recovery
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Logger.shared.debug("[DEBUG] webViewWebContentProcessDidTerminate received for site: \(site.name)")
        // Find the SiteTab for this webView and ask it to recover
        if let tab = SiteTabManager.shared.tabs.first(where: { $0.site.id == site.id }) {
            tab.handleContentProcessTermination()
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        // If the response is not displayable by WebKit (e.g., unknown MIME) or explicitly marked as an attachment,
        // treat it as a download so we can manage it via WKDownload and avoid embedding potentially large or binary blobs.
        if !navigationResponse.canShowMIMEType {
            return decisionHandler(.download)
        }

        if let http = navigationResponse.response as? HTTPURLResponse,
           let cd = http.allHeaderFields["Content-Disposition"] as? String,
           cd.lowercased().contains("attachment") {
            return decisionHandler(.download)
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        Logger.shared.debug("[DEBUG] navigationResponse didBecome WKDownload for site: \(site.name)")
        // Locate the corresponding SiteTab and attach a handler to manage the download lifecycle and destination.
        if let tab = SiteTabManager.shared.tabs.first(where: { $0.webView == webView }) {
            let handler = SiteTab.SiteDownloadHandler(siteTab: tab, download: download)
            // Do NOT pre-register a download entry — wait until the handler's
            // decideDestination step confirms the destination (user Save) before
            // adding the DownloadsManager entry. This prevents placeholder "Download"
            // rows with 0% progress when the user cancels the Save panel.
            tab.registerDownloadHandler(handler, for: download)
            download.delegate = handler
        }
    }
}

// Handle actions coming from our internal error page (Retry / Open in Browser / Dismiss)
final class ErrorMessageHandler: NSObject, WKScriptMessageHandler {
    private let siteId: String
    init(siteId: String) { self.siteId = siteId }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "vaakaError" else { return }
        if let body = message.body as? [String: Any], let action = body["action"] as? String {
            DispatchQueue.main.async {
                guard let tab = SiteTabManager.shared.tabs.first(where: { $0.site.id == self.siteId }) else { return }
                switch action {
                case "retry":
                    tab.webView.load(URLRequest(url: tab.site.url))
                case "open":
                    NSWorkspace.shared.open(tab.site.url)
                case "dismiss":
                    tab.webView.loadHTMLString("", baseURL: nil)
                default:
                    break
                }
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
        
        // Ignore special schemes (data, blob, about)
        if let scheme = url.scheme?.lowercased(), scheme == "data" || scheme == "blob" || scheme == "about" || url.absoluteString.hasPrefix("about:") {
            return nil
        }
        
        // If same site, load in current window instead of opening new window/tab
        if SiteManager.shared.site(for: url) == site {
            webView.load(URLRequest(url: url))
            return nil
        }
        
        // For external URLs, open in default browser instead of new window
        NSWorkspace.shared.open(url)
        return nil
    }

    // Support <input type="file"> by presenting an NSOpenPanel and returning selected URLs
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.beginSheetModal(for: webView.window ?? NSApp.keyWindow ?? NSWindow()) { response in
            if response == .OK {
                completionHandler(panel.urls)
            } else {
                completionHandler(nil)
            }
        }
    }
}


