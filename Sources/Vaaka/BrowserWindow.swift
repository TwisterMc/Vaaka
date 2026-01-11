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

    // Event monitor for keyboard shortcuts
    private var keyMonitor: Any?

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

        // Window delegate
        self.window?.delegate = self

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

        // Initial empty state view if no sites
        updateEmptyStateIfNeeded()
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
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Site Settings…", action: #selector(openSiteSettings(_:)), keyEquivalent: "").representedObject = site
        guard let event = NSApp.currentEvent, let win = self.window, let content = win.contentView else {
            // Unable to show context menu safely
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: content)
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

            // Accessibility: make this rail item an accessibility element (acts like a button)
            self.setAccessibilityElement(true)
            self.setAccessibilityRole(.button)
            self.setAccessibilityLabel(site.name)

            // set tooltip
            self.toolTip = site.name

            // Use instance methods for image/visibility updates (no noisy prints)

            // Load favicon (SVG preferred, PNG allowed, generated fallback)
            if let name = site.favicon, let img = FaviconFetcher.shared.image(forResource: name) {
                self.applyImage(img, reason: "setup:loaded-resource:\(name)")
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
                // cross-fade
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.18
                    imageView.animator().alphaValue = 0.0
                    spinner.animator().alphaValue = 1.0
                }, completionHandler: {
                    self.setImageHidden(true, reason: "setLoading:start:anim-complete")
                })

                // Schedule a fallback in case loading stalls: show a mono icon and stop spinner after a short timeout
                let work = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    if self.spinner.isHidden == false {
                        // Apply fallback
                        if let host = self.site.url.host {
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
                if let name = site.favicon, let img = FaviconFetcher.shared.image(forResource: name) {
                    self.applyImage(img, reason: "setLoading:refresh-resource:\(name)")
                } else if let host = site.url.host {
                    self.applyImage(FaviconFetcher.shared.generateMonoIcon(for: host), reason: "setLoading:generated-mono-for:\(host)")
                }

                self.setImageHidden(false, reason: "setLoading:finish:ensure-visible")
                self.setImageAlpha(0.0, reason: "setLoading:finish:alpha-0")
                // cross-fade back
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.18
                    spinner.animator().alphaValue = 0.0
                    imageView.animator().alphaValue = 1.0
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
