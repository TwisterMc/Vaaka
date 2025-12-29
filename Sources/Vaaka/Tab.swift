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

    init(site: Site, configuration: WKWebViewConfiguration = WKWebViewConfiguration()) {
        self.site = site
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        // Do not load the start URL immediately — wait until the WebView is attached to the window/content view.
        // This avoids spurious `open` attempts while the WebView is not yet part of the responder/window chain.
    }

    /// Load the site's start URL if it hasn't been loaded already. Safe to call multiple times.
    func loadStartURLIfNeeded() {
        guard !hasLoadedStartURL else { return }
        hasLoadedStartURL = true
        let req = URLRequest(url: site.url)
        webView.load(req)
    }
}
