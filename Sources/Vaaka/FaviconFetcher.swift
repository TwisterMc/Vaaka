import Foundation
import AppKit
import ImageIO

class FaviconFetcher {
    static let shared = FaviconFetcher()

    private let session: URLSession

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    // NOTE: The spec requires that favicons are fetched and managed in Settings
    // (not at runtime from WebViews). This method remains available for Settings
    // code to optionally fetch icons, but Browser UI should use image(forResource:)
    // or generateMonoIcon(...) instead of calling this during normal page loads.
    func fetchFavicon(for url: URL, completion: @escaping (NSImage?) -> Void) {
        guard let host = url.host else { completion(nil); return }
        // First try to discover icons from the page's HTML (link rel icons), then fallback to common /favicon.ico paths.
        discoverIconCandidates(baseURL: url) { candidates in
            var urls = candidates
            // Append well-known fallbacks
            urls.append(URL(string: "https://\(host)/favicon.ico")!)
            urls.append(URL(string: "https://www.\(host)/favicon.ico")!)
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
        let task = session.dataTask(with: req) { data, resp, err in
            if let d = data, let img = NSImage(data: d) {
                completion(img)
            } else {
                remaining.removeFirst()
                self.fetchFromCandidateURLs(remaining, completion: completion)
            }
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
        // Very small, pragmatic HTML parsing via regex to extract <link rel="...icon..." href="..."> candidates.
        // This avoids adding a heavy HTML parser dependency for a simple use case.
        var results: [URL] = []
        let pattern = "<link[^>]+rel=[\'\"]?([^\"'>]+)[\"']?[^>]*href=[\'\"]([^\"'>]+)[\"']?[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length))
        for m in matches {
            if m.numberOfRanges >= 3 {
                let rel = ns.substring(with: m.range(at: 1)).lowercased()
                let href = ns.substring(with: m.range(at: 2))
                if rel.contains("icon") || rel.contains("shortcut") || rel.contains("apple-touch-icon") {
                    if let resolved = URL(string: href, relativeTo: baseURL)?.absoluteURL {
                        results.append(resolved)
                    }
                }
            }
        }
        // Deduplicate, preserving order
        var seen = Set<String>()
        results = results.filter { url in
            let s = url.absoluteString
            if seen.contains(s) { return false }
            seen.insert(s)
            return true
        }
        return results
    }

    // Directory where saved favicons are stored (Application Support/Vaaka/favicons)
    private var faviconsDir: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let d = appSupport.appendingPathComponent("Vaaka/favicons", isDirectory: true)
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    // Load a bundled or cached resource image by resource name (e.g., "github.svg" or "site.png").
    func image(forResource name: String) -> NSImage? {
        // Try asset in app bundle first
        if let img = NSImage(named: NSImage.Name(name)) { return img }
        // Fallback to looking in module resources
        if let url = Bundle.module.url(forResource: name, withExtension: nil), let data = try? Data(contentsOf: url), let img = NSImage(data: data) { return img }
        // Finally, check on-disk saved favicons
        let file = faviconsDir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let data = try Data(contentsOf: file)
                if let img = NSImage(data: data) {
                    return img
                } else {
                    // Try a more robust decode via ImageIO
                    if let src = CGImageSourceCreateWithData(data as CFData, nil), let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                        DebugLogger.debug("image(forResource): fallback CGImage decode succeeded for \(file.path) size=\(data.count)")
                        return img
                    }
                    DebugLogger.warn("image(forResource): failed to decode image at path=\(file.path) size=\(try? FileManager.default.attributesOfItem(atPath: file.path)[.size] ?? 0)")
                }
            } catch {
                DebugLogger.warn("image(forResource): failed to read file at path=\(file.path): \(error)")
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
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let data = rep.representation(using: .png, properties: [:]) else { DebugLogger.warn("saveImage: unable to convert image to PNG for site=\(siteID)"); return nil }
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
                    DebugLogger.warn("saveImage: decoded image check failed for site=\(siteID)")
                    return nil
                }
            }
            // Move into place (atomic)
            try FileManager.default.moveItem(at: temp, to: final)
            // Log size
            let size = (try? FileManager.default.attributesOfItem(atPath: final.path)[.size]) as? UInt64 ?? 0
            print("[DEBUG] saveImage: wrote favicon for site=\(siteID) path=\(final.path) size=\(size)")
            return fname
        } catch {
            print("[DEBUG] Failed to save favicon for \(siteID): \(error)")
            try? FileManager.default.removeItem(at: temp)
            return nil
        }
    }
    // Generate a simple mono icon with the first character of the canonical host (strip www.)
    func generateMonoIcon(for host: String) -> NSImage? {
        let canonical = SiteManager.canonicalHost(host) ?? host.lowercased()
        let letter = canonical.first.map { String($0).uppercased() } ?? "?"
        DebugLogger.debug("generateMonoIcon: host=\(host) canonical=\(canonical) letter=\(letter)")
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
