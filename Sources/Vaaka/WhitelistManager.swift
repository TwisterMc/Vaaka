import Foundation

class WhitelistManager {
    static let shared = WhitelistManager()

    private(set) var simpleDomains: [String] = []
    private(set) var regexPatterns: [String] = []
    let builtinOAuth: [String] = [
        "accounts.google.com",
        "login.microsoft.com",
        "login.microsoftonline.com",
        "appleid.apple.com",
        "github.com",
        "facebook.com",
        "twitter.com",
        "linkedin.com"
    ]

    private var fileURL: URL {
        let fm = FileManager.default
        let appSupport = try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let vaakaDir = appSupport.appendingPathComponent("Vaaka", isDirectory: true)
        try? fm.createDirectory(at: vaakaDir, withIntermediateDirectories: true)
        return vaakaDir.appendingPathComponent("whitelist.json")
    }

    func loadWhitelistIfNeeded() {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            loadWhitelist()
        } else {
            // Copy bundled default if possible, otherwise create a minimal default
            if let bundled = Bundle.module.url(forResource: "whitelist", withExtension: "json") {
                try? FileManager.default.copyItem(at: bundled, to: fileURL)
                loadWhitelist()
            } else {
                simpleDomains = ["example.com", "github.com"]
                regexPatterns = []
                saveWhitelist()
            }
        }
    }

    func loadWhitelist() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        struct W: Codable {
            let version: String
            let simple_domains: [String]
            let regex_patterns: [String]
            let builtin_oauth: [String]
        }
        if let w = try? JSONDecoder().decode(W.self, from: data) {
            simpleDomains = w.simple_domains
            regexPatterns = w.regex_patterns
        }
    }

    func saveWhitelist() {
        let obj: [String: Any] = [
            "version": "1.0",
            "simple_domains": simpleDomains,
            "regex_patterns": regexPatterns,
            "builtin_oauth": builtinOAuth
        ]
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]) {
            try? data.write(to: fileURL)
        }
    }

    func addDomain(_ domain: String) {
        guard !simpleDomains.contains(domain) else { return }
        simpleDomains.append(domain)
        saveWhitelist()
        NotificationCenter.default.post(name: Notification.Name("Vaaka.WhitelistChanged"), object: self)
    }

    func removeDomain(_ domain: String) {
        simpleDomains.removeAll { $0 == domain }
        saveWhitelist()
        NotificationCenter.default.post(name: Notification.Name("Vaaka.WhitelistChanged"), object: self)
    }

    func isWhitelisted(url: URL) -> Bool {
        guard let host = url.host else { return false }
        if builtinOAuth.contains(host) { return true }
        for domain in simpleDomains {
            if host == domain || host.hasSuffix("." + domain) { return true }
        }
        let urlString = url.absoluteString
        for pattern in regexPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)) != nil {
                return true
            }
        }
        return false
    }
}
