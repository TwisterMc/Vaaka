import Foundation
import AppKit
import ImageIO

class FaviconFetcher {
    static let shared = FaviconFetcher()

    private let session: URLSession
    private let cache = NSCache<NSString, NSImage>()

    init(session: URLSession? = nil) {
        if let s = session {
            self.session = s
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 20
            config.httpMaximumConnectionsPerHost = 4
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.urlCache = nil
            self.session = URLSession(configuration: config)
        }
    }

    // NOTE: The spec requires that favicons are fetched and managed in Settings
    // (not at runtime from WebViews). This method remains available for Settings
    // code to optionally fetch icons, but Browser UI should use image(forResource:)
    // or generateMonoIcon(...) instead of calling this during normal page loads.
    func fetchFavicon(for url: URL, completion: @escaping (NSImage?) -> Void) {
        guard let host = url.host else { completion(nil); return }
        // First try to discover icons from the page's HTML (link rel icons and manifest.json), then fallback to common /favicon.ico paths.
        discoverIconCandidates(baseURL: url) { candidates in
            var urls = candidates
            
            // Determine if we should try www-prefixed versions
            let wwwHost = host.hasPrefix("www.") ? nil : "www.\(host)"
            
            // Append well-known fallback paths, prioritizing larger sizes
            urls.append(URL(string: "https://\(host)/apple-touch-icon.png")!)
            if let wHost = wwwHost {
                urls.append(URL(string: "https://\(wHost)/apple-touch-icon.png")!)
            }
            urls.append(URL(string: "https://\(host)/apple-touch-icon-precomposed.png")!)
            if let wHost = wwwHost {
                urls.append(URL(string: "https://\(wHost)/apple-touch-icon-precomposed.png")!)
            }
            
            urls.append(URL(string: "https://\(host)/favicon.ico")!)
            if let wHost = wwwHost {
                urls.append(URL(string: "https://\(wHost)/favicon.ico")!)
            }
            
            self.fetchFromCandidateURLs(urls, completion: completion)
        }
    }

    private func fetchFromCandidateURLs(_ urls: [URL], completion: @escaping (NSImage?) -> Void) {
        var remaining = urls
        guard let first = remaining.first else { completion(nil); return }
        var req = URLRequest(url: first)
        // Send a Safari-like User-Agent and accept images
        req.setValue(UserAgent.safari, forHTTPHeaderField: "User-Agent")
        req.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 5.0  // Add timeout to avoid hanging
        let task = session.dataTask(with: req) { data, resp, err in
            if let d = data, let img = NSImage(data: d) {
                // Prefer larger icons (64x64+) for Retina displays, minimum 32x32
                let size = img.size
                let minSize: CGFloat = 64  // Prefer 2x size for crisp display on Retina
                
                // Accept this image if it meets minimum quality
                if size.width >= minSize && size.height >= minSize {
                    completion(img)
                    return
                }
                // If smaller than preferred but >= 32x32, continue searching but keep as fallback
                if size.width >= 32 && size.height >= 32 {
                    // Check if there are more candidates - if not, use this one
                    if remaining.count <= 1 {
                        completion(img)
                        return
                    }
                }
            }
            remaining.removeFirst()
            self.fetchFromCandidateURLs(remaining, completion: completion)
        }
        task.resume()
    }

    /// Parse the HTML at baseURL and return an ordered list of candidate absolute URLs pointing to potential favicon images.
    private func discoverIconCandidates(baseURL: URL, completion: @escaping ([URL]) -> Void) {
        var req = URLRequest(url: baseURL)
        req.httpMethod = "GET"
        req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        // Make requests appear like Safari to improve discovery on some sites
        req.setValue(UserAgent.safari, forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: req) { data, resp, err in
            guard let data = data, let html = String(data: data, encoding: .utf8) else { completion([]); return }
            let candidates = self.parseIconLinks(fromHTML: html, baseURL: baseURL)
            completion(candidates)
        }
        task.resume()
    }

    private func parseIconLinks(fromHTML html: String, baseURL: URL) -> [URL] {
        // Extract <link> tags for icons and prioritize by size/type, also check manifest.json
        var results: [(url: URL, priority: Int)] = []
        
        // Match <link ...> tags
        let pattern = "<link[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length))
        
        var manifestURL: URL?
        
        for match in matches {
            let linkTag = ns.substring(with: match.range)
            
            // Check for manifest link first
            guard linkTag.lowercased().contains("rel=") else { continue }
            let relPattern = "rel=[\'\"]?([^\"'>]+)[\"']?"
            guard let relRegex = try? NSRegularExpression(pattern: relPattern, options: [.caseInsensitive]),
                  let relMatch = relRegex.firstMatch(in: linkTag, options: [], range: NSRange(location: 0, length: linkTag.count)) else { continue }
            
            let relRange = relMatch.range(at: 1)
            let rel = (linkTag as NSString).substring(with: relRange).lowercased()
            
            if rel.contains("manifest") {
                let hrefPattern = "href=[\'\"]?([^\"'>]+)[\"']?"
                guard let hrefRegex = try? NSRegularExpression(pattern: hrefPattern, options: [.caseInsensitive]),
                      let hrefMatch = hrefRegex.firstMatch(in: linkTag, options: [], range: NSRange(location: 0, length: linkTag.count)) else { continue }
                let hrefRange = hrefMatch.range(at: 1)
                let href = (linkTag as NSString).substring(with: hrefRange)
                if let resolved = URL(string: href, relativeTo: baseURL)?.absoluteURL {
                    manifestURL = resolved
                }
                continue
            }
            
            // Check if this is an icon link
            if !rel.contains("icon") && !rel.contains("shortcut") && !rel.contains("apple") {
                continue
            }
            
            // Extract href
            let hrefPattern = "href=[\'\"]?([^\"'>]+)[\"']?"
            guard let hrefRegex = try? NSRegularExpression(pattern: hrefPattern, options: [.caseInsensitive]),
                  let hrefMatch = hrefRegex.firstMatch(in: linkTag, options: [], range: NSRange(location: 0, length: linkTag.count)) else { continue }
            
            let hrefRange = hrefMatch.range(at: 1)
            let href = (linkTag as NSString).substring(with: hrefRange)
            
            guard let resolved = URL(string: href, relativeTo: baseURL)?.absoluteURL else { continue }
            
            // Prioritize by type: SVG > PNG/JPG > ICO
            var priority = 0
            let lowerHref = href.lowercased()
            
            if lowerHref.contains(".svg") {
                priority = 400
            } else if lowerHref.contains(".png") || lowerHref.contains(".jpg") || lowerHref.contains(".jpeg") {
                priority = 200
            } else if lowerHref.contains(".ico") {
                priority = 100
            }
            
            // Apple touch icons get a small boost
            if rel.contains("apple") {
                priority += 10
            }
            
            results.append((url: resolved, priority: priority))
        }
        
        // If a manifest was found, fetch and parse it for icons (site owner curated, get +50 boost)
        if let manifestURL = manifestURL {
            if let icons = extractIconsFromManifest(manifestURL: manifestURL, baseURL: baseURL) {
                for icon in icons {
                    let iconUrl = icon.absoluteString.lowercased()
                    let basePriority: Int
                    if iconUrl.contains(".svg") {
                        basePriority = 400
                    } else if iconUrl.contains(".png") || iconUrl.contains(".jpg") || iconUrl.contains(".jpeg") {
                        basePriority = 200
                    } else {
                        basePriority = 100
                    }
                    results.append((url: icon, priority: basePriority + 50))
                }
            }
        }
        
        // Sort by priority descending, deduplicate, and return URLs
        results.sort { $0.priority > $1.priority }
        var seen = Set<String>()
        var finalURLs: [URL] = []
        for (url, _) in results {
            let s = url.absoluteString
            if !seen.contains(s) {
                seen.insert(s)
                finalURLs.append(url)
            }
        }
        return finalURLs
    }

    private func extractIconsFromManifest(manifestURL: URL, baseURL: URL) -> [URL]? {
        var icons: [URL] = []
        var req = URLRequest(url: manifestURL)
        req.setValue(UserAgent.safari, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 5.0
        
        let semaphore = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: req) { data, resp, err in
            defer { semaphore.signal() }
            guard let data = data else { return }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let iconsArray = json["icons"] as? [[String: Any]] {
                    for iconObj in iconsArray {
                        if let iconSrc = iconObj["src"] as? String {
                            if let resolved = URL(string: iconSrc, relativeTo: baseURL)?.absoluteURL {
                                icons.append(resolved)
                            }
                        }
                    }
                }
            } catch {
                // Failed to parse manifest JSON
            }
        }
        task.resume()
        
        // Wait up to 3 seconds for manifest fetch
        let result = semaphore.wait(timeout: .now() + 3.0)
        return result == .timedOut ? nil : (icons.isEmpty ? nil : icons)
    }

    // Directory where saved favicons are stored (Application Support/Vaaka/favicons)
    internal var faviconsDir: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let d = appSupport.appendingPathComponent("Vaaka/favicons", isDirectory: true)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    // Load a bundled or cached resource image by resource name (e.g., "github.svg" or "site.png").
    func image(forResource name: String) -> NSImage? {
        if let cached = cache.object(forKey: name as NSString) {
            return cached
        }
          // Try asset in app bundle first
          if let img = NSImage(named: NSImage.Name(name)) {
              cache.setObject(img, forKey: name as NSString)
              return img
          }
          if let url = Bundle.main.url(forResource: name, withExtension: nil),
              let data = try? Data(contentsOf: url),
              let img = NSImage(data: data) {
              cache.setObject(img, forKey: name as NSString)
              return img
          }
        // Fallback to looking in SwiftPM module resources without touching Bundle.module
        if let base = Bundle.main.resourceURL {
            let modFile = base.appendingPathComponent("Vaaka_Vaaka.bundle").appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: modFile.path),
               let data = try? Data(contentsOf: modFile),
               let img = NSImage(data: data) {
                cache.setObject(img, forKey: name as NSString)
                return img
            }
        }
        // Finally, check on-disk saved favicons
        let file = faviconsDir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let data = try Data(contentsOf: file)
                if let img = NSImage(data: data) {
                    cache.setObject(img, forKey: name as NSString)
                    return img
                } else {
                    // Try a more robust decode via ImageIO
                    if let src = CGImageSourceCreateWithData(data as CFData, nil), let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                        cache.setObject(img, forKey: name as NSString)
                        return img
                    }
                }
            } catch {
                // Failed to read file
            }
        }
        return nil
    }

    /// Returns true if the named resource exists on disk within the favicons directory
    func resourceExistsOnDisk(_ name: String) -> Bool {
        let file = faviconsDir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: file.path)
    }
    /// Save an image for a given site ID to the favicons directory and return its filename (e.g., "<siteid>.png")
    func saveImage(_ image: NSImage, forSiteID siteID: String) -> String? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let data = rep.representation(using: .png, properties: [:]) else { return nil }
        let fname = "\(siteID).png"
        let final = faviconsDir.appendingPathComponent(fname)
        let temp = faviconsDir.appendingPathComponent("\(fname).tmp")
        do {
            // Write atomically to a temp file first
            try data.write(to: temp, options: .atomic)
            // Verify we can decode it before replacing
            if NSImage(data: data) == nil {
                // Try decode via ImageIO
                if let src = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(src) > 0 {
                    // ok
                } else {
                    try? FileManager.default.removeItem(at: temp)
                    return nil
                }
            }
            // Move into place (atomic)
            try FileManager.default.moveItem(at: temp, to: final)
            // Update cache with the newly saved image
            if let savedImage = NSImage(data: data) {
                cache.setObject(savedImage, forKey: fname as NSString)
            }
            // Notify listeners that a favicon was saved for this site so UI can update immediately
            NotificationCenter.default.post(name: .FaviconSaved, object: nil, userInfo: ["siteId": siteID, "filename": fname])
            return fname
        } catch {
            try? FileManager.default.removeItem(at: temp)
            return nil
        }
    }
    /// Load favicon from disk, or fetch from web if not found on disk
    /// This is more resilient to permission issues since it falls back to fetching
    func imageOrFetchFromWeb(forResource name: String, url: URL, completion: @escaping (NSImage?) -> Void) {
        // First try to load from disk
        if let img = image(forResource: name) {
            completion(img)
            return
        }
        
        // Fall back to fetching from web
        fetchFavicon(for: url) { img in
            if let img = img {
                // Cache in memory even if we couldn't save to disk
                self.cache.setObject(img, forKey: name as NSString)
            }
            completion(img)
        }
    }

    // Generate a simple mono icon with the first character of the canonical host (strip www.)
    func generateMonoIcon(for host: String) -> NSImage? {
        let canonical = SiteManager.canonicalHost(host) ?? host.lowercased()
        let letter = canonical.first.map { String($0).uppercased() } ?? "?"
        let size = NSSize(width: 28, height: 28)
        let img = NSImage(size: size)
        img.lockFocus()
        let bg = NSColor.controlBackgroundColor
        bg.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.systemFont(ofSize: 16, weight: .bold)
        ]
        let s = NSString(string: letter)
        let textSize = s.size(withAttributes: attrs)
        let rect = NSRect(x: (size.width - textSize.width)/2, y: (size.height - textSize.height)/2, width: textSize.width, height: textSize.height)
        s.draw(in: rect, withAttributes: attrs)
        img.unlockFocus()
        return img
    }
}
