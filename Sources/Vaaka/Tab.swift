import Foundation
import WebKit
import AppKit

/// Represents a loaded Site tab: one `WKWebView` per `Site`.
final class SiteTab: NSObject {
    var site: Site
    var webView: WKWebView

    // Keep a strong reference to the navigation delegate used to enforce whitelist
    var navigationDelegateStored: WKNavigationDelegate?
    var uiDelegateStored: WKUIDelegate?

    // Message handlers (keep strong references to prevent deallocation)
    private var notificationHandler: NotificationMessageHandler?
    private var badgeHandler: BadgeUpdateHandler?
    private var consoleHandler: ConsoleMessageHandler?

    // Deduplication tracking for notifications
    var lastNotificationTimes: [String: Date] = [:]

    private var hasLoadedStartURL: Bool = false
    private var loadingWatchdogWorkItem: DispatchWorkItem?
    private var navigationStuckWorkItem: DispatchWorkItem?
    private var navigationInProgress: Bool = false
    // When exercising the visibility experiment via `--test-unhide-before-load` we temporarily unhide
    // the WebView during the initial load; this flag lets us re-hide it after navigation actually starts.
    private var temporarilyUnhiddenForLoad: Bool = false

    // Timer used to refresh dynamic favicons (e.g., Google Calendar daily favicon)
    private var faviconRefreshTimer: DispatchSourceTimer?

    // Tokens for NotificationCenter closure observers so we can unregister them
    private var startLoadingObserver: NSObjectProtocol?
    private var finishLoadingObserver: NSObjectProtocol?



    init(site: Site) {
        self.site = site

        // Create fresh configuration for this tab
        let configuration = WKWebViewConfiguration()
        // Use an ephemeral data store per tab to isolate cookies/storage
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        let webpagePreferences = WKWebpagePreferences()
        webpagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = webpagePreferences


        // Configure content controller and content-blocking for this tab
        let userContent = WKUserContentController()
        userContent.add(ErrorMessageHandler(siteId: site.id), name: "vaakaError")
        ContentBlockerManager.shared.addTo(userContentController: userContent)
        configuration.userContentController = userContent

        self.webView = SiteTab.makeWebView(configuration: configuration)
        super.init()

        // Use this tab's userContentController for scripts and handlers
        let ucc = self.webView.configuration.userContentController

        #if DEBUG
        // Log configuration identity for debugging
        Logger.shared.debug("[DEBUG][SiteTab] init site=\(site.name) webView=\(ObjectIdentifier(self.webView)) config=\(ObjectIdentifier(self.webView.configuration)) ucc=\(ObjectIdentifier(self.webView.configuration.userContentController)) dataStore=\(ObjectIdentifier(self.webView.configuration.websiteDataStore))")
        #endif

        // Always inject badge detection (works even without simulation)
        let badgeScript = WKUserScript(source: BadgeDetector.script, injectionTime: .atDocumentEnd, forMainFrameOnly: !UserDefaults.standard.bool(forKey: "Vaaka.NotificationsEnabledGlobal"))
        ucc.addUserScript(badgeScript)

        // Inject console forwarder to capture JS console/error messages (helps when the Web Inspector is broken)
        let consoleScript = WKUserScript(source: ConsoleForwarder.script, injectionTime: .atDocumentStart, forMainFrameOnly: !UserDefaults.standard.bool(forKey: "Vaaka.NotificationsEnabledGlobal"))
        ucc.addUserScript(consoleScript)
        let cHandler = ConsoleMessageHandler(siteTab: self)
        self.consoleHandler = cHandler
        ucc.add(cHandler, name: "consoleMessage")

        // If a badge handler wasn't created above (simulation disabled), register a lightweight one
        if self.badgeHandler == nil {
            let badgeHandler = BadgeUpdateHandler(siteTab: self)
            self.badgeHandler = badgeHandler
            ucc.add(badgeHandler, name: "badgeUpdate")
        }

        // Add notification message handler to support the Notification interceptor script
        let nHandler = NotificationMessageHandler(siteTab: self)
        self.notificationHandler = nHandler
        ucc.add(nHandler, name: "notificationRequest")

        // Context menu interceptor to enable native Save Image handling
        let ctxScript = WKUserScript(source: ContextMenuInterceptor.script, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        ucc.addUserScript(ctxScript)
        let ctxHandler = ContextMenuHandler(siteTab: self)
        ucc.add(ctxHandler, name: "contextMenu")

            // Observe start events for this site so we can cancel watchdogs
        self.startLoadingObserver = NotificationCenter.default.addObserver(forName: Notification.Name("Vaaka.SiteTabDidStartLoading"), object: nil, queue: .main) { [weak self] note in
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

            // If a favicon refresh timer is running, stop it while navigation is in progress
            self.stopFaviconRefresh()

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
                            // Schedule a final fallback: open externally if reload doesn't finish within another `stuckTimeout` seconds.
                            self.navigationStuckWorkItem?.cancel()
                            let finalWi = DispatchWorkItem { [weak self] in
                                guard let self = self else { return }
                                if self.navigationInProgress {
                                    NSWorkspace.shared.open(self.site.url)
                                    NotificationCenter.default.post(name: Notification.Name("Vaaka.SiteTabDidFinishLoading"), object: self.site.id)
                                    self.navigationInProgress = false
                                }
                            }
                            self.navigationStuckWorkItem = finalWi
                            DispatchQueue.main.asyncAfter(deadline: .now() + stuckTimeout, execute: finalWi)
                        } else {
                            // No tab index found — open externally as a fallback
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
        self.finishLoadingObserver = NotificationCenter.default.addObserver(forName: Notification.Name("Vaaka.SiteTabDidFinishLoading"), object: nil, queue: .main) { [weak self] note in
            guard let self = self, let id = note.object as? String, id == self.site.id else { return }
            // Cancel any in-flight watchdogs and clear navigation state
            self.loadingWatchdogWorkItem?.cancel()
            self.loadingWatchdogWorkItem = nil
            self.navigationStuckWorkItem?.cancel()
            self.navigationStuckWorkItem = nil
            self.navigationInProgress = false

            // After navigation completes, start dynamic favicon refresh if appropriate
            self.startFaviconRefreshIfNeeded()
        }

        // Do not load the start URL immediately — wait until the WebView is attached to the window/content view.
        // This avoids spurious `open` attempts while the WebView is not yet part of the responder/window chain.

    }

    deinit {
        loadingWatchdogWorkItem?.cancel()

        // Unregister closure-based observers if present
        if let o = startLoadingObserver { NotificationCenter.default.removeObserver(o); startLoadingObserver = nil }
        if let o = finishLoadingObserver { NotificationCenter.default.removeObserver(o); finishLoadingObserver = nil }

        NotificationCenter.default.removeObserver(self)
        // Clean up injected script message handlers if present
        let ucc = webView.configuration.userContentController
        // Remove handlers we added during init
        ucc.removeScriptMessageHandler(forName: "vaakaError")
        ucc.removeScriptMessageHandler(forName: "contextMenu")
        if badgeHandler != nil {
            ucc.removeScriptMessageHandler(forName: "badgeUpdate")
        }
        if notificationHandler != nil {
            ucc.removeScriptMessageHandler(forName: "notificationRequest")
        }
        if consoleHandler != nil {
            ucc.removeScriptMessageHandler(forName: "consoleMessage")
        }
        badgeHandler = nil
        notificationHandler = nil
        consoleHandler = nil
        lastNotificationTimes.removeAll()
        stopFaviconRefresh()
    }

    // Create a fresh WKWebView with the provided configuration. This centralizes creation so
    // we can recreate web views after content process termination/crashes.
    private static func makeWebView(configuration: WKWebViewConfiguration) -> WKWebView {
        let w = WKWebView(frame: .zero, configuration: configuration)
        w.customUserAgent = UserAgent.safari
        w.translatesAutoresizingMaskIntoConstraints = false
        return w
    }

    /// Called when the web content process terminates/crashes. Attempt a graceful in-app recovery
    /// by replacing the WKWebView with a fresh instance using the same configuration, re-adding
    /// user scripts and message handlers, and restoring the last-known URL. If recovery fails,
    /// we fall back to opening externally after a short timeout.
    func handleContentProcessTermination() {
        DispatchQueue.main.async {
            Logger.shared.debug("[DEBUG] webContentProcessDidTerminate for site: \(self.site.name)")

            // Make the tab active so the user can see recovery progress
            if let idx = SiteTabManager.shared.tabs.firstIndex(where: { $0.site.id == self.site.id }) {
                SiteTabManager.shared.setActiveIndex(idx)
            }

            // Create new webview with a fresh configuration (avoid reusing old.configuration which can cause state sharing)
            let old = self.webView
            let newConfig = WKWebViewConfiguration()
            // Use an ephemeral data store for recovered webviews to avoid sharing site state
            newConfig.websiteDataStore = WKWebsiteDataStore.nonPersistent()
            let webpagePreferences = WKWebpagePreferences()
            webpagePreferences.allowsContentJavaScript = true
            newConfig.defaultWebpagePreferences = webpagePreferences
            let newUserContent = WKUserContentController()
            newUserContent.add(ErrorMessageHandler(siteId: self.site.id), name: "vaakaError")
            ContentBlockerManager.shared.addTo(userContentController: newUserContent)
            newConfig.userContentController = newUserContent

            let new = SiteTab.makeWebView(configuration: newConfig)

            // Log replacement details for debugging
            #if DEBUG
            Logger.shared.debug("[DEBUG][SiteTab] contentProcessRecovery site=\(self.site.name) oldWebView=\(ObjectIdentifier(old)) newWebView=\(ObjectIdentifier(new)) newConfig=\(ObjectIdentifier(new.configuration)) newUCC=\(ObjectIdentifier(new.configuration.userContentController))")
            #endif

            // Reinstall user scripts / handlers bound to this SiteTab
            let ucc = new.configuration.userContentController
            let badgeScript = WKUserScript(source: BadgeDetector.script, injectionTime: .atDocumentEnd, forMainFrameOnly: !UserDefaults.standard.bool(forKey: "Vaaka.NotificationsEnabledGlobal"))
            ucc.addUserScript(badgeScript)
            let consoleScript = WKUserScript(source: ConsoleForwarder.script, injectionTime: .atDocumentStart, forMainFrameOnly: !UserDefaults.standard.bool(forKey: "Vaaka.NotificationsEnabledGlobal"))
            ucc.addUserScript(consoleScript)

            let cHandler = ConsoleMessageHandler(siteTab: self)
            self.consoleHandler = cHandler
            ucc.add(cHandler, name: "consoleMessage")

            if self.badgeHandler == nil {
                let badgeHandler = BadgeUpdateHandler(siteTab: self)
                self.badgeHandler = badgeHandler
                ucc.add(badgeHandler, name: "badgeUpdate")
            }

            let nHandler = NotificationMessageHandler(siteTab: self)
            self.notificationHandler = nHandler
            ucc.add(nHandler, name: "notificationRequest")

            // Reinstall context menu interceptor
            let ctxScript = WKUserScript(source: ContextMenuInterceptor.script, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            ucc.addUserScript(ctxScript)
            let ctxHandler = ContextMenuHandler(siteTab: self)
            ucc.add(ctxHandler, name: "contextMenu")

            // Copy delegates so whitelist / window.open handling continues to work
            if let nav = self.navigationDelegateStored { new.navigationDelegate = nav }
            if let ui = self.uiDelegateStored { new.uiDelegate = ui }

            // Insert into existing superview to preserve layout
            if let sv = old.superview {
                sv.addSubview(new)
                NSLayoutConstraint.activate([
                    new.leadingAnchor.constraint(equalTo: sv.leadingAnchor),
                    new.trailingAnchor.constraint(equalTo: sv.trailingAnchor),
                    new.topAnchor.constraint(equalTo: sv.topAnchor),
                    new.bottomAnchor.constraint(equalTo: sv.bottomAnchor)
                ])
                new.isHidden = old.isHidden
                old.removeFromSuperview()
            }

            // Replace the property so callers see the fresh webView
            self.webView = new

            // Attempt to restore last URL (if known) or the site's start URL
            var restoreURL: URL? = nil
            if let lastStr = UserDefaults.standard.string(forKey: "Vaaka.LastURL.\(self.site.id)"), let lastURL = URL(string: lastStr), SiteManager.hostMatches(host: lastURL.host, siteHost: self.site.url.host) {
                restoreURL = lastURL
            }
            if restoreURL == nil { restoreURL = self.site.url }

            if let u = restoreURL {
                _ = self.webView.load(URLRequest(url: u))
            }

            // Start a short watchdog: if the new webview doesn't show content in `stuckTimeout`, open externally
            let stuckTimeout: TimeInterval = 8.0
            let finalWi = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                if self.webView.url == nil {
                    Logger.shared.debug("[DEBUG] content process recovery failed; opening externally for site \(self.site.name)")
                    NSWorkspace.shared.open(self.site.url)
                    NotificationCenter.default.post(name: Notification.Name("Vaaka.SiteTabDidFinishLoading"), object: self.site.id)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + stuckTimeout, execute: finalWi)
        }
    }

    // Active downloads for this tab: keep strong references to per-download handlers
    private var activeDownloadHandlers: [ObjectIdentifier: SiteDownloadHandler] = [:]

    func registerDownloadHandler(_ handler: SiteDownloadHandler, for download: WKDownload) {
        activeDownloadHandlers[ObjectIdentifier(download)] = handler
    }

    func unregisterDownloadHandler(for download: WKDownload) {
        activeDownloadHandlers.removeValue(forKey: ObjectIdentifier(download))
    }

    // Responsible for managing a single WKDownload's lifecycle on behalf of a SiteTab.
    class SiteDownloadHandler: NSObject, WKDownloadDelegate, Cancellable {
        private weak var siteTab: SiteTab?
        private weak var download: WKDownload?

        init(siteTab: SiteTab, download: WKDownload) {
            self.siteTab = siteTab
            self.download = download
            super.init()
        }

        deinit {
            // Clean up registration if still present
            if let d = download {
                siteTab?.unregisterDownloadHandler(for: d)
            }
        }



        var downloadId: String?

        @MainActor
        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
            // Default destination suggestion
            let fm = FileManager.default
            let downloadsURL = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
            var proposed = downloadsURL?.appendingPathComponent(suggestedFilename)

            // Ensure we don't clobber an existing file
            if let p = proposed {
                var candidate = p
                var idx = 1
                while fm.fileExists(atPath: candidate.path) {
                    let base = p.deletingPathExtension().lastPathComponent
                    let ext = p.pathExtension
                    let name = ext.isEmpty ? "\(base)-\(idx)" : "\(base)-\(idx).\(ext)"
                    candidate = p.deletingLastPathComponent().appendingPathComponent(name)
                    idx += 1
                }
                proposed = candidate
            }

            // Register an item in DownloadsManager so UI can show it immediately
            let id = UUID().uuidString
            self.downloadId = id
            DownloadsManager.shared.addExternalDownload(id: id, siteId: self.siteTab?.site.id ?? "", sourceURL: response.url, suggestedFilename: suggestedFilename, destination: proposed, taskIdentifier: nil)
            DownloadsManager.shared.registerCancellable(id: id, self)

            // If there is a key window, present a save panel and await user's destination choice
            if let win = NSApp.keyWindow {
                return await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = proposed?.lastPathComponent ?? suggestedFilename
                    panel.canCreateDirectories = true
                    panel.beginSheetModal(for: win) { resp in
                        if resp == .OK, let dest = panel.url {
                            DownloadsManager.shared.setDestination(id: id, destination: dest)
                            cont.resume(returning: dest)
                        } else {
                            cont.resume(returning: nil)
                        }
                    }
                }
            }

            return proposed
        }
        func downloadDidFinish(_ download: WKDownload) {
            DispatchQueue.main.async {
                Logger.shared.debug("[DEBUG] Download finished for site: \(self.siteTab?.site.name ?? "<unknown>")")
                // If we know the destination from the decideDestination step, reveal it.
                if let id = self.downloadId, let item = DownloadsManager.shared.allItems().first(where: { $0.id == id }), let dest = item.destinationURL {
                    NSWorkspace.shared.activateFileViewerSelecting([dest])
                } else if let fm = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                    NSWorkspace.shared.activateFileViewerSelecting([fm])
                }
                if let d = self.download {
                    self.siteTab?.unregisterDownloadHandler(for: d)
                }
                // Mark complete in manager if we previously registered an id
                if let id = self.downloadId {
                    DownloadsManager.shared.complete(id: id, destination: nil)
                    DownloadsManager.shared.unregisterCancellable(id: id)
                }
            }
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            DispatchQueue.main.async {
                Logger.shared.log("[ERROR] Download failed for site: \(self.siteTab?.site.name ?? "<unknown>") error=\(error)")
                // Inform user with an alert
                let alert = NSAlert()
                alert.messageText = "Download failed"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "OK")
                if let win = NSApp.keyWindow {
                    alert.beginSheetModal(for: win, completionHandler: nil)
                } else {
                    alert.runModal()
                }
                if let d = self.download {
                    self.siteTab?.unregisterDownloadHandler(for: d)
                }
                if let id = self.downloadId {
                    DownloadsManager.shared.fail(id: id, error: error)
                    DownloadsManager.shared.unregisterCancellable(id: id)
                }
            }
        }



        func download(_ download: WKDownload, didWriteData totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            guard let id = self.downloadId else { return }
            let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.0
            DownloadsManager.shared.updateProgress(id: id, progress: progress)
        }

        func cancelDownload() {
            download?.cancel()
        }
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

    // MARK: - Dynamic favicon refresh (e.g., Google Calendar daily icon changes)
    private func startFaviconRefreshIfNeeded() {
        // Determine the effective URL to check (prefer current webView URL)
        let effectiveURL = webView.url ?? site.url
        guard DynamicFaviconManager.shared.shouldRefreshFavicon(for: effectiveURL), let interval = DynamicFaviconManager.shared.refreshInterval(for: effectiveURL) else {
            return
        }
        // Avoid starting multiple timers
        if faviconRefreshTimer != nil { return }

        // Fire immediately with a scheduled reschedule for the next interval (midnight-friendly)
        refreshDynamicFavicon()

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + interval, leeway: .seconds(30))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.refreshDynamicFavicon()
            // Cancel and reschedule to recompute next interval (handles DST and calendar edges)
            self.stopFaviconRefresh()
            self.startFaviconRefreshIfNeeded()
        }
        faviconRefreshTimer = timer
        timer.resume()
    }

    private func refreshDynamicFavicon() {
        // Avoid refreshing while navigation is in progress
        guard !webView.isLoading else { return }

        FaviconFetcher.shared.captureLiveFavicon(from: webView) { [weak self] image in
            guard let self = self, let image = image else { return }

            // Convert to PNG and compare to existing on-disk image to avoid unnecessary writes/notifications
            guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let data = rep.representation(using: .png, properties: [:]) else {
                // Still notify UI with the captured image
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("Vaaka.FaviconDidUpdate"), object: self.site.id, userInfo: ["image": image])
                }
                return
            }

            let targetURL = FaviconFetcher.shared.faviconsDir.appendingPathComponent("\(self.site.id).png")
            if let existing = try? Data(contentsOf: targetURL), existing == data {
                // No change — still notify so views can pick it up if needed
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("Vaaka.FaviconDidUpdate"), object: self.site.id, userInfo: ["image": image])
                }
                return
            }

            // Save and notify (saveImage will post .FaviconSaved too)
            if let _ = FaviconFetcher.shared.saveImage(image, forSiteID: self.site.id) {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("Vaaka.FaviconDidUpdate"), object: self.site.id, userInfo: ["image": image])
                }
            } else {
                // If save failed, still notify UI with the in-memory image
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Notification.Name("Vaaka.FaviconDidUpdate"), object: self.site.id, userInfo: ["image": image])
                }
            }
        }
    }

    private func stopFaviconRefresh() {
        faviconRefreshTimer?.cancel()
        faviconRefreshTimer = nil
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



