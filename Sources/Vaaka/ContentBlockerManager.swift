import Foundation
import WebKit

/// Manages compiling and applying a WKContentRuleList that blocks common trackers/ads.
final class ContentBlockerManager {
    static let shared = ContentBlockerManager()

    private let identifier = "vaaka.blockers"
    private var compiled: WKContentRuleList?

    private init() {
        // kickoff compile if preference says so
        if UserDefaults.standard.bool(forKey: "Vaaka.BlockTrackers") {
            compileIfNeeded()
        }
        // Observe preference changes
        NotificationCenter.default.addObserver(self, selector: #selector(prefsChanged), name: UserDefaults.didChangeNotification, object: nil)
    }

    @objc private func prefsChanged() {
        let enabled = UserDefaults.standard.bool(forKey: "Vaaka.BlockTrackers")
        if enabled {
            compileIfNeeded()
        } else {
            // nothing to do; removed lists will be ignored by WebViews until restart or manual cleanup
        }
    }

    private func compileIfNeeded() {
        if compiled != nil { return }
        let rules = defaultRulesJSON()
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: rules) { [weak self] (list, error) in
            if let err = error {
                DebugLogger.warn("ContentBlocker compile failed: \(err)")
                return
            }
            guard let l = list else { return }
            DebugLogger.info("ContentBlocker compiled: id=\(self?.identifier ?? "<id>")")
            self?.compiled = l
            // Apply to any existing webviews
            DispatchQueue.main.async {
                for tab in SiteTabManager.shared.tabs {
                    tab.webView.configuration.userContentController.add(l)
                }
            }
        }
    }

    func addTo(userContentController: WKUserContentController) {
        if let l = compiled {
            userContentController.add(l)
        } else if UserDefaults.standard.bool(forKey: "Vaaka.BlockTrackers") {
            // kick off compile if not yet compiled
            compileIfNeeded()
        }
    }

    private func defaultRulesJSON() -> String {
        // Minimal, conservative rule-set blocking well-known tracker hostnames and common ad paths.
        // Use a raw string literal to avoid heavy escaping.
        return #"""
        [
          {
            "trigger": { "url-filter": ".*(doubleclick.net|google-analytics.com|googlesyndication.com|facebook.net|facebook.com|adservice.google.com|ads.yahoo.com|adroll.com|segment.io|cdn.ampproject.org).*", "resource-type": ["image","script","xhr","subresource"] },
            "action": { "type": "block" }
          },
          {
            "trigger": { "url-filter": ".*(/ads/|ads/).*", "resource-type": ["image","script","subresource"] },
            "action": { "type": "block" }
          }
        ]
        """#
    }
}
