import AppKit
import WebKit

class BrowserWindowController: NSWindowController {
    // UI
    private let tabScrollView: NSScrollView = NSScrollView()
    private let tabStackView: NSStackView = NSStackView()
    private let newTabButton: NSButton = NSButton(title: "+", target: nil, action: nil)

    // Address and content
    let addressLabel: NSTextField
    private let contentContainer: NSView = NSView()

    // Tab coordination
    private var activeWebView: WKWebView? {
        guard let idx = TabManager.shared.tabs.indices.contains(TabManager.shared.activeIndex) ? TabManager.shared.activeIndex : nil else { return nil }
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

        // Create initial tab
        if TabManager.shared.tabs.isEmpty {
            _ = TabManager.shared.createTab(with: URL(string: "https://example.com"))
        } else {
            // ensure active is visible
            activeTabChanged()
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

        // Layout - add tab bar container
        content.addSubview(tabBarContainer)
        tabBarContainer.addSubview(tabScrollView)
        tabBarContainer.addSubview(newTabButton)
        content.addSubview(addressLabel)
        content.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            tabBarContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            tabBarContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            tabBarContainer.topAnchor.constraint(equalTo: content.topAnchor),
            tabBarContainer.heightAnchor.constraint(equalToConstant: 36),

            tabScrollView.leadingAnchor.constraint(equalTo: tabBarContainer.leadingAnchor, constant: 8),
            tabScrollView.centerYAnchor.constraint(equalTo: tabBarContainer.centerYAnchor),
            tabScrollView.trailingAnchor.constraint(equalTo: newTabButton.leadingAnchor, constant: -8),
            tabScrollView.heightAnchor.constraint(equalTo: tabBarContainer.heightAnchor),

            newTabButton.trailingAnchor.constraint(equalTo: tabBarContainer.trailingAnchor, constant: -8),
            newTabButton.centerYAnchor.constraint(equalTo: tabBarContainer.centerYAnchor),

            addressLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            addressLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            addressLabel.topAnchor.constraint(equalTo: tabBarContainer.bottomAnchor, constant: 6),
            addressLabel.heightAnchor.constraint(equalToConstant: 18),

            contentContainer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: addressLabel.bottomAnchor, constant: 6),
            contentContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor)
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
        contentContainer.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            webView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            webView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
        webView.navigationDelegate = self
    }

    @objc private func tabsChanged() {
        NSLog("Tabs changed: count=\(TabManager.shared.tabs.count)")
        rebuildTabButtons()
    }

    @objc private func activeTabChanged() {
        NSLog("Active tab changed: activeIndex=\(TabManager.shared.activeIndex)")
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
        NSLog("Rebuilding tabs: \(TabManager.shared.tabs.map { $0.title.isEmpty ? ($0.url?.host ?? "New Tab") : $0.title })")
        // Clear
        tabStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for (index, tab) in TabManager.shared.tabs.enumerated() {
            let btn = NSButton(title: tab.title.isEmpty ? (tab.url?.host ?? "New Tab") : tab.title, target: self, action: #selector(tabButtonPressed(_:)))
            btn.tag = index
            btn.setButtonType(.momentaryPushIn)
            btn.bezelStyle = .texturedSquare
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.setContentHuggingPriority(.defaultLow, for: .horizontal)
            btn.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            // close button overlay
            let close = NSButton(title: "✕", target: self, action: #selector(closeTabPressed(_:)))
            close.tag = index
            close.bezelStyle = .regularSquare
            close.font = NSFont.systemFont(ofSize: 10)
            close.translatesAutoresizingMaskIntoConstraints = false
            close.setContentHuggingPriority(.required, for: .horizontal)
            close.setContentCompressionResistancePriority(.required, for: .horizontal)
            close.widthAnchor.constraint(equalToConstant: 18).isActive = true

            let container = NSView()
            container.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(btn)
            container.addSubview(close)

            NSLayoutConstraint.activate([
                btn.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                btn.topAnchor.constraint(equalTo: container.topAnchor),
                btn.bottomAnchor.constraint(equalTo: container.bottomAnchor),

                close.leadingAnchor.constraint(equalTo: btn.trailingAnchor, constant: 6),
                close.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                close.centerYAnchor.constraint(equalTo: btn.centerYAnchor),
            ])

            // Ensure the container has an intrinsic width based on its children
            container.setContentHuggingPriority(.defaultLow, for: .horizontal)
            tabStackView.addArrangedSubview(container)
        }

        // Keep new tab button visible at end
        if newTabButton.superview == nil {
            // ensure it's in window view
            if let content = window?.contentView {
                content.addSubview(newTabButton)
            }
        }
    }
}

// MARK: - WKNavigationDelegate
extension BrowserWindowController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        addressLabel.stringValue = webView.url?.absoluteString ?? ""
        if let idx = TabManager.shared.tabs.firstIndex(where: { $0.webView == webView }) {
            TabManager.shared.tabs[idx].title = webView.title ?? webView.url?.host ?? ""
            rebuildTabButtons()
        }
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
