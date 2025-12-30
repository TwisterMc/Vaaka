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
        // Load any locally persisted rules (from remote updates) preferentially
        if let local = loadPersistedRules() {
            WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: local) { [weak self] (list, error) in
                if let err = error {
                    DebugLogger.warn("ContentBlocker compile from persisted rules failed: \(err) — falling back to builtin rules")
                    // Fall back to builtin rules
                    self?.compileBuiltin()
                    return
                }
                guard let l = list else { self?.compileBuiltin(); return }
                DebugLogger.info("ContentBlocker compiled from persisted rules")
                self?.compiled = l
                DispatchQueue.main.async { self?.applyToExistingTabs(l) }
            }
            return
        }
        compileBuiltin()
    }

    private func compileBuiltin() {
        let rules = defaultRulesJSON()
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: rules) { [weak self] (list, error) in
            if let err = error {
                DebugLogger.warn("ContentBlocker compile failed: \(err)")
                return
            }
            guard let l = list else { return }
            DebugLogger.info("ContentBlocker compiled: id=\(self?.identifier ?? "<id>") (built-in)")
            self?.compiled = l
            DispatchQueue.main.async { self?.applyToExistingTabs(l) }
        }
    }

    private func applyToExistingTabs(_ l: WKContentRuleList) {
        for tab in SiteTabManager.shared.tabs {
            tab.webView.configuration.userContentController.add(l)
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

    // MARK: - Remote update support
    /// If the user enables auto-updates and provides a URL, fetch rules and persist locally.
    func updateRulesFromRemoteIfNeeded() {
        guard UserDefaults.standard.bool(forKey: "Vaaka.BlockerAutoUpdate") else { return }
        guard let urlStr = UserDefaults.standard.string(forKey: "Vaaka.BlockerRemoteURL"), let url = URL(string: urlStr) else { return }
        fetchRemoteRules(url: url) { success in
            DebugLogger.info("ContentBlocker remote update completed success=\(success)")
        }
    }

    func fetchRemoteRules(url: URL, completion: @escaping (Bool) -> Void) {
        let req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        let t = URLSession.shared.dataTask(with: req) { data, resp, err in
            if let e = err { DebugLogger.warn("ContentBlocker remote fetch failed: \(e)"); completion(false); return }
            guard let d = data, let s = String(data: d, encoding: .utf8) else { DebugLogger.warn("ContentBlocker remote fetch: invalid data"); completion(false); return }
            // Basic validation: must decode as JSON array and contain objects with trigger/action
            if (try? JSONSerialization.jsonObject(with: d)) == nil {
                DebugLogger.warn("ContentBlocker remote fetch: JSON validation failed")
                completion(false); return
            }
            // Persist the fetched rules and schedule compile
            if self.persistRules(s) {
                DispatchQueue.main.async { self.compiled = nil; self.compileIfNeeded(); completion(true) }
            } else { completion(false) }
        }
        t.resume()
    }

    private func persistRules(_ rules: String) -> Bool {
        guard let url = persistURLForRules() else { return false }
        do { try rules.write(to: url, atomically: true, encoding: .utf8); return true } catch { DebugLogger.warn("Failed to persist blocker rules: \(error)"); return false }
    }

    private func loadPersistedRules() -> String? {
        guard let url = persistURLForRules() else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func persistURLForRules() -> URL? {
        let fm = FileManager.default
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dir = appSupport.appendingPathComponent("Vaaka", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("blocker_rules.json")
        }
        return nil
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
