import Foundation
import AppKit
import WebKit

extension Notification.Name {
    static let TabsChanged = Notification.Name("Vaaka.TabsChanged")
    static let ActiveTabChanged = Notification.Name("Vaaka.ActiveTabChanged")
}

final class TabManager: NSObject {
    static let shared = TabManager()

    private(set) var tabs: [Tab] = [] {
        didSet { NotificationCenter.default.post(name: .TabsChanged, object: self) }
    }

    private(set) var activeIndex: Int = 0 {
        didSet { NotificationCenter.default.post(name: .ActiveTabChanged, object: self) }
    }

    private let maxTabs = 20

    // Recently closed tabs for potential reopen
    private(set) var recentlyClosed: [ClosedTab] = []

    struct ClosedTab: Codable {
        let url: URL
        let title: String
        let timestamp: Date
    }

    private override init() {
        super.init()
    }

    func createTab(with url: URL? = nil) -> Tab? {
        guard tabs.count < maxTabs else { return nil }

        let config = WKWebViewConfiguration()
        let webpagePreferences = WKWebpagePreferences()
        webpagePreferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = webpagePreferences

        let tab = Tab(configuration: config)
        if let url = url { tab.pendingURL = url }

        tabs.append(tab)
        setActiveTab(index: tabs.count - 1)
        // Load immediately for now
        if let toLoad = tab.pendingURL {
            tab.webView.load(URLRequest(url: toLoad))
            tab.url = toLoad
            tab.pendingURL = nil
        }
        return tab
    }

    func closeTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        let removed = tabs.remove(at: index)
        if let url = removed.url {
            recentlyClosed.insert(ClosedTab(url: url, title: removed.title, timestamp: Date()), at: 0)
            if recentlyClosed.count > 10 { recentlyClosed.removeLast() }
        }
        // adjust active index
        if tabs.isEmpty {
            activeIndex = 0
        } else if index <= activeIndex {
            activeIndex = max(0, activeIndex - 1)
        }
    }

    func setActiveTab(index: Int) {
        guard index >= 0 && index < tabs.count else { return }
        activeIndex = index
        tabs[index].lastActiveTime = Date()
    }

    func indexOf(tab: Tab) -> Int? {
        return tabs.firstIndex { $0.identifier == tab.identifier }
    }

    func reopenLastClosed() -> Tab? {
        guard let closed = recentlyClosed.first else { return nil }
        let tab = createTab(with: closed.url)
        recentlyClosed.removeFirst()
        return tab
    }

    func canCreateTab() -> Bool { tabs.count < maxTabs }
}
