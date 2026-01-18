import AppKit
import WebKit

class BrowserWindowController: NSWindowController {
    // UI – vertical tab rail on the left + content on the right
    private let railContainer: NSVisualEffectView = NSVisualEffectView()
    private let railScrollView: NSScrollView = NSScrollView()
    private let railStackView: NSStackView = NSStackView()

    private let contentContainer: NSView = NSView()

    // Constants
    private let railWidth: CGFloat = 52.0 // within 44–56pt range

    // Track created webviews attached to the content container
    private var webViewsAttached: Set<String> = [] // site.id values

    // Downloads UI
    private let downloadsBar = DownloadsBarView()
    private var downloadsBarHeightConstraint: NSLayoutConstraint?

    // Event monitor for keyboard shortcuts
    private var keyMonitor: Any?
    // Prevent accidental double-toggle of the Tab Overview from duplicate key events
    private var lastTabOverviewToggle: Date?

    convenience init() {
        let rect = NSRect(x: 100, y: 100, width: 1200, height: 800)
        let style: NSWindow.StyleMask = [.titled, .closable, .resizable, .miniaturizable]
        let window = NSWindow(contentRect: rect, styleMask: style, backing: .buffered, defer: false)
        window.title = "Vaaka"
        // Enable custom title bar coloring
        window.titlebarAppearsTransparent = false
        self.init(window: window)
    }

    override init(window: NSWindow?) {
        super.init(window: window)
        setupUI()

        // Observe SiteTabManager for tab list / active changes
        NotificationCenter.default.addObserver(self, selector: #selector(tabsChanged), name: .TabsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(activeTabChanged), name: .ActiveTabChanged, object: nil)

        // Observe loading notifications for showing spinner states
        NotificationCenter.default.addObserver(self, selector: #selector(siteDidStartLoading(_:)), name: Notification.Name("Vaaka.SiteTabDidStartLoading"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(siteDidFinishLoading(_:)), name: Notification.Name("Vaaka.SiteTabDidFinishLoading"), object: nil)
        // Present user-friendly failures when navigation fails
        NotificationCenter.default.addObserver(self, selector: #selector(siteDidFailLoading(_:)), name: .SiteTabDidFailLoading, object: nil)

        // Also react to site list changes
        NotificationCenter.default.addObserver(self, selector: #selector(sitesChanged), name: .SitesChanged, object: nil)

        // Observe appearance changes
        NotificationCenter.default.addObserver(self, selector: #selector(appearanceChanged), name: NSNotification.Name("Vaaka.AppearanceChanged"), object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(faviconSaved(_:)), name: .FaviconSaved, object: nil)
        // Window delegate
        self.window?.delegate = self

        // Observe image-contextmenu messages from webviews to show native Save menu
        NotificationCenter.default.addObserver(self, selector: #selector(imageContextMenuRequested(_:)), name: Notification.Name("Vaaka.ContextMenuImage"), object: nil)

        // Observe downloads model updates
        NotificationCenter.default.addObserver(self, selector: #selector(downloadsChanged(_:)), name: Notification.Name("Vaaka.DownloadsChanged"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(downloadUpdated(_:)), name: Notification.Name("Vaaka.DownloadUpdated"), object: nil)

        // Keyboard shortcuts
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] evt in
            return self?.handleKeyEvent(evt) ?? evt
        }

        // Minimum window size
        if let w = self.window {
            w.minSize = NSSize(width: 640, height: 400)
            w.contentMinSize = NSSize(width: 640, height: 400)
        }

        // Apply appearance preference
        applyAppearance()

        // Initial render
        rebuildRailButtons()
        attachAllWebViewsIfNeeded()
        activeTabChanged()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let km = keyMonitor { NSEvent.removeMonitor(km) }
    }

    private func setupUI() {
        guard let content = window?.contentView else { return }
        content.subviews.forEach { $0.removeFromSuperview() }

        // Rail container with native sidebar appearance
        railContainer.translatesAutoresizingMaskIntoConstraints = false
        railContainer.material = .sidebar
        railContainer.blendingMode = .behindWindow
        railContainer.state = .active
        
        // Scroll view for rail
        railScrollView.translatesAutoresizingMaskIntoConstraints = false
        railScrollView.hasVerticalScroller = true
        railScrollView.drawsBackground = false
        railScrollView.borderType = .noBorder
        railScrollView.wantsLayer = true
        railScrollView.layer?.backgroundColor = NSColor.clear.cgColor

        // Stack view vertical
        railStackView.orientation = .vertical
        railStackView.alignment = .centerX
        railStackView.spacing = 8
        railStackView.edgeInsets = NSEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        railStackView.translatesAutoresizingMaskIntoConstraints = false
        railStackView.wantsLayer = true
        railStackView.layer?.backgroundColor = NSColor.clear.cgColor

        // Put stack into docView for scroll
        let docView = NSView()
        docView.translatesAutoresizingMaskIntoConstraints = false
        docView.wantsLayer = true
        docView.layer?.backgroundColor = NSColor.clear.cgColor
        docView.addSubview(railStackView)
        railScrollView.documentView = docView

        // Content container
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        content.addSubview(railContainer)
        content.addSubview(contentContainer)
        content.addSubview(downloadsBar)
        railContainer.addSubview(railScrollView)

        NSLayoutConstraint.activate([
            // Left rail fixed width
            railContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            railContainer.topAnchor.constraint(equalTo: content.topAnchor),
            railContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            railContainer.widthAnchor.constraint(equalToConstant: railWidth),

            railScrollView.leadingAnchor.constraint(equalTo: railContainer.leadingAnchor),
            railScrollView.trailingAnchor.constraint(equalTo: railContainer.trailingAnchor),
            railScrollView.topAnchor.constraint(equalTo: railContainer.topAnchor),
            railScrollView.bottomAnchor.constraint(equalTo: railContainer.bottomAnchor),

            // Content fills remaining space
            contentContainer.leadingAnchor.constraint(equalTo: railContainer.trailingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: content.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            // Downloads bar pinned to bottom and initially hidden (height 0)
            downloadsBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            downloadsBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            downloadsBar.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            // constraints for docView and stack
            railStackView.leadingAnchor.constraint(equalTo: docView.leadingAnchor),
            railStackView.trailingAnchor.constraint(equalTo: docView.trailingAnchor),
            railStackView.topAnchor.constraint(equalTo: docView.topAnchor),
            railStackView.bottomAnchor.constraint(lessThanOrEqualTo: docView.bottomAnchor)
        ])

        // Clip docView to scroll content width
        let clip = railScrollView.contentView
        NSLayoutConstraint.activate([
            docView.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            docView.topAnchor.constraint(equalTo: clip.topAnchor),
            docView.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
            docView.widthAnchor.constraint(equalTo: railScrollView.widthAnchor)
        ])

        // Downloads bar initial height constraint (hidden)
        downloadsBarHeightConstraint = downloadsBar.heightAnchor.constraint(equalToConstant: 0)
        downloadsBarHeightConstraint?.isActive = true

        // Initial empty state view if no sites
        updateEmptyStateIfNeeded()

        // Apply initial downloads state
        updateDownloadsBar(animated: false)
    }

    // MARK: - UI updates
    @objc private func sitesChanged() {
        rebuildRailButtons()
        attachAllWebViewsIfNeeded()

        // Remove any orphaned WKWebViews whose site ids are no longer in the sites list
        let currentSiteIds = Set(SiteTabManager.shared.tabs.map { $0.site.id })
        var removed: [String] = []
        for v in contentContainer.subviews {
            if let wv = v as? WKWebView, let id = wv.identifier?.rawValue {
                if !currentSiteIds.contains(id) {
                    removed.append(id)
                    wv.removeFromSuperview()
                    webViewsAttached.remove(id)
                }
            }
        }

        // If last active site got removed, SiteTabManager will have set activeIndex appropriately; update UI.
        activeTabChanged()
    }

    @objc private func tabsChanged() {
        rebuildRailButtons()
    }

    @objc private func activeTabChanged() {
        // Update visual active states and visible webview
        DispatchQueue.main.async {
            let idx = SiteTabManager.shared.activeIndex
            self.updateRailSelection(activeIndex: idx)
            self.setActiveWebViewVisibility(index: idx)
            self.updateWindowTitleForActiveTab()
            // Do not auto-clear unread counts when switching active tabs so unread badges remain visible
        }
    }

    private func rebuildRailButtons() {
        railStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let tabs = SiteTabManager.shared.tabs
        for (index, tab) in tabs.enumerated() {
            let item = RailItemView(site: tab.site, index: index, actionTarget: self)
            railStackView.addArrangedSubview(item)
            // height to make icons comfortably touch-target
            item.heightAnchor.constraint(equalToConstant: 44).isActive = true
            item.widthAnchor.constraint(equalToConstant: railWidth).isActive = true
        }
        
        // Add spacer to push overview button to bottom
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        railStackView.addArrangedSubview(spacer)
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        
        // Add Tab Overview button at bottom
        let overviewButton = TabOverviewButton(actionTarget: self)
        railStackView.addArrangedSubview(overviewButton)
        overviewButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        overviewButton.widthAnchor.constraint(equalToConstant: railWidth).isActive = true
    }

    private func updateRailSelection(activeIndex: Int) {
        for case let item as RailItemView in railStackView.arrangedSubviews {
            item.updateActiveState(isActive: item.index == activeIndex)
        }
    }

    private func attachAllWebViewsIfNeeded() {
        let tabs = SiteTabManager.shared.tabs
        for tab in tabs {
            if webViewsAttached.contains(tab.site.id) { continue }

            // Attach once
            let webView = tab.webView
            webView.translatesAutoresizingMaskIntoConstraints = false
            webView.identifier = NSUserInterfaceItemIdentifier(tab.site.id)
            contentContainer.addSubview(webView)
            NSLayoutConstraint.activate([
                webView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
                webView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                webView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
            ])
            webView.isHidden = true
            webViewsAttached.insert(tab.site.id)

            // No themeColor observation; using favicon-derived color

            // Start navigation only after the webview is attached to the view hierarchy
            tab.loadStartURLIfNeeded()
        }
    }

    private func setActiveWebViewVisibility(index: Int) {
        let tabs = SiteTabManager.shared.tabs
        for (i, tab) in tabs.enumerated() {
            let willHide = (i != index)

            tab.webView.isHidden = willHide
        }
    }

    private func updateWindowTitleForActiveTab() {
        guard let win = self.window else { return }
        if let tab = SiteTabManager.shared.activeTab() {
            let t = tab.webView.title
            if let title = t, !title.isEmpty {
                win.title = title
            } else {
                // Fallback to site name when no page title available
                win.title = tab.site.name
            }
        } else {
            win.title = "Vaaka"
        }
    }

    @objc private func appearanceChanged() {
        applyAppearance()
    }

    private func applyAppearance() {
        guard let win = self.window else { return }
        win.appearance = AppearanceManager.shared.effectiveAppearance
        win.backgroundColor = .clear
        
        // Sidebar uses native material
        railContainer.material = .sidebar
        railContainer.layer?.backgroundColor = nil
        
        // Update content container background for current appearance
        let effectiveAppearance = win.effectiveAppearance
        effectiveAppearance.performAsCurrentDrawingAppearance {
            contentContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }

    private func updateEmptyStateIfNeeded() {
        // Remove any previous empty state view
        if SiteManager.shared.sites.isEmpty {
            // show an empty state inside content container
            contentContainer.subviews.forEach { $0.isHidden = true }
            if contentContainer.subviews.first(where: { $0.identifier?.rawValue == "EmptyStateView" }) == nil {
                let v = EmptyStateView(frame: .zero)
                v.translatesAutoresizingMaskIntoConstraints = false
                v.identifier = NSUserInterfaceItemIdentifier("EmptyStateView")
                contentContainer.addSubview(v)
                NSLayoutConstraint.activate([
                    v.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
                    v.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor),
                    v.widthAnchor.constraint(equalToConstant: 320)
                ])
                v.openSettingsAction = { [weak self] in
                    self?.openPreferences()
                }
            }
        } else {
            // ensure content container subviews (including empty state) are visible state
            contentContainer.subviews.forEach { if $0.tag != 0xE11 { $0.isHidden = false } }
            if let empty = contentContainer.viewWithTag(0xE11) { empty.removeFromSuperview() }
        }
    }

    // MARK: - Loading state notifications
    @objc private func siteDidStartLoading(_ note: Notification) {
        guard let id = note.object as? String else { return }
        for case let item as RailItemView in railStackView.arrangedSubviews where item.site.id == id {
            item.setLoading(true)
        }
    }

    // MARK: - Downloads
    @objc private func downloadsChanged(_ note: Notification) {
        updateDownloadsBar(animated: true)
    }

    @objc private func downloadUpdated(_ note: Notification) {
        updateDownloadsBar(animated: false)
    }

    @objc private func faviconSaved(_ note: Notification) {
        // Rebuild rail to pick up new favicon resources (per-item handlers also update immediately)
        DispatchQueue.main.async {
            self.rebuildRailButtons()
        }
    }

    private var hideDownloadsWorkItem: DispatchWorkItem?

    private func updateDownloadsBar(animated: Bool) {
        let items = DownloadsManager.shared.allItems()
        let visible = !items.isEmpty

        // Update content of bar
        downloadsBar.apply(items: items)

        // Animate height
        let target: CGFloat = visible ? 84 : 0
        downloadsBarHeightConstraint?.constant = target
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.window?.contentView?.layoutSubtreeIfNeeded()
            }, completionHandler: nil)
        } else {
            self.window?.contentView?.layoutSubtreeIfNeeded()
        }

        // Auto-hide when no in-progress items after a delay
        hideDownloadsWorkItem?.cancel()
        if !visible { return }
        // If there are no in-progress items, schedule a hide after 5s
        if items.first(where: { $0.status == .inProgress }) == nil {
            let wi = DispatchWorkItem { [weak self] in
                self?.updateDownloadsBar(animated: true)
            }
            hideDownloadsWorkItem = wi
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: wi)
        }
    }

    @objc private func siteDidFinishLoading(_ note: Notification) {
        guard let id = note.object as? String else { return }
        for case let item as RailItemView in railStackView.arrangedSubviews where item.site.id == id {
            item.setLoading(false)
        }
        // If the finished site is the active tab, update window title
        if let active = SiteTabManager.shared.activeTab(), active.site.id == id {
            updateWindowTitleForActiveTab()
        }
    }

    @objc private func siteDidFailLoading(_ note: Notification) {
        guard let info = note.userInfo,
              let siteId = info["siteId"] as? String,
              let urlStr = info["url"] as? String,
              let errDesc = info["errorDescription"] as? String else { return }

        // Find which tab this is
        if let idx = SiteTabManager.shared.tabs.firstIndex(where: { $0.site.id == siteId }) {
            // Instead of a blocking modal, show an in-tab error page with Retry / Open in Browser / Dismiss
            DispatchQueue.main.async {
                SiteTabManager.shared.setActiveIndex(idx)
                let tab = SiteTabManager.shared.tabs[idx]
                tab.webView.isHidden = false
                let site = tab.site
                // Determine a full URL to open and a short hostname to display.
                let fullURLString: String
                let displayHost: String
                if urlStr.hasPrefix("about:") || urlStr == "<no-url>" || urlStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    fullURLString = site.url.absoluteString
                    displayHost = site.url.host ?? site.url.absoluteString
                } else if let parsed = URL(string: urlStr), let host = parsed.host {
                    fullURLString = urlStr
                    displayHost = host
                } else {
                    // Fallback: show raw string but prefer site host if available
                    fullURLString = urlStr
                    displayHost = site.url.host ?? site.url.absoluteString
                }
                tab.showErrorPage(errorDescription: errDesc, failedURL: fullURLString, displayHost: displayHost)
            }
        } else {
            // No tab found for this site — fall back to opening externally so the user can still view the content
            DispatchQueue.main.async {
                if let u = URL(string: urlStr) { NSWorkspace.shared.open(u) }
            }
        }
    }

    

    // MARK: - Keyboard handling
    private func handleKeyEvent(_ evt: NSEvent) -> NSEvent? {
        // Cmd+T for Tab Overview — toggle overview when pressed
        if evt.modifierFlags.contains(.command) && evt.charactersIgnoringModifiers == "t" {
            // Route through the same toggle entry point used by the toolbar/menu so all callers share the debounce logic.
            self.tabOverviewClicked(nil)
            return nil
        }
        
        // Ctrl+Tab / Ctrl+Shift+Tab
        if evt.modifierFlags.contains(.control) && evt.keyCode == 48 { // tab keycode
            if evt.modifierFlags.contains(.shift) {
                // previous
                let idx = SiteTabManager.shared.activeIndex
                let prev = (idx - 1 + SiteTabManager.shared.tabs.count) % max(1, SiteTabManager.shared.tabs.count)
                SiteTabManager.shared.setActiveIndex(prev)
            } else {
                // next
                let idx = SiteTabManager.shared.activeIndex
                let next = (idx + 1) % max(1, SiteTabManager.shared.tabs.count)
                SiteTabManager.shared.setActiveIndex(next)
            }
            return nil // consume
        }

        // Cmd+1..Cmd+9
        if evt.modifierFlags.contains(.command), let chars = evt.charactersIgnoringModifiers, let first = chars.first, let digit = Int(String(first)), (1...9).contains(digit) {
            let idx = digit - 1
            if idx < SiteTabManager.shared.tabs.count {
                SiteTabManager.shared.setActiveIndex(idx)
                return nil
            }
        }
        return evt
    }

    // MARK: - Actions
    fileprivate func railItemClicked(_ index: Int) {
        SiteTabManager.shared.setActiveIndex(index)
    }
    
    private let tabOverviewDebounceInterval: TimeInterval = 0.35

    @objc func tabOverviewClicked(_ sender: Any? = nil) {
        // Debounce duplicate calls from different input sources (keyboard/menu/button)
        let now = Date()
        if let last = self.lastTabOverviewToggle, now.timeIntervalSince(last) < tabOverviewDebounceInterval {
            return
        }
        self.lastTabOverviewToggle = now

        if tabOverviewView != nil {
            hideTabOverview()
        } else {
            showTabOverview()
        }
    }
    
    private var tabOverviewView: TabOverviewView?
    
    private func showTabOverview() {
        guard let window = self.window, let contentView = window.contentView else { return }
        
        // Don't show if already visible
        if tabOverviewView != nil { return }
        
        let overviewView = TabOverviewView(tabs: SiteTabManager.shared.tabs, activeIndex: SiteTabManager.shared.activeIndex) { [weak self] selectedIndex in
            self?.hideTabOverview()
            SiteTabManager.shared.setActiveIndex(selectedIndex)
        } dismissHandler: { [weak self] in
            self?.hideTabOverview()
        }
        
        overviewView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(overviewView, positioned: .above, relativeTo: nil)
        
        NSLayoutConstraint.activate([
            overviewView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            overviewView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            overviewView.topAnchor.constraint(equalTo: contentView.topAnchor),
            overviewView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        
        self.tabOverviewView = overviewView
        
        // Force layout to complete before scrolling
        overviewView.layoutSubtreeIfNeeded()
        
        // Deferred pass: re-run centering so any late layout changes are handled
        DispatchQueue.main.async { [weak overviewView] in
            guard let overviewView = overviewView else { return }
            overviewView.centerContentVertically(retryAttempt: 1)
        }
        
        overviewView.appear()
    }
    
    private func hideTabOverview() {
        tabOverviewView?.disappear { [weak self] in
            self?.tabOverviewView?.removeFromSuperview()
            self?.tabOverviewView = nil
        }
    }

    fileprivate func openPreferences() {
        let prefs = PreferencesWindowController()
        prefs.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Context menu helpers
    fileprivate func showContextMenu(for site: Site, at pointInWindow: NSPoint) {
        let menu = NSMenu(title: "Site")
        menu.addItem(withTitle: "Reload Site", action: #selector(reloadSite(_:)), keyEquivalent: "").representedObject = site
        menu.addItem(withTitle: "Open in Default Browser", action: #selector(openInBrowser(_:)), keyEquivalent: "").representedObject = site
        // Offer explicit mark-as-read action when there are unread notifications
        if UnreadManager.shared.count(for: site.id) > 0 {
            let mark = NSMenuItem(title: "Mark Site as Read", action: #selector(markSiteAsRead(_:)), keyEquivalent: "")
            mark.representedObject = site
            menu.addItem(mark)
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Site Settings…", action: #selector(openSiteSettings(_:)), keyEquivalent: "").representedObject = site

        guard let event = NSApp.currentEvent, let win = self.window, let content = win.contentView else {
            // Unable to show context menu safely
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: content)
    }

    @objc private func markSiteAsRead(_ sender: NSMenuItem) {
        guard let site = sender.representedObject as? Site else { return }
        UnreadManager.shared.clear(for: site.id)
    }

    @objc private func reloadSite(_ sender: NSMenuItem) {
        guard let site = sender.representedObject as? Site else { return }
        if let idx = SiteTabManager.shared.tabs.firstIndex(where: { $0.site.id == site.id }) {
            SiteTabManager.shared.tabs[idx].webView.reload()
        }
    }

    @objc private func openInBrowser(_ sender: NSMenuItem) {
        guard let site = sender.representedObject as? Site else { return }
        NSWorkspace.shared.open(site.url)
    }

    @objc private func openSiteSettings(_ sender: NSMenuItem) {
        openPreferences()
    }

    // Image context menu support
    @objc private func imageContextMenuRequested(_ note: Notification) {
        guard let info = note.userInfo, let siteId = info["siteId"] as? String, let src = info["src"] as? String else { return }
        // Show a small menu at the current mouse location offering Save / Copy URL
        guard let win = self.window, let content = win.contentView else { return }
        let menu = NSMenu(title: "Image")
        let save = NSMenuItem(title: "Save Image As…", action: #selector(saveImageAs(_:)), keyEquivalent: "")
        save.representedObject = ["siteId": siteId, "src": src]
        menu.addItem(save)
        let copy = NSMenuItem(title: "Copy Image URL", action: #selector(copyImageURL(_:)), keyEquivalent: "")
        copy.representedObject = src
        menu.addItem(copy)
        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: content)
        } else {
            // fallback: center of window
            let loc = NSPoint(x: win.frame.midX, y: win.frame.midY)
            NSMenu.popUpContextMenu(menu, with: NSEvent.mouseEvent(with: .rightMouseDown, location: loc, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: win.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!, for: content)
        }
    }

    @objc private func copyImageURL(_ sender: NSMenuItem) {
        guard let src = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(src, forType: .string)
    }

    @objc private func saveImageAs(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String], let src = info["src"], let siteId = info["siteId"] else { return }

        // Determine suggested filename
        var suggested = URL(string: src)?.lastPathComponent ?? "image"
        if suggested.isEmpty { suggested = "image" }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggested
        panel.canCreateDirectories = true
        guard let win = self.window else { return }
        panel.beginSheetModal(for: win) { resp in
            if resp == .OK, let dest = panel.url {
                // Kick off a direct download using URLSession so it's robust even when the WebView doesn't create a WKDownload
                self.performImageDownload(from: src, to: dest, siteId: siteId)
            }
        }
    }

    private func performImageDownload(from src: String, to destination: URL, siteId: String) {
        // Handle data: URLs specially
        if src.hasPrefix("data:") {
            if let comma = src.firstIndex(of: ",") {
                let meta = String(src[src.index(src.startIndex, offsetBy: 5)..<comma])
                let isBase64 = meta.contains("base64")
                let payload = String(src[src.index(after: comma)...])
                if let data = isBase64 ? Data(base64Encoded: payload) : payload.data(using: .utf8) {
                    do {
                        try data.write(to: destination)
                        NSWorkspace.shared.activateFileViewerSelecting([destination])
                    } catch {
                        let alert = NSAlert(error: error)
                        if let win = self.window { alert.beginSheetModal(for: win, completionHandler: nil) } else { alert.runModal() }
                    }
                }
            }
            return
        }

        guard let url = URL(string: src) else { return }
        // Use DownloadsManager to start the external download (tracks progress / reveal / cancel)
        DownloadsManager.shared.startExternalDownload(from: url, suggestedFilename: destination.lastPathComponent, destination: destination, siteId: siteId)
    }

    // MARK: - Helpers
    private func ensureWebViewsAndSetActive(index: Int) {
        attachAllWebViewsIfNeeded()
        setActiveWebViewVisibility(index: index)
    }

    // MARK: - Empty state view
    private final class EmptyStateView: NSView {
        var openSettingsAction: (() -> Void)?
        private let messageLabel = NSTextField(labelWithString: "No sites configured\nAdd a site in Settings to begin.")
        private let button = NSButton(title: "Open Settings", target: nil, action: nil)

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setup()
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        private func setup() {
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
            messageLabel.alignment = .center
            messageLabel.font = NSFont.systemFont(ofSize: 14)
            messageLabel.translatesAutoresizingMaskIntoConstraints = false
            // Accessibility
            messageLabel.setAccessibilityLabel(messageLabel.stringValue)
            messageLabel.setAccessibilityIdentifier("EmptyState.Message")

            button.bezelStyle = .rounded
            button.target = self
            button.action = #selector(openPressed)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setAccessibilityLabel("Open Settings")
            button.setAccessibilityIdentifier("EmptyState.OpenSettings")
            button.setAccessibilityRole(.button)

            addSubview(messageLabel)
            addSubview(button)
            // Make this view an accessibility group and expose children
            self.setAccessibilityElement(false)

            NSLayoutConstraint.activate([
                messageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
                messageLabel.topAnchor.constraint(equalTo: topAnchor),
                button.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 12),
                button.centerXAnchor.constraint(equalTo: centerXAnchor),
                button.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
        @objc private func openPressed() { openSettingsAction?() }
    }

    // MARK: - Site item view
    private final class RailItemView: NSView {
        let site: Site
        let index: Int
        private let imageView = NSImageView()
        private let indicator = NSView()
        private let spinner = NSProgressIndicator()
        private let badgeContainer = NSView()
        private let badgeLabel = NSTextField(labelWithString: "")
        private var tracking: NSTrackingArea?
        private weak var actionTarget: BrowserWindowController?

        init(site: Site, index: Int, actionTarget: BrowserWindowController) {
            self.site = site
            self.index = index
            self.actionTarget = actionTarget
            super.init(frame: .zero)
            setup()
        }

        func debugInfo() -> String {
            let hasImage = (imageView.image != nil)
            let size = imageView.image?.size.debugDescription ?? "nil"
            return "hasImage=\(hasImage) hidden=\(imageView.isHidden) alpha=\(imageView.alphaValue) size=\(size)"
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        private var reloadRetries = 0
        // Track the last known image presence to detect unexpected transitions
        private var lastKnownHasImage = false

        // Centralized image & visibility mutators
        private func applyImage(_ img: NSImage?, reason: String) {
            imageView.image = img
            lastKnownHasImage = (img != nil)
        }
        private func setImageHidden(_ hidden: Bool, reason: String) {
            imageView.isHidden = hidden
        }
        private func setImageAlpha(_ alpha: CGFloat, reason: String) {
            imageView.alphaValue = alpha
        }

        private func setup() {
            translatesAutoresizingMaskIntoConstraints = false
            wantsLayer = true
            layer?.cornerRadius = 6

            indicator.wantsLayer = true
            indicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            indicator.translatesAutoresizingMaskIntoConstraints = false
            indicator.isHidden = true

            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.setAccessibilityHidden(true)

            // Badge setup (hidden by default)
            badgeContainer.translatesAutoresizingMaskIntoConstraints = false
            badgeContainer.wantsLayer = true
            badgeContainer.isHidden = true
            badgeContainer.layer?.backgroundColor = NSColor.systemRed.cgColor
            badgeContainer.layer?.cornerRadius = 8
            badgeContainer.setAccessibilityHidden(true)

            badgeLabel.translatesAutoresizingMaskIntoConstraints = false
            badgeLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
            badgeLabel.textColor = .white
            badgeLabel.alignment = .center
            badgeLabel.setAccessibilityHidden(true)
            badgeContainer.addSubview(badgeLabel)
            NSLayoutConstraint.activate([
                badgeLabel.leadingAnchor.constraint(equalTo: badgeContainer.leadingAnchor, constant: 4),
                badgeLabel.trailingAnchor.constraint(equalTo: badgeContainer.trailingAnchor, constant: -4),
                badgeLabel.topAnchor.constraint(equalTo: badgeContainer.topAnchor, constant: 1),
                badgeLabel.bottomAnchor.constraint(equalTo: badgeContainer.bottomAnchor, constant: -1)
            ])

            spinner.style = .spinning

            // Accessibility for tab item
            self.setAccessibilityElement(true)
            self.setAccessibilityRole(.button)
            self.setAccessibilityLabel("\(site.name) tab")
            self.setAccessibilityIdentifier("RailItem.\(site.id)")
            spinner.controlSize = .small
            spinner.translatesAutoresizingMaskIntoConstraints = false
            spinner.isDisplayedWhenStopped = false
            spinner.isHidden = true
            spinner.alphaValue = 0.0
            imageView.alphaValue = 1.0

            addSubview(indicator)
            addSubview(imageView)
            addSubview(spinner)
            addSubview(badgeContainer)

            NSLayoutConstraint.activate([
                indicator.leadingAnchor.constraint(equalTo: leadingAnchor),
                indicator.widthAnchor.constraint(equalToConstant: 3),
                indicator.topAnchor.constraint(equalTo: topAnchor, constant: 6),
                indicator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),

                imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 24),
                imageView.heightAnchor.constraint(equalToConstant: 24),

                // Place spinner in the exact center of the imageView so it replaces the icon visually
                spinner.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
                spinner.centerYAnchor.constraint(equalTo: imageView.centerYAnchor)
            ])

            // Position badge at top-right of the favicon
            NSLayoutConstraint.activate([
                badgeContainer.heightAnchor.constraint(equalToConstant: 16),
                badgeContainer.centerYAnchor.constraint(equalTo: imageView.topAnchor, constant: 2),
                badgeContainer.centerXAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -2)
            ])

            // Accessibility: make this rail item an accessibility element (acts like a button)
            self.setAccessibilityElement(true)
            self.setAccessibilityRole(.button)
            self.setAccessibilityLabel(site.name)

            // set tooltip
            self.toolTip = site.name

            // Use instance methods for image/visibility updates (no noisy prints)

            // Initial badge state
            self.updateBadge()
            NotificationCenter.default.addObserver(self, selector: #selector(unreadChanged(_:)), name: .UnreadChanged, object: nil)
            // Update overview/favicon when saved
            NotificationCenter.default.addObserver(self, selector: #selector(faviconSaved(_:)), name: .FaviconSaved, object: nil)

            // Listen for dynamic favicon updates specifically for this site
            NotificationCenter.default.addObserver(self, selector: #selector(faviconDidUpdate(_:)), name: Notification.Name("Vaaka.FaviconDidUpdate"), object: site.id)

            // Load favicon (SVG preferred, PNG allowed, generated fallback)
            if let name = site.favicon {
                // Try to load from disk, or fetch from web as fallback
                FaviconFetcher.shared.imageOrFetchFromWeb(forResource: name, url: site.url) { [weak self] img in
                    guard let self = self else { return }
                    if let img = img {
                        DispatchQueue.main.async {
                            self.applyImage(img, reason: "setup:loaded-resource:\(name)")
                        }
                    } else if let host = site.url.host {
                        // Fallback to generated mono icon
                        let mono = FaviconFetcher.shared.generateMonoIcon(for: host)
                        DispatchQueue.main.async {
                            self.applyImage(mono, reason: "setup:generated-mono")
                        }
                    }
                }
            } else if let host = site.url.host {
                let mono = FaviconFetcher.shared.generateMonoIcon(for: host)
                self.applyImage(mono, reason: "setup:generated-mono")
            }
            // Ensure image view is visible and properly configured even if there was no icon
            self.setImageHidden(false, reason: "setup:ensure-visible")
            self.setImageAlpha(1.0, reason: "setup:ensure-alpha")
            if imageView.image == nil, let host = site.url.host {
                // Final safety: show a generated mono icon if nothing else is present
                self.applyImage(FaviconFetcher.shared.generateMonoIcon(for: host), reason: "setup:final-safety-mono-for-host:\(host)")
            }

            // Click handling
            let click = NSClickGestureRecognizer(target: self, action: #selector(clicked(_:)))
            addGestureRecognizer(click)
        }

        @objc private func unreadChanged(_ note: Notification) {
            guard let siteId = note.object as? String, siteId == site.id else { return }
            updateBadge()
        }

        @objc private func faviconSaved(_ note: Notification) {
            guard let info = note.userInfo as? [String: Any], let siteId = info["siteId"] as? String, siteId == site.id else { return }
            guard let fname = info["filename"] as? String else { return }
            if let img = FaviconFetcher.shared.image(forResource: fname) {
                DispatchQueue.main.async {
                    self.applyImage(img, reason: "faviconSaved:loaded:")
                    self.setImageHidden(false, reason: "faviconSaved:ensure-visible")
                    self.setImageAlpha(1.0, reason: "faviconSaved:set-alpha-1")
                }
            }
        }

        @objc private func faviconDidUpdate(_ note: Notification) {
            guard let image = note.userInfo?["image"] as? NSImage else { return }
            DispatchQueue.main.async {
                self.applyImage(image, reason: "dynamic-favicon-update")
                self.setImageHidden(false, reason: "dynamic-favicon-update")
                self.setImageAlpha(1.0, reason: "dynamic-favicon-update")
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        private func updateBadge() {
            let count = UnreadManager.shared.count(for: site.id)
            if count > 0 {
                badgeLabel.stringValue = count > 9 ? "9+" : "\(count)"
                badgeContainer.isHidden = false
            } else {
                badgeContainer.isHidden = true
                badgeLabel.stringValue = ""
            }
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let t = tracking { removeTrackingArea(t) }
            tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
            if let t = tracking { addTrackingArea(t) }
        }

        override func mouseEntered(with event: NSEvent) {
            layer?.backgroundColor = NSColor.selectedControlColor.withAlphaComponent(0.06).cgColor
        }

        override func mouseExited(with event: NSEvent) {
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        func updateActiveState(isActive: Bool) {
            indicator.isHidden = !isActive
            if isActive {
                layer?.backgroundColor = NSColor.selectedControlColor.withAlphaComponent(0.12).cgColor
            } else {
                layer?.backgroundColor = NSColor.clear.cgColor
            }
        }

        private var loadingTimeoutWorkItem: DispatchWorkItem?

        func setLoading(_ l: Bool) {
            // Cancel any existing timeout when state changes
            loadingTimeoutWorkItem?.cancel()
            loadingTimeoutWorkItem = nil

            // Announce to assistive tech
            if l {
                NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [NSAccessibility.NotificationUserInfoKey.announcement: "Loading \(site.name)", NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.medium])

                spinner.isHidden = false
                spinner.alphaValue = 0.0
                spinner.startAnimation(nil)
                // Bring up spinner without hiding the favicon to avoid flicker between navigations
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.18
                    spinner.animator().alphaValue = 1.0
                    // keep imageView alpha unchanged so cached favicon remains visible while loading
                }, completionHandler: nil)

                // Schedule a fallback in case loading stalls: show a mono icon and stop spinner after a short timeout
                let work = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    if self.spinner.isHidden == false {
                        // Only apply fallback if there's no image currently displayed (avoid overwriting cached favicon)
                        if self.imageView.image == nil, let host = self.site.url.host {
                            self.applyImage(FaviconFetcher.shared.generateMonoIcon(for: host), reason: "loadingTimeout:applied-fallback-mono-for:\(host)")
                            self.setImageHidden(false, reason: "loadingTimeout:ensure-visible")
                            self.setImageAlpha(1.0, reason: "loadingTimeout:set-alpha-1")
                            self.spinner.stopAnimation(nil)
                            self.spinner.isHidden = true
                        }
                    }
                }
                self.loadingTimeoutWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)

            } else {
                NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [NSAccessibility.NotificationUserInfoKey.announcement: "\(site.name) loaded", NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.low])

                // Ensure we have the most up-to-date favicon image (in case it changed while loading)
                var appliedImage: NSImage? = nil
                if let name = site.favicon, let img = FaviconFetcher.shared.image(forResource: name) {
                    appliedImage = img
                } else if self.imageView.image == nil, let host = site.url.host {
                    // Only fallback to mono icon if no image currently shown
                    appliedImage = FaviconFetcher.shared.generateMonoIcon(for: host)
                }

                if let img = appliedImage {
                    self.applyImage(img, reason: "setLoading:refresh-resource-or-fallback")
                }

                // If we applied a new image, ensure it is visible. Otherwise keep the currently visible favicon intact.
                if appliedImage != nil {
                    self.setImageHidden(false, reason: "setLoading:finish:ensure-visible")
                }
                // Fade spinner away and leave the favicon as-is (avoid re-fading favicon to prevent flicker)
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.18
                    spinner.animator().alphaValue = 0.0
                }, completionHandler: {
                    self.spinner.stopAnimation(nil)
                    self.spinner.isHidden = true

                    // Ensure any pending loading-timeout fallback is cancelled now that finish completed
                    self.loadingTimeoutWorkItem?.cancel()
                    self.loadingTimeoutWorkItem = nil

                    // If the image is nil after finishing animation, first apply an immediate fallback mono icon
                    if self.imageView.image == nil {
                        if let host = self.site.url.host {
                            self.applyImage(FaviconFetcher.shared.generateMonoIcon(for: host), reason: "setLoading:immediate-fallback-mono-for:\(host)")
                            self.setImageHidden(false, reason: "setLoading:immediate-fallback-ensure-visible")
                            self.setImageAlpha(1.0, reason: "setLoading:immediate-fallback-alpha-1")
                        }
                    }

                    // Force final visible state (defensive: ensure the icon is not left invisible due to interrupted animation)
                    self.setImageHidden(false, reason: "setLoading:finish:ensure-visible-final")
                    self.setImageAlpha(1.0, reason: "setLoading:finish:force-alpha-1")

                    // Also attempt a small number of retries with delay to account for file write races or transient failures
                    if self.imageView.image == nil, self.reloadRetries < 3 {
                        self.reloadRetries += 1
                        let attempt = self.reloadRetries
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            if let name = self.site.favicon, let img = FaviconFetcher.shared.image(forResource: name) {
                                self.applyImage(img, reason: "retry:loaded-resource:\(name):attempt:\(attempt)")
                                self.setImageHidden(false, reason: "retry:ensure-visible")
                                // no-op: suppress noisy retry logs
                                // Ensure final visible state after retry succeeds
                                self.setImageAlpha(1.0, reason: "retry:force-alpha-1")
                            } else {
                                // suppress noisy retry logs
                            }
                        }
                    } else {
                        self.reloadRetries = 0
                    }
                })
            }
        }

        @objc private func clicked(_ g: NSClickGestureRecognizer) {
            // Treat clicks as activation; right-click is handled via rightMouseDown
            actionTarget?.railItemClicked(index)
        }

        // Support VoiceOver / accessibility press for the tab
        override func accessibilityPerformPress() -> Bool {
            actionTarget?.railItemClicked(index)
            return true
        }

        override func rightMouseDown(with event: NSEvent) {
            actionTarget?.showContextMenu(for: site, at: event.locationInWindow)
        }
    }

    // MARK: - Tab Overview Button
    private final class TabOverviewButton: NSView {
        weak var actionTarget: BrowserWindowController?
        private let imageView = NSImageView()
        
        init(actionTarget: BrowserWindowController?) {
            self.actionTarget = actionTarget
            super.init(frame: .zero)
            setup()
        }
        
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        
        private func setup() {
            wantsLayer = true
            layer?.cornerRadius = 8
            translatesAutoresizingMaskIntoConstraints = false
            
            // Use SF Symbol for grid icon
            let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
            if let gridImage = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "Tab Overview") {
                imageView.image = gridImage.withSymbolConfiguration(config)
            }
            imageView.contentTintColor = .secondaryLabelColor
            imageView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(imageView)
            
            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 24),
                imageView.heightAnchor.constraint(equalToConstant: 24)
            ])
            
            // Click gesture
            let click = NSClickGestureRecognizer(target: self, action: #selector(clicked))
            addGestureRecognizer(click)
            
            // Hover effect
            let tracking = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(tracking)
            
            // Accessibility
            setAccessibilityElement(true)
            setAccessibilityRole(.button)
            setAccessibilityLabel("Tab Overview")
            setAccessibilityHelp("Show all tabs in grid view")
        }
        
        @objc private func clicked() {
            actionTarget?.tabOverviewClicked()
        }
        
        override func mouseEntered(with event: NSEvent) {
            layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.15).cgColor
            imageView.contentTintColor = .labelColor
        }
        
        override func mouseExited(with event: NSEvent) {
            layer?.backgroundColor = .clear
            imageView.contentTintColor = .secondaryLabelColor
        }
    }
}

// MARK: - Snapshot Cache
class SnapshotCache {
    static let shared = SnapshotCache()
    
    private struct CachedSnapshot {
        let image: NSImage
        let timestamp: Date
    }
    
    private var cache: [String: CachedSnapshot] = [:]
    private let cacheExpiration: TimeInterval = 120 // 2 minutes
    
    func get(for siteId: String) -> NSImage? {
        guard let cached = cache[siteId] else { return nil }
        
        // Check if expired
        if Date().timeIntervalSince(cached.timestamp) > cacheExpiration {
            cache.removeValue(forKey: siteId)
            return nil
        }
        
        return cached.image
    }
    
    func set(_ image: NSImage, for siteId: String) {
        cache[siteId] = CachedSnapshot(image: image, timestamp: Date())
    }
    
    func clear() {
        cache.removeAll()
    }
}

// MARK: - Tab Overview Overlay
class TabOverviewView: NSView {
    private let tabs: [SiteTab]
    private let activeIndex: Int
    private let onSelect: (Int) -> Void
    private let onDismiss: () -> Void
    private let scrollView = NSScrollView()
    private let containerView = NSView()
    private var itemViews: [TabOverviewItemView] = []
    private var selectedIndex: Int?
    private var columns: Int = 1
    private var lastLayoutSize: CGSize = .zero

    // Debugging aids (temporary) - gated behind DEBUG so they never log in release builds

    
    init(tabs: [SiteTab], activeIndex: Int, onSelect: @escaping (Int) -> Void, dismissHandler: @escaping () -> Void) {
        self.tabs = tabs
        self.activeIndex = activeIndex
        self.onSelect = onSelect
        self.onDismiss = dismissHandler
        super.init(frame: .zero)
        setup()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.0).cgColor
        
        // Blur background - blocks all interaction with content below
        let blurView = NSVisualEffectView()
        blurView.material = .hudWindow
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)
        
        // Block all interaction with content below
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
        
        // Scroll view for grid
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        addSubview(scrollView)
        
        containerView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = containerView
        
        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            containerView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
        
        // Configure scroll view to center content vertically
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero
        
        // Set up scroll view notifications for lazy loading
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollViewDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        
        // Initial grid will be built once the view has a valid size
        
        // Click outside to dismiss
        let click = NSClickGestureRecognizer(target: self, action: #selector(backgroundClicked))
        addGestureRecognizer(click)
        
        // Keyboard support for navigation and selection
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            switch event.keyCode {
            case 53: // Escape
                self.onDismiss()
                return nil
            case 36: // Enter
                if let selected = self.selectedIndex {
                    self.onSelect(selected)
                }
                return nil
            case 48: // Tab
                let forward = !event.modifierFlags.contains(.shift)
                self.navigateTab(forward: forward)
                return nil
            case 123: // Left arrow
                self.navigateLeft()
                return nil
            case 124: // Right arrow
                self.navigateRight()
                return nil
            case 125: // Down arrow
                self.navigateDown()
                return nil
            case 126: // Up arrow
                self.navigateUp()
                return nil
            default:
                return event
            }
        }
        
        // Start with active tab selected
        selectedIndex = activeIndex
        updateSelection()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateGridIfNeeded()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateGridIfNeeded()
    }

    private func updateGridIfNeeded() {
        let size = bounds.size
        guard size.width > 0 && size.height > 0 else { return }
        if size != lastLayoutSize {
            rebuildGrid(for: size)
            lastLayoutSize = size
        }
    }

    private func rebuildGrid(for size: CGSize) {
        // Clear existing views only when the size actually changes
        containerView.subviews.forEach { $0.removeFromSuperview() }
        itemViews.removeAll()
        layoutGrid()

        // Ensure frames are up to date before adjusting insets
        containerView.layoutSubtreeIfNeeded()
        
        // Force layer geometry to sync before hit-testing becomes active
        // This prevents coordinate space mismatches in layer-backed scroll views
        CATransaction.begin()
        CATransaction.flush()
        CATransaction.commit()
        
        // Force scroll view to update its document view's bounds
        scrollView.layoutSubtreeIfNeeded()
        
        // Synchronously center now (with retries if the document view hasn't stabilized)
        centerContentVertically(retryAttempt: 0)

        // Also schedule a follow-up re-center on the next run-loop in case some
        // frames (documentView / scroll clip) are still being finalized by AppKit.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.scrollView.layoutSubtreeIfNeeded()
            // Re-apply resolved appearance colors after layout stabilizes
            self.itemViews.forEach { $0.updateAppearance() }
            self.centerContentVertically(retryAttempt: 1)
        }

        // Preserve current selection highlight after rebuild
        updateSelection()
    }

    fileprivate func centerContentVertically(retryAttempt: Int = 0) {
        // Ensure layout is applied before measuring
        containerView.layoutSubtreeIfNeeded()
        scrollView.layoutSubtreeIfNeeded()

        // Use fittingSize so we measure the size Auto Layout wants for the document view
        let contentHeight = containerView.fittingSize.height
        let scrollHeight = scrollView.contentView.bounds.height

        // If sizes are not ready yet, schedule a short retry (Safari-like patience)
        if contentHeight <= 0 || scrollHeight <= 0 {
            if retryAttempt < 3 {
                let delays: [TimeInterval] = [0.02, 0.08, 0.2]
                let delay = delays[min(retryAttempt, delays.count - 1)]
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.centerContentVertically(retryAttempt: retryAttempt + 1)
                }
            }
            return
        }

        if contentHeight < scrollHeight {
            let topInset = (scrollHeight - contentHeight) / 2
            if scrollView.contentInsets.top != topInset {
                scrollView.contentInsets = NSEdgeInsets(top: topInset, left: 0, bottom: topInset, right: 0)
                // Ensure content is positioned after insets change
                // Note: when content is smaller than the clip, origin (0,0) shows the bottom.
                // To center visually, scroll the clip origin upward by -topInset.
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: -topInset))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        } else {
            // Clear any existing centering insets
            if !NSEdgeInsetsEqual(scrollView.contentInsets, NSEdgeInsetsZero) {
                scrollView.contentInsets = NSEdgeInsetsZero
                scrollView.contentView.scroll(to: NSPoint.zero)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
    }
    
    private func layoutGrid() {
        // Guard against layout before view has proper dimensions
        guard bounds.width > 0 && bounds.height > 0 else { return }
        
        // Calculate responsive grid
        let windowWidth = bounds.width
        let margin: CGFloat = 40
        let spacing: CGFloat = 20
        let minItemWidth: CGFloat = 280
        let aspectRatio: CGFloat = 16.0 / 10.0 // Width / Height
        
        // Calculate columns based on window width
        let availableWidth = windowWidth - (2 * margin)
        columns = max(1, Int((availableWidth + spacing) / (minItemWidth + spacing)))
        columns = min(columns, 4) // Max 4 columns
        
        let itemWidth = (availableWidth - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        let itemHeight = itemWidth / aspectRatio
        
        var currentRow: [NSView] = []
        var topAnchor: NSLayoutYAxisAnchor = containerView.topAnchor
        var topConstant: CGFloat = margin
        
        for (index, tab) in tabs.enumerated() {
            let itemView = TabOverviewItemView(
                tab: tab,
                index: index,
                isActive: index == activeIndex,
                width: itemWidth,
                height: itemHeight
            )
            itemView.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(itemView)
            itemViews.append(itemView)
            
            let column = index % columns
            currentRow.append(itemView)
            
            // Position constraints
            NSLayoutConstraint.activate([
                itemView.widthAnchor.constraint(equalToConstant: itemWidth),
                itemView.heightAnchor.constraint(equalToConstant: itemHeight),
                itemView.topAnchor.constraint(equalTo: topAnchor, constant: topConstant)
            ])
            
            if column == 0 {
                itemView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: margin).isActive = true
            } else {
                itemView.leadingAnchor.constraint(equalTo: currentRow[column - 1].trailingAnchor, constant: spacing).isActive = true
            }
            
            // Add click handler
            let click = NSClickGestureRecognizer(target: self, action: #selector(itemClicked(_:)))
            itemView.addGestureRecognizer(click)
            itemView.itemIndex = index
            
            // Start new row
            if column == columns - 1 || index == tabs.count - 1 {
                topAnchor = itemView.bottomAnchor
                topConstant = spacing
                currentRow = []
            }
        }
        
        // Bottom constraint
        if let lastItem = itemViews.last {
            lastItem.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -margin).isActive = true
        }
    }
    
    @objc private func itemClicked(_ gesture: NSClickGestureRecognizer) {
        guard let view = gesture.view as? TabOverviewItemView else { return }
        onSelect(view.itemIndex)
    }
    
    @objc private func backgroundClicked(_ gesture: NSClickGestureRecognizer) {
        let location = gesture.location(in: self)
        // Only dismiss if clicking outside any item
        for itemView in itemViews {
            if itemView.frame.contains(location) {
                return
            }
        }
        onDismiss()
    }
    
    private func navigateTab(forward: Bool) {
        guard !tabs.isEmpty else { return }
        if let current = selectedIndex {
            selectedIndex = forward ? (current + 1) % tabs.count : (current - 1 + tabs.count) % tabs.count
        } else {
            selectedIndex = forward ? 0 : tabs.count - 1
        }
        updateSelection()
    }
    
    private func navigateLeft() {
        guard let current = selectedIndex, current > 0 else { return }
        selectedIndex = current - 1
        updateSelection()
    }
    
    private func navigateRight() {
        guard let current = selectedIndex, current < tabs.count - 1 else { return }
        selectedIndex = current + 1
        updateSelection()
    }
    
    private func navigateUp() {
        guard let current = selectedIndex, current >= columns else { return }
        selectedIndex = current - columns
        updateSelection()
    }
    
    private func navigateDown() {
        guard let current = selectedIndex else { return }
        let newIndex = current + columns
        if newIndex < tabs.count {
            selectedIndex = newIndex
            updateSelection()
        }
    }
    
    private func updateSelection() {
        for (index, itemView) in itemViews.enumerated() {
            itemView.setSelected(index == selectedIndex)
        }
        
        // Scroll to selected item if needed
        if let selected = selectedIndex, selected < itemViews.count {
            let itemView = itemViews[selected]
            scrollView.contentView.scrollToVisible(itemView.frame)
        }
    }
    
    func appear() {
        alphaValue = 0.0
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.animator().alphaValue = 1.0
        })
    }
    
    func scrollToTop() {
        scrollView.contentView.scroll(to: NSPoint.zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
    
    func disappear(completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            self.animator().alphaValue = 0.0
        }, completionHandler: completion)
    }
    
    @objc private func scrollViewDidScroll() {
        // Trigger snapshot capture for newly visible items
        let visibleRect = scrollView.documentVisibleRect
        for itemView in itemViews where !itemView.hasSnapshot {
            let itemFrame = itemView.frame
            if visibleRect.intersects(itemFrame) {
                itemView.captureSnapshotIfNeeded()
            }
        }
    }
    
    // Block all mouse events from passing through to content below
    override var acceptsFirstResponder: Bool { return true }
    override func mouseDown(with event: NSEvent) { /* Block */ }
    override func mouseDragged(with event: NSEvent) { /* Block */ }
    override func mouseUp(with event: NSEvent) { /* Block */ }
    override func mouseMoved(with event: NSEvent) { /* Block */ }
    override func mouseEntered(with event: NSEvent) { /* Block */ }
    override func mouseExited(with event: NSEvent) { /* Block */ }
    override func rightMouseDown(with event: NSEvent) { /* Block */ }
    override func rightMouseUp(with event: NSEvent) { /* Block */ }
    override func otherMouseDown(with event: NSEvent) { /* Block */ }
    override func otherMouseUp(with event: NSEvent) { /* Block */ }
    override func scrollWheel(with event: NSEvent) {
        // Allow scrolling within the overview
        super.scrollWheel(with: event)
    }
    
    override func cursorUpdate(with event: NSEvent) {
        // Force arrow cursor and prevent cursor updates from content below
        NSCursor.arrow.set()
    }
    
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
        discardCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }
    
    // No heavy work in layout(): grid is built only on size changes
}

// MARK: - Tab Overview Item View
class TabOverviewItemView: NSView {
    private let tab: SiteTab
    var itemIndex: Int
    private let isActive: Bool
    private let snapshotView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let faviconView = NSImageView()
    private var isSelected = false
    private(set) var hasSnapshot = false
    private let displayWidth: CGFloat
    private let displayHeight: CGFloat
    
    init(tab: SiteTab, index: Int, isActive: Bool, width: CGFloat, height: CGFloat) {
        self.tab = tab
        self.itemIndex = index
        self.isActive = isActive
        self.displayWidth = width
        self.displayHeight = height
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        setup()
        
        // Only capture first 10 items immediately, rest are lazy loaded
        if index < 10 {
            captureSnapshotIfNeeded()
        }
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = isActive ? 3 : 1
        layer?.borderColor = isActive ? NSColor.controlAccentColor.cgColor : NSColor.separatorColor.cgColor
        // Defer background color resolution to updateAppearance() so we pick up the effective appearance
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.shadowOpacity = 0.2
        layer?.shadowRadius = 8
        layer?.shadowOffset = NSSize(width: 0, height: -2)
        // Prevent implicit animations on color changes (stops blinking during resize)
        layer?.actions = ["backgroundColor": NSNull(), "borderColor": NSNull(), "shadowColor": NSNull()]
        
        // Snapshot view (main content)
        snapshotView.translatesAutoresizingMaskIntoConstraints = false
        snapshotView.imageScaling = .scaleProportionallyUpOrDown
        snapshotView.wantsLayer = true
        snapshotView.layer?.cornerRadius = 8
        snapshotView.layer?.masksToBounds = true
        // Defer snapshot background color to updateAppearance()
        snapshotView.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(snapshotView)
        
        // Bottom bar with favicon and title
        let bottomBar = NSView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.wantsLayer = true
        // Defer bottom bar color to updateAppearance()
        bottomBar.layer?.backgroundColor = NSColor.clear.cgColor
        bottomBar.identifier = NSUserInterfaceItemIdentifier("TabOverviewItemBottomBar")
        addSubview(bottomBar)
        
        if let faviconName = tab.site.favicon, let img = FaviconFetcher.shared.image(forResource: faviconName) {
            faviconView.image = img
        } else if let host = tab.site.url.host {
            faviconView.image = FaviconFetcher.shared.generateMonoIcon(for: host)
        }

        // Observe favicon saves to update this overview item's favicon when it becomes available
        NotificationCenter.default.addObserver(self, selector: #selector(faviconSaved(_:)), name: .FaviconSaved, object: nil)
        
        // Title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = tab.webView.title ?? tab.site.name
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.alignment = .left
        bottomBar.addSubview(titleLabel)
        
        // Favicon
        faviconView.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(faviconView)
        
        // Active indicator
        if isActive {
            let activeLabel = NSTextField(labelWithString: "Active")
            activeLabel.translatesAutoresizingMaskIntoConstraints = false
            activeLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
            activeLabel.textColor = .controlAccentColor
            activeLabel.alignment = .right
            bottomBar.addSubview(activeLabel)
            
            NSLayoutConstraint.activate([
                activeLabel.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -12),
                activeLabel.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor)
            ])
        }
        
        NSLayoutConstraint.activate([
            snapshotView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            snapshotView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            snapshotView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            snapshotView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -4),
            
            bottomBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 44),
            
            faviconView.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 12),
            faviconView.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            faviconView.widthAnchor.constraint(equalToConstant: 20),
            faviconView.heightAnchor.constraint(equalToConstant: 20),
            
            titleLabel.leadingAnchor.constraint(equalTo: faviconView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: bottomBar.trailingAnchor, constant: isActive ? -70 : -12)
        ])
        
        // Hover tracking
        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)

        // Ensure colors match the current effective appearance
        updateAppearance()
    }

    @objc private func faviconSaved(_ note: Notification) {
        guard let info = note.userInfo as? [String: Any], let siteId = info["siteId"] as? String, siteId == tab.site.id else { return }
        guard let fname = info["filename"] as? String else { return }
        if let img = FaviconFetcher.shared.image(forResource: fname) {
            DispatchQueue.main.async {
                self.faviconView.image = img
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Re-apply appearance-resolved colors when the system appearance changes
        updateAppearance()
    }

    // Update layer-backed colors according to the view's effective appearance
    fileprivate func updateAppearance() {
        // Resolve semantic colors for the current appearance context without animations
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            self.snapshotView.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
            // bottomBar is identified by a known identifier
            if let bottomBar = self.subviews.first(where: { $0.identifier?.rawValue == "TabOverviewItemBottomBar" }) {
                bottomBar.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.95).cgColor
            }
        }
        CATransaction.commit()
    }
    
    func captureSnapshotIfNeeded() {
        guard !hasSnapshot else { return }
        
        // Check cache first
        if let cachedImage = SnapshotCache.shared.get(for: tab.site.id) {
            snapshotView.image = cachedImage
            hasSnapshot = true
            return
        }
        
        let webView = tab.webView
        
        // Calculate thumbnail size (2x for retina)
        let scale: CGFloat = 2.0
        let thumbnailWidth = displayWidth * scale
        let thumbnailHeight = (displayHeight - 44) * scale // Subtract bottom bar height
        
        // Configure snapshot at thumbnail size instead of full webView size
        let config = WKSnapshotConfiguration()
        
        // Calculate the portion of webView to capture while maintaining aspect ratio
        let webViewAspect = webView.bounds.width / webView.bounds.height
        let thumbnailAspect = thumbnailWidth / thumbnailHeight
        
        var snapshotRect: CGRect
        if webViewAspect > thumbnailAspect {
            // WebView is wider, capture centered width
            let captureWidth = webView.bounds.height * thumbnailAspect
            let offsetX = (webView.bounds.width - captureWidth) / 2
            snapshotRect = CGRect(x: offsetX, y: 0, width: captureWidth, height: webView.bounds.height)
        } else {
            // WebView is taller, capture from top
            let captureHeight = webView.bounds.width / thumbnailAspect
            snapshotRect = CGRect(x: 0, y: 0, width: webView.bounds.width, height: captureHeight)
        }
        
        config.rect = snapshotRect
        config.snapshotWidth = NSNumber(value: Double(thumbnailWidth))
        
        webView.takeSnapshot(with: config) { [weak self] image, error in
            guard let self = self else { return }
            
            if let image = image {
                DispatchQueue.main.async {
                    self.snapshotView.image = image
                    self.hasSnapshot = true
                    // Cache the snapshot
                    SnapshotCache.shared.set(image, for: self.tab.site.id)
                }
            } else {
                // Show placeholder if snapshot fails
                DispatchQueue.main.async {
                    self.showPlaceholder()
                    self.hasSnapshot = true
                }
            }
        }
    }
    
    private func showPlaceholder() {
        // Show large favicon as placeholder
        if let faviconName = tab.site.favicon, let img = FaviconFetcher.shared.image(forResource: faviconName) {
            snapshotView.image = img
        } else if let host = tab.site.url.host {
            snapshotView.image = FaviconFetcher.shared.generateMonoIcon(for: host)
        }
        snapshotView.imageScaling = .scaleProportionallyDown
    }
    
    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.push()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            // Don't override keyboard-selected highlight
            if !self.isSelected {
                self.layer?.borderColor = NSColor.controlAccentColor.cgColor
            }
            self.layer?.shadowOpacity = 0.4
        })
    }
    
    override func mouseExited(with event: NSEvent) {
        NSCursor.pop()
        if !isSelected {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                self.layer?.borderColor = isActive ? NSColor.controlAccentColor.cgColor : NSColor.separatorColor.cgColor
                self.layer?.shadowOpacity = 0.2
            })
        }
    }
    
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
    
    func setSelected(_ selected: Bool) {
        isSelected = selected
        if selected {
            // Focused state: thick green border with strong glow (consistent in light/dark)
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                self.layer?.borderWidth = 3
                self.layer?.borderColor = NSColor.systemGreen.cgColor
                self.layer?.shadowColor = NSColor.systemGreen.cgColor
                self.layer?.shadowOpacity = 0.8
                self.layer?.shadowRadius = 12
            })
        } else {
            // Non-focused state
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                self.layer?.borderWidth = isActive ? 3 : 1
                self.layer?.borderColor = isActive ? NSColor.controlAccentColor.cgColor : NSColor.separatorColor.cgColor
                self.layer?.shadowColor = NSColor.black.cgColor
                self.layer?.shadowOpacity = 0.2
                self.layer?.shadowRadius = 8
            })
        }
    }
}

// Simplified window delegate to keep layout updated when window becomes key or resizes
extension BrowserWindowController: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        DispatchQueue.main.async {
            self.contentContainer.layoutSubtreeIfNeeded()
            self.activeTabChanged()
        }
    }

    func windowDidResize(_ notification: Notification) {
        // Nothing special for now; views use Auto Layout
    }
}
