import Foundation
import WebKit

struct TabSettings: Codable {
    var javascriptEnabled: Bool = true
    var zoomLevel: Double = 1.0

    static var `default`: TabSettings { .init() }
}

final class Tab: NSObject {
    let identifier: UUID = .init()
    let webView: WKWebView
    var title: String = ""
    var url: URL?
    var favicon: NSImage?
    var isLoading: Bool = false {
        didSet { NotificationCenter.default.post(name: Notification.Name("Vaaka.TabUpdated"), object: self) }
    }
    var settings: TabSettings = .default
    var lastActiveTime: Date = Date()
    var isSuspended: Bool = false
    var pendingURL: URL?

    init(configuration: WKWebViewConfiguration = WKWebViewConfiguration()) {
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
    }

    func fetchFaviconIfNeeded() {
        guard favicon == nil, let u = url else { return }
        FaviconFetcher.shared.fetchFavicon(for: u) { img in
            DispatchQueue.main.async {
                self.favicon = img
                NotificationCenter.default.post(name: Notification.Name("Vaaka.TabUpdated"), object: self)
            }
        }
    }
}
