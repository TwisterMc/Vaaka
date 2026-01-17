import Foundation

extension Notification.Name {
    static let SitesChanged = Notification.Name("Vaaka.SitesChanged")
    static let FaviconSaved = Notification.Name("Vaaka.FaviconSaved")
}

/// A site configuration for Vaaka. One `Site` maps to exactly one vertical tab.
public struct Site: Codable, Equatable {
    public let id: String
    public let name: String
    public let url: URL
    public let favicon: String? // relative resource name (e.g. "github.svg") or nil

    public init(id: String, name: String, url: URL, favicon: String?) {
        self.id = id
        self.name = name
        self.url = url
        self.favicon = favicon
    }
}

/// Manages the ordered, settings-driven list of Sites. This class strictly reads the
/// bundled `whitelist.json` (or the persisted file) using the new site-based schema
/// and exposes an ordered, immutable list of sites at runtime.
final class SiteManager {
    static let shared = SiteManager()

    private(set) var sites: [Site] = [] {
        didSet { NotificationCenter.default.post(name: .SitesChanged, object: self) }
    }

    private struct FileSchema: Codable {
        let version: String
        let sites: [Site]
    }

    private var fileURL: URL {
        let fm = FileManager.default
        // Prefer the Application Support directory, but fall back to temporary directory if unavailable
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let vaakaDir = appSupport.appendingPathComponent("Vaaka", isDirectory: true)
            try? fm.createDirectory(at: vaakaDir, withIntermediateDirectories: true)
            return vaakaDir.appendingPathComponent("whitelist.json")
        }
        // Fallback
        let tmp = fm.temporaryDirectory
        let vaakaDir = tmp.appendingPathComponent("Vaaka", isDirectory: true)
        try? fm.createDirectory(at: vaakaDir, withIntermediateDirectories: true)
        return vaakaDir.appendingPathComponent("whitelist.json")
    }

    private init() {
        loadSites()
    }

    /// Loads sites from bundled resource `whitelist.json` if no persisted file exists, otherwise from persisted file.
    /// This method strictly expects the new `sites` schema and will silently fail (no fallback) if the schema is invalid.
    func loadSites() {
        let decoder = JSONDecoder()
        // Prefer persisted file in App Support; if missing, load bundled resource and persist it (first-run behavior)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                let schema = try decoder.decode(FileSchema.self, from: data)
                sites = schema.sites
            } catch {
                sites = []
            }
        } else {
            do {
                // Prefer main bundle Resources
                var bundledURL: URL? = Bundle.main.url(forResource: "whitelist", withExtension: "json")
                // Fallback to SwiftPM bundle inside app Resources (without touching Bundle.module)
                if bundledURL == nil, let base = Bundle.main.resourceURL {
                    let candidate = base.appendingPathComponent("Vaaka_Vaaka.bundle").appendingPathComponent("whitelist.json")
                    if FileManager.default.fileExists(atPath: candidate.path) { bundledURL = candidate }
                }
                guard let bundled = bundledURL else { sites = []; return }
                let data = try Data(contentsOf: bundled)
                let schema = try decoder.decode(FileSchema.self, from: data)
                sites = schema.sites
                // Persist the bundled version for future launches
                try? data.write(to: fileURL)
            } catch {
                sites = []
            }
        }

        if sites.isEmpty {
            if let appleURL = URL(string: "https://apple.com") {
                let s = Site(id: "apple-default", name: "Apple", url: appleURL, favicon: nil)
                sites = [s]
                // Persist the seeded list so users can modify it later
                let encoder = JSONEncoder()
                let schema = FileSchema(version: "1.0", sites: sites)
                if let data = try? encoder.encode(schema) { try? data.write(to: fileURL) }
            }
        }
    }

    /// Normalize a host for domain-based matching (strip leading 'www.' and lowercase).
    static func canonicalHost(_ host: String?) -> String? {
        guard var h = host?.lowercased() else { return nil }
        if h.hasPrefix("www.") { h = String(h.dropFirst(4)) }
        return h
    }

    /// Return a best-effort registrable/root domain for a host string. This is a heuristic
    /// that works for common cases: it returns the last two labels (eg. "google.com")
    /// but will include an extra label for common country-code TLDs (eg. "co.uk" -> take last 3 labels).
    static func rootDomain(for host: String?) -> String? {
        guard let canonical = canonicalHost(host) else { return nil }
        let parts = canonical.split(separator: ".")
        if parts.count <= 2 { return canonical }
        // If a likely ccTLD (two-letter last label), include one more label (e.g., example.co.uk -> example.co.uk)
        if let last = parts.last, last.count == 2, parts.count >= 3 {
            return parts.suffix(3).joined(separator: ".")
        }
        return parts.suffix(2).joined(separator: ".")
    }

    /// Returns true if `host` belongs to `siteHost` domain (ex: sub.example.com matches example.com).
    ///
    /// Enhanced behavior: if a site was configured as a specific subdomain (eg. "mail.google.com"),
    /// we still want other registrable subdomains of the same root (eg. "accounts.google.com") to be
    /// considered allowed. To support that without changing the stored site URL, we also compare
    /// against the site's root domain when checking matches.
    static func hostMatches(host: String?, siteHost: String?) -> Bool {
        guard let h = canonicalHost(host), let s = canonicalHost(siteHost) else { return false }
        // Direct match or subdomain of siteHost
        if h == s { return true }
        if h.hasSuffix("." + s) { return true }
        // Also allow matches against the site's root domain (eg. siteHost "mail.google.com" -> root "google.com")
        if let siteRoot = rootDomain(for: s) {
            if h == siteRoot { return true }
            if h.hasSuffix("." + siteRoot) { return true }
        }
        return false
    }

    /// Check if given URL is allowed by any configured site (domain-based, subdomains allowed).
    func isWhitelisted(url: URL) -> Bool {
        guard let host = url.host else { return false }
        for site in sites {
            if SiteManager.hostMatches(host: host, siteHost: site.url.host) { return true }
        }
        return false
    }

    /// Returns the Site that owns the given URL, or nil. Matching is domain-based.
    func site(for url: URL) -> Site? {
        guard let host = url.host else { return nil }
        return sites.first { site in
            return SiteManager.hostMatches(host: host, siteHost: site.url.host)
        }
    }

    // MARK: - Validation helpers for user input

    /// Normalize a user-provided domain or URL (e.g. "example.com" or "https://example.com") into a `URL` if valid. Returns nil if invalid.
    static func normalizedURL(from input: String) -> URL? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        // Try raw parse first
        if let u = URL(string: s), let host = u.host, !host.isEmpty {
            // ensure host contains a dot (simple heuristic) to avoid accidental local strings
            if host.contains(".") { return u }
        }
        // If no scheme present, try https://<input>
        if let pref = URL(string: "https://\(s)"), let host = pref.host, host.contains(".") {
            return pref
        }
        return nil
    }

    /// Lightweight validation for domain-like strings acceptable to the user (matches the behavior of normalizedURL).
    static func isValidDomainInput(_ input: String) -> Bool {
        return normalizedURL(from: input) != nil
    }

    /// Replace the sites array with a new ordered array and persist. (Used by Settings only.)
    func replaceSites(_ newSites: [Site]) {
        // Deduplicate sites by canonical host, preserving first occurrence and original order.
        var seenHosts: Set<String> = []
        var uniqueSites: [Site] = []
        for site in newSites {
            if let host = SiteManager.canonicalHost(site.url.host) {
                if seenHosts.contains(host) {
                    continue
                }
                seenHosts.insert(host)
                uniqueSites.append(site)
            } else {
                // If host normalization fails, keep the site to avoid accidental data loss
                uniqueSites.append(site)
            }
        }

        let encoder = JSONEncoder()
        let schema = FileSchema(version: "1.0", sites: uniqueSites)
        if let data = try? encoder.encode(schema) {
            try? data.write(to: fileURL)
            sites = uniqueSites

            // After persisting, attempt to fetch missing favicons asynchronously
            fetchMissingFaviconsIfNeeded(for: uniqueSites)
        }
    }

    private var fetchingSiteIDs: Set<String> = []
    private let lastFaviconRefreshKey = "Vaaka.LastFaviconRefresh"
    private let faviconRefreshIntervalSeconds: TimeInterval = 86400 * 7  // 7 days

    private func fetchMissingFaviconsIfNeeded(for newSites: [Site]) {
        for site in newSites where site.favicon == nil {
            guard !fetchingSiteIDs.contains(site.id) else { continue }
            fetchingSiteIDs.insert(site.id)

            FaviconFetcher.shared.fetchFavicon(for: site.url) { img in
                defer { self.fetchingSiteIDs.remove(site.id) }
                guard let img = img else {
                    return
                }
                if let filename = FaviconFetcher.shared.saveImage(img, forSiteID: site.id) {
                    DispatchQueue.main.async {
                        var s = self.sites
                        if let idx = s.firstIndex(where: { $0.id == site.id }) {
                            // Only update if changed
                            if s[idx].favicon != filename {
                                s[idx] = Site(id: s[idx].id, name: s[idx].name, url: s[idx].url, favicon: filename)
                                // Persist the updated list (this will not re-trigger fetch for the same site since favicon is set)
                                self.replaceSites(s)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Refresh favicons for all sites if enough time has passed since last refresh
    func refreshFaviconsIfNeeded() {
        let lastRefresh = UserDefaults.standard.double(forKey: lastFaviconRefreshKey)
        let now = Date().timeIntervalSince1970
        
        // Only refresh if 7 days have passed since last refresh
        if lastRefresh == 0 || (now - lastRefresh) >= faviconRefreshIntervalSeconds {
            refreshAllFavicons()
        }
    }

    /// Force refresh favicons for all sites
    func refreshAllFavicons() {
        for site in sites {
            guard !fetchingSiteIDs.contains(site.id) else { continue }
            fetchingSiteIDs.insert(site.id)

            FaviconFetcher.shared.fetchFavicon(for: site.url) { img in
                defer { self.fetchingSiteIDs.remove(site.id) }
                guard let img = img else {
                    return
                }
                if let filename = FaviconFetcher.shared.saveImage(img, forSiteID: site.id) {
                    DispatchQueue.main.async {
                        var s = self.sites
                        if let idx = s.firstIndex(where: { $0.id == site.id }) {
                            // Update even if the filename is the same (forces re-fetch)
                            s[idx] = Site(id: s[idx].id, name: s[idx].name, url: s[idx].url, favicon: filename)
                            self.replaceSites(s)
                        }
                    }
                }
            }
        }
        
        // Update last refresh time
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastFaviconRefreshKey)
    }
}
