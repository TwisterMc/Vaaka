import AppKit
import WebKit

class BrowserWindowController: NSWindowController {
    let webView: WKWebView
    let addressLabel: NSTextField

    convenience init() {
        let rect = NSRect(x: 100, y: 100, width: 1200, height: 800)
        let style: NSWindow.StyleMask = [.titled, .closable, .resizable, .miniaturizable]
        let window = NSWindow(contentRect: rect, styleMask: style, backing: .buffered, defer: false)
        window.title = "Vaaka"
        self.init(window: window)
    }

    override init(window: NSWindow?) {
        let config = WKWebViewConfiguration()
        let webpagePreferences = WKWebpagePreferences()
        webpagePreferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = webpagePreferences
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        webView = WKWebView(frame: .zero, configuration: config)
        addressLabel = NSTextField(labelWithString: "")

        super.init(window: window)

        webView.navigationDelegate = self
        setupUI()

        // Load a default page (lazy: will be replaced by new tab page later)
        if let url = URL(string: "https://example.com") {
            webView.load(URLRequest(url: url))
            addressLabel.stringValue = url.absoluteString
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupUI() {
        guard let content = window?.contentView else { return }
        content.translatesAutoresizingMaskIntoConstraints = false

        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 6
        container.translatesAutoresizingMaskIntoConstraints = false

        addressLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        addressLabel.lineBreakMode = .byTruncatingMiddle
        addressLabel.translatesAutoresizingMaskIntoConstraints = false
        addressLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)

        webView.translatesAutoresizingMaskIntoConstraints = false

        container.addArrangedSubview(addressLabel)
        container.addArrangedSubview(webView)
        content.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            container.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            container.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            container.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8)
        ])
    }
}

extension BrowserWindowController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        addressLabel.stringValue = webView.url?.absoluteString ?? ""
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
