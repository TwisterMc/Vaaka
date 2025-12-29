import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)

// Test hook: if started with `--test-add-site` or `--test-add-site-url <url>`, add a new site shortly after launch to reproduce add-time behaviors.
if CommandLine.arguments.contains("--test-add-site") || CommandLine.arguments.contains("--test-add-site-url") {
    // If a URL argument is provided, use it; otherwise default to Apple for legacy test hook
    var urlStr: String? = nil
    if let idx = CommandLine.arguments.firstIndex(of: "--test-add-site-url"), CommandLine.arguments.count > idx + 1 {
        urlStr = CommandLine.arguments[idx + 1]
    } else if CommandLine.arguments.contains("--test-add-site") {
        urlStr = "https://www.apple.com"
    }
    if let urlStr = urlStr, let url = URL(string: urlStr) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("[DEBUG] Test hook: adding a new site (\(url.absoluteString)) to reproduce add-time behavior")
            let host = url.host ?? "site"
            let name = host.capitalized
            let newSite = Site(id: UUID().uuidString, name: name, url: url, favicon: nil)
            var s = SiteManager.shared.sites
            s.append(newSite)
            SiteManager.shared.replaceSites(s)

            // Optional churn: rapidly call replaceSites a few times to simulate noisy updates
            if CommandLine.arguments.contains("--test-churn-replace-sites") {
                for i in 0..<8 {
                    let delay = 0.05 * Double(i)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.05 + delay) {
                        print("[DEBUG] Test hook: churn replaceSites iteration=\(i)")
                        SiteManager.shared.replaceSites(SiteManager.shared.sites)
                    }
                }
            }
        }
    } else {
        print("[DEBUG] Test hook: no valid URL provided for --test-add-site-url")
    }
}

app.run()
