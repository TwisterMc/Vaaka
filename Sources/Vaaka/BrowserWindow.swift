import AppKit
import WebKit

class BrowserWindowController: NSWindowController {
    // UI
    private let tabBarContainer: NSView = NSView()
    private let tabScrollView: NSScrollView = NSScrollView()
    private let tabStackView: NSStackView = NSStackView()
    private let newTabButton: NSButton = NSButton(title: "+", target: nil, action: nil)

    // Address and content
    let addressLabel: NSTextField
    private let contentContainer: NSView = NSView()

    // Tab coordination
    private var activeWebView: WKWebView? {
        let idx = TabManager.shared.activeIndex
        guard TabManager.shared.tabs.indices.contains(idx) else { return nil }
        return TabManager.shared.tabs[idx].webView
    }

    convenience init() {
        let rect = NSRect(x: 100, y: 100, width: 1200, height: 800)
        let style: NSWindow.StyleMask = [.titled, .closable, .resizable, .miniaturizable]
        let window = NSWindow(contentRect: rect, styleMask: style, backing: .buffered, defer: false)
        window.title = "Vaaka"
        self.init(window: window)
    }

    override init(window: NSWindow?) {
        addressLabel = NSTextField(labelWithString: "")

        super.init(window: window)

        setupUI()

        // Observe tab manager
        NotificationCenter.default.addObserver(self, selector: #selector(tabsChanged), name: .TabsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(activeTabChanged), name: .ActiveTabChanged, object: nil)

        // Window delegate for lifecycle hooks
        self.window?.delegate = self

        // Create initial tab once the run loop has a chance to lay out the window
        DispatchQueue.main.async {
            if TabManager.shared.tabs.isEmpty {
                _ = TabManager.shared.createTab(with: URL(string: "https://example.com"))
            } else {
                // ensure active is visible
                self.activeTabChanged()
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupUI() {
        guard let content = window?.contentView else { return }
        content.translatesAutoresizingMaskIntoConstraints = false

        // Tab bar setup
        // Tab bar container (keeps scroll view and new tab button together)
        let tabBarContainer = NSView()
        tabBarContainer.translatesAutoresizingMaskIntoConstraints = false

        tabStackView.orientation = .horizontal
        tabStackView.spacing = 6
        tabStackView.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        tabStackView.translatesAutoresizingMaskIntoConstraints = false
        tabStackView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        tabScrollView.hasHorizontalScroller = true
        tabScrollView.drawsBackground = false
        tabScrollView.translatesAutoresizingMaskIntoConstraints = false
        tabScrollView.borderType = .noBorder

        // Create a document container for the scroll view and add the tabStack inside it.
        let docView = NSView()
        docView.translatesAutoresizingMaskIntoConstraints = false
        docView.addSubview(tabStackView)
        tabStackView.translatesAutoresizingMaskIntoConstraints = false
        tabStackView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        tabScrollView.documentView = docView

        newTabButton.bezelStyle = .texturedRounded
        newTabButton.target = self
        newTabButton.action = #selector(newTabPressed(_:))
        newTabButton.setContentHuggingPriority(.required, for: .horizontal)
        newTabButton.translatesAutoresizingMaskIntoConstraints = false

        // Address label
        addressLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        addressLabel.lineBreakMode = .byTruncatingMiddle
        addressLabel.translatesAutoresizingMaskIntoConstraints = false
        addressLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        // Content area
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        // Layout - use a vertical stack so contentContainer expands correctly
        // Layout using explicit constraints so contentContainer fills available space
        tabBarContainer.translatesAutoresizingMaskIntoConstraints = false
        tabBarContainer.addSubview(tabScrollView)
        tabBarContainer.addSubview(newTabButton)
        content.addSubview(tabBarContainer)
        content.addSubview(addressLabel)
        content.addSubview(contentContainer)

        // fixed heights
        tabBarContainer.heightAnchor.constraint(equalToConstant: 36).isActive = true
        addressLabel.heightAnchor.constraint(equalToConstant: 18).isActive = true

        // make contentContainer flexible
        contentContainer.setContentHuggingPriority(.defaultLow, for: .vertical)
        contentContainer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        NSLayoutConstraint.activate([
            tabBarContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            tabBarContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            tabBarContainer.topAnchor.constraint(equalTo: content.topAnchor),

            addressLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            addressLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            addressLabel.topAnchor.constraint(equalTo: tabBarContainer.bottomAnchor, constant: 6),

            contentContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: addressLabel.bottomAnchor, constant: 6),
            contentContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            tabScrollView.leadingAnchor.constraint(equalTo: tabBarContainer.leadingAnchor, constant: 8),
            tabScrollView.centerYAnchor.constraint(equalTo: tabBarContainer.centerYAnchor),
            tabScrollView.trailingAnchor.constraint(equalTo: newTabButton.leadingAnchor, constant: -8),
            tabScrollView.heightAnchor.constraint(equalTo: tabBarContainer.heightAnchor),

            newTabButton.trailingAnchor.constraint(equalTo: tabBarContainer.trailingAnchor, constant: -8),
            newTabButton.centerYAnchor.constraint(equalTo: tabBarContainer.centerYAnchor)
        ])

        // Constrain stack view to the docView and ensure docView width is at least the scrollContent width so it won't collapse.
        NSLayoutConstraint.activate([
            tabStackView.leadingAnchor.constraint(equalTo: docView.leadingAnchor),
            tabStackView.topAnchor.constraint(equalTo: docView.topAnchor),
            tabStackView.bottomAnchor.constraint(equalTo: docView.bottomAnchor),
            tabStackView.heightAnchor.constraint(equalTo: docView.heightAnchor),

            // Ensure document view expands to fill the scroll content area (prevents zero width collapse).
            docView.widthAnchor.constraint(greaterThanOrEqualTo: tabScrollView.contentView.widthAnchor)
        ])

        // Make the docView flexible by giving its width constraint a lower priority so it can grow with content.
        if let widthConstraint = docView.constraints.first(where: { $0.firstAnchor == docView.widthAnchor }) {
            widthConstraint.priority = .defaultLow
        }

        // Initial render of tabs
        rebuildTabButtons()
    }
}

// MARK: - Tab UI handling
extension BrowserWindowController {
    @objc private func newTabPressed(_ sender: Any?) {
        if !TabManager.shared.canCreateTab() {
            let alert = NSAlert()
            alert.messageText = "Maximum Tabs Reached"
            alert.informativeText = "You can have up to 20 tabs open. Close a tab to open a new one."
            alert.runModal()
            return
        }

        if let tab = TabManager.shared.createTab(with: URL(string: "https://example.com")) {
            attachWebView(tab.webView)
            rebuildTabButtons()
        }
    }

    @objc private func tabButtonPressed(_ sender: NSButton) {
        let idx = sender.tag
        TabManager.shared.setActiveTab(index: idx)
    }

    @objc private func closeTabPressed(_ sender: NSButton) {
        let idx = sender.tag
        TabManager.shared.closeTab(at: idx)
        rebuildTabButtons()
        // update displayed webview
        activeTabChanged()
    }

    private func attachWebView(_ webView: WKWebView) {
        // Remove existing
        for sub in contentContainer.subviews { sub.removeFromSuperview() }
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        contentContainer.addSubview(webView)

        // Try using Auto Layout first
        let constraints = [
            webView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            webView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            webView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ]
        NSLayoutConstraint.activate(constraints)
        webView.navigationDelegate = self

        // Force layout so we can quickly observe frames
        contentContainer.layoutSubtreeIfNeeded()
        webView.layoutSubtreeIfNeeded()
        print("Attaching webView (post-layout); url=\(webView.url?.absoluteString ?? "(nil)") frame=\(webView.frame) container=\(contentContainer.frame)")
        vaakaLog("Attaching webView (post-layout); url=\(webView.url?.absoluteString ?? "(nil)") frame=\(webView.frame) container=\(contentContainer.frame)")

        // If height is still zero (autolayout hasn't resolved), fallback to manual frame sizing
        if contentContainer.frame.height <= 1 {
            NSLayoutConstraint.deactivate(constraints)
            webView.translatesAutoresizingMaskIntoConstraints = true
            let contentBounds = contentContainer.bounds
            var manualFrame = contentBounds
            if manualFrame.height <= 1 {
                // compute based on window
                if let w = self.window, let contentView = w.contentView {
                    let contentRect = w.contentLayoutRect
                    let topReserved = CGFloat(36 + 6 + 18 + 6) // tabbar + gap + address + gap
                    let width = contentRect.width
                    let height = max(200, contentRect.height - topReserved)

                    let frameInWindow = CGRect(x: contentRect.minX, y: contentRect.minY, width: width, height: height)

                    // Add webView directly to window contentView as a fallback
                    webView.removeFromSuperview()
                    webView.translatesAutoresizingMaskIntoConstraints = true
                    webView.frame = frameInWindow
                    webView.autoresizingMask = [.width, .height]
                    contentView.addSubview(webView)
                    contentView.layoutSubtreeIfNeeded()

                    print("Attaching webView (window fallback); frame=\(webView.frame) contentView=\(contentView.frame)")
                    vaakaLog("Attaching webView (window fallback); frame=\(webView.frame) contentView=\(contentView.frame)")
                    return
                } else {
                    manualFrame.size.height = 400
                    manualFrame.size.width = 800
                }
            }
            webView.frame = manualFrame
            webView.autoresizingMask = [.width, .height]
            contentContainer.addSubview(webView)
            contentContainer.layoutSubtreeIfNeeded()
            print("Attaching webView (manual layout); frame=\(webView.frame) container=\(contentContainer.frame)")
            vaakaLog("Attaching webView (manual layout); frame=\(webView.frame) container=\(contentContainer.frame)")
        }
    }

    @objc private func tabsChanged() {
        print("Tabs changed: count=\(TabManager.shared.tabs.count)")
        vaakaLog("Tabs changed: count=\(TabManager.shared.tabs.count)")
        rebuildTabButtons()
    }

    @objc private func activeTabChanged() {
        print("Active tab changed: activeIndex=\(TabManager.shared.activeIndex)")
        vaakaLog("Active tab changed: activeIndex=\(TabManager.shared.activeIndex)")
        // attach active web view
        guard TabManager.shared.tabs.indices.contains(TabManager.shared.activeIndex) else {
            // no tabs, create a new one
            if TabManager.shared.tabs.isEmpty {
                _ = TabManager.shared.createTab(with: URL(string: "https://example.com"))
                rebuildTabButtons()
            }
            return
        }
        let tab = TabManager.shared.tabs[TabManager.shared.activeIndex]
        attachWebView(tab.webView)
        addressLabel.stringValue = tab.webView.url?.absoluteString ?? ""
        rebuildTabButtons()
    }

    private func rebuildTabButtons() {
        print("Rebuilding tabs: \(TabManager.shared.tabs.map { $0.title.isEmpty ? ($0.url?.host ?? "New Tab") : $0.title })")
        vaakaLog("Rebuilding tabs: \(TabManager.shared.tabs.map { $0.title.isEmpty ? ($0.url?.host ?? "New Tab") : $0.title })")
        // Clear
        tabStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (index, tab) in TabManager.shared.tabs.enumerated() {
            // Build a tab view with favicon, title and close button + loading spinner
            let faviconView = NSImageView()
            faviconView.wantsLayer = true
            faviconView.translatesAutoresizingMaskIntoConstraints = false
            faviconView.image = tab.favicon
            faviconView.imageScaling = .scaleProportionallyUpOrDown
            faviconView.layer?.cornerRadius = 4
            faviconView.layer?.masksToBounds = true
            faviconView.widthAnchor.constraint(equalToConstant: 16).isActive = true
            faviconView.heightAnchor.constraint(equalToConstant: 16).isActive = true

            let titleLabel = NSTextField(labelWithString: tab.title.isEmpty ? (tab.url?.host ?? "New Tab") : tab.title)
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.translatesAutoresizingMaskIntoConstraints = false

            let spinner = NSProgressIndicator()
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.isDisplayedWhenStopped = false
            spinner.translatesAutoresizingMaskIntoConstraints = false
            if tab.isLoading { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }

            // close button overlay
            let close = NSButton(title: "✕", target: self, action: #selector(closeTabPressed(_:)))
            close.tag = index
            close.bezelStyle = .regularSquare
            close.font = NSFont.systemFont(ofSize: 10)
            close.translatesAutoresizingMaskIntoConstraints = false
            close.setContentHuggingPriority(.required, for: .horizontal)
            close.setContentCompressionResistancePriority(.required, for: .horizontal)
            close.widthAnchor.constraint(equalToConstant: 18).isActive = true

            let contentStack = NSStackView(views: [faviconView, titleLabel])
            contentStack.orientation = .horizontal
            contentStack.spacing = 6
            contentStack.alignment = .centerY
            contentStack.translatesAutoresizingMaskIntoConstraints = false

            let container = NSView()
            container.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(contentStack)
            container.addSubview(spinner)
            container.addSubview(close)

            NSLayoutConstraint.activate([
                contentStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
                contentStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),

                spinner.leadingAnchor.constraint(equalTo: contentStack.trailingAnchor, constant: 6),
                spinner.centerYAnchor.constraint(equalTo: contentStack.centerYAnchor),

                close.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 6),
                close.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
                close.centerYAnchor.constraint(equalTo: contentStack.centerYAnchor)
            ])

            // Make the container clickable by adding a button overlay
            let clickButton = NSButton(title: "", target: self, action: #selector(tabButtonPressed(_:)))
            clickButton.isBordered = false
            clickButton.translatesAutoresizingMaskIntoConstraints = false
            clickButton.tag = index
            container.addSubview(clickButton, positioned: .below, relativeTo: contentStack)
            NSLayoutConstraint.activate([
                clickButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                clickButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                clickButton.topAnchor.constraint(equalTo: container.topAnchor),
                clickButton.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])

            // Ensure the container has an intrinsic width based on its children
            container.setContentHuggingPriority(.defaultLow, for: .horizontal)
            tabStackView.addArrangedSubview(container)
        }

        // Ensure the newTabButton is inside the tabBarContainer
        if newTabButton.superview !== tabBarContainer {
            newTabButton.removeFromSuperview()
            tabBarContainer.addSubview(newTabButton)
            // Reinforce constraints to keep it positioned correctly
            NSLayoutConstraint.activate([
                newTabButton.trailingAnchor.constraint(equalTo: tabBarContainer.trailingAnchor, constant: -8),
                newTabButton.centerYAnchor.constraint(equalTo: tabBarContainer.centerYAnchor)
            ])
        }
    }
}

// MARK: - WKNavigationDelegate
extension BrowserWindowController: WKNavigationDelegate, NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        print("windowDidBecomeKey - refreshing active tab UI")
        vaakaLog("windowDidBecomeKey - refreshing active tab UI")
        // Re-attach after window becomes key so layout is established
        DispatchQueue.main.async {
            self.contentContainer.layoutSubtreeIfNeeded()
            self.activeTabChanged()
        }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if let idx = TabManager.shared.tabs.firstIndex(where: { $0.webView == webView }) {
            let tab = TabManager.shared.tabs[idx]
            tab.isLoading = true
            DispatchQueue.main.async { tab.fetchFaviconIfNeeded() }
            rebuildTabButtons()
        }
        print("webView didStartProvisionalNavigation: url=\(webView.url?.absoluteString ?? "(nil)")")
        vaakaLog("webView didStartProvisionalNavigation: url=\(webView.url?.absoluteString ?? "(nil)")")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let idx = TabManager.shared.tabs.firstIndex(where: { $0.webView == webView }) {
            let tab = TabManager.shared.tabs[idx]
            tab.isLoading = false
            tab.title = webView.title ?? webView.url?.host ?? ""
            tab.url = webView.url
            DispatchQueue.main.async { tab.fetchFaviconIfNeeded() }
            rebuildTabButtons()
        }
        print("webView didFinish: url=\(webView.url?.absoluteString ?? "(nil)")")
        vaakaLog("webView didFinish: url=\(webView.url?.absoluteString ?? "(nil)")")
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        // Allow data/blob
        if url.scheme == "data" || url.scheme == "blob" {
            decisionHandler(.allow)
            return
        }

        if WhitelistManager.shared.isWhitelisted(url: url) {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            if webView.canGoBack { webView.goBack() }
            NSWorkspace.shared.open(url)
        }
    }
}
