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

        // If EasyList has never been fetched, import it on first launch
        if UserDefaults.standard.string(forKey: "Vaaka.BlockerEasyListLastUpdated") == nil {
            let easyURL = URL(string: "https://raw.githubusercontent.com/easylist/easylist/master/easylist_general_block.txt")!
            fetchAndConvertEasyList(from: easyURL) { success in
                if success { self.updateLastUpdated(Date()) }
            }
        }
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
                if error != nil {
                    self?.compileBuiltin()
                    return
                }
                guard let l = list else { self?.compileBuiltin(); return }
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
            guard let l = list else { return }
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
        // Auto-update removed: EasyList is fetched on first launch and via the UI button only.
    }

    func fetchRemoteRules(url: URL, completion: @escaping (Bool) -> Void) {
        let req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        let t = URLSession.shared.dataTask(with: req) { data, resp, err in
            guard err == nil else { completion(false); return }
            guard let d = data, let s = String(data: d, encoding: .utf8) else { completion(false); return }
            guard (try? JSONSerialization.jsonObject(with: d)) != nil else { completion(false); return }
            // Persist the fetched rules and schedule compile
            if self.persistRules(s) {
                DispatchQueue.main.async { self.compiled = nil; self.compileIfNeeded(); completion(true) }
            } else { completion(false) }
        }
        t.resume()
    }

    // MARK: - EasyList (ABP) support
    /// Fetch an ABP-format filter list (eg. EasyList) and convert it to a WK Content Rule List JSON, persist, and compile.
    func fetchAndConvertEasyList(from url: URL, completion: @escaping (Bool) -> Void) {
        let req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        let t = URLSession.shared.dataTask(with: req) { data, resp, err in
            guard err == nil else { completion(false); return }
            guard let d = data, let s = String(data: d, encoding: .utf8) else { completion(false); return }
            let json = self.convertABPToContentRules(abp: s)
            guard json.count > 0 else { completion(false); return }
            if self.persistRules(json) {
                // record last-updated
                self.updateLastUpdated(Date())
                DispatchQueue.main.async { self.compiled = nil; self.compileIfNeeded(); completion(true) }
            } else { completion(false) }
        }
        t.resume()
    }

    private func convertABPToContentRules(abp: String) -> String {
        var rules: [[String: Any]] = []
        let lines = abp.components(separatedBy: .newlines)
        for raw in lines {
            var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("!") { continue } // comment
            if line.hasPrefix("@@") { continue } // exception rule - skip
            // split modifiers
            var modifiersPart: String? = nil
            if let idx = line.firstIndex(of: "$") {
                modifiersPart = String(line[line.index(after: idx)...])
                line = String(line[..<idx])
            }
            // simple domain anchor rules
            var urlFilter: String? = nil
            var resourceTypes: [String]? = nil
            // Parse modifiers into resource types
            if let mods = modifiersPart {
                let comps = mods.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                var types: [String] = []
                for c in comps {
                    if c == "script" { types.append("script") }
                    else if c == "image" { types.append("image") }
                    else if c == "stylesheet" { types.append("style-sheet") }
                    else if c == "xmlhttprequest" || c == "xhr" { types.append("xmlhttprequest") }
                    else if c == "object" { types.append("object") }
                }
                if !types.isEmpty { resourceTypes = types }
            }
            // Handle rules starting with || (domain)
            if line.hasPrefix("||") {
                var domain = String(line.dropFirst(2))
                if domain.hasSuffix("^") { domain.removeLast() }
                let esc = NSRegularExpression.escapedPattern(for: domain)
                urlFilter = ".*" + esc + ".*"
            } else if line.hasPrefix("|") {
                // starts with | anchor - treat as starts-with
                let pat = String(line.dropFirst())
                if pat.hasPrefix("http") {
                    let esc = NSRegularExpression.escapedPattern(for: pat)
                    urlFilter = ".*" + esc + ".*"
                } else {
                    let esc = NSRegularExpression.escapedPattern(for: pat)
                    urlFilter = ".*" + esc + ".*"
                }
            } else if line.hasPrefix("/") && line.hasSuffix("/") {
                // regex rule
                let regexBody = String(line.dropFirst().dropLast())
                urlFilter = regexBody
            } else if line.contains("*") || line.contains("/") {
                // wildcard/path rule: translate * -> .*
                var pat = NSRegularExpression.escapedPattern(for: line)
                pat = pat.replacingOccurrences(of: "\\*", with: ".*")
                urlFilter = ".*" + pat + ".*"
            } else {
                // fallback: treat as domain substring
                let esc = NSRegularExpression.escapedPattern(for: line)
                urlFilter = ".*" + esc + ".*"
            }
            if let uf = urlFilter {
                var trigger: [String: Any] = ["url-filter": uf]
                if let rt = resourceTypes { trigger["resource-type"] = rt }
                let action: [String: Any] = ["type": "block"]
                let rule: [String: Any] = ["trigger": trigger, "action": action]
                rules.append(rule)
            }
        }
        // Serialize to JSON
        if let d = try? JSONSerialization.data(withJSONObject: rules, options: [.prettyPrinted]), let s = String(data: d, encoding: .utf8) {
            return s
        }
        return ""
    }

    private func persistRules(_ rules: String) -> Bool {
        guard let url = persistURLForRules() else { return false }
        do { try rules.write(to: url, atomically: true, encoding: .utf8); return true } catch { return false }
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

    // MARK: - Last-updated helpers
    private func updateLastUpdated(_ date: Date) {
        let iso = ISO8601DateFormatter().string(from: date)
        UserDefaults.standard.set(iso, forKey: "Vaaka.BlockerEasyListLastUpdated")
    }

    func lastUpdatedString() -> String? {
        guard let iso = UserDefaults.standard.string(forKey: "Vaaka.BlockerEasyListLastUpdated") else { return nil }
        if let d = ISO8601DateFormatter().date(from: iso) {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            return df.string(from: d)
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
