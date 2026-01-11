import Foundation
import WebKit
import AppKit

/// Extracts and manages theme-color meta tag from web pages.
final class ThemeColorExtractor {
    static let shared = ThemeColorExtractor()

    private let cache = NSCache<NSString, NSColor>()

    /// Extract theme-color from the loaded page's HTML.
    func extractThemeColor(from webView: WKWebView, completion: @escaping (NSColor?) -> Void) {
        let js = """
        (function() {
            const meta = document.querySelector('meta[name="theme-color"]');
            if (!meta) return null;
            return meta.getAttribute('content');
        })();
        """
        webView.evaluateJavaScript(js) { result, error in
            guard let colorString = result as? String, !colorString.isEmpty else {
                completion(nil)
                return
            }
            let color = NSColor(hexString: colorString)
            completion(color)
        }
    }

    /// Cache a theme-color for a given site ID.
    func cacheColor(_ color: NSColor, forSiteID id: String) {
        cache.setObject(color, forKey: id as NSString)
    }

    /// Retrieve a cached theme-color by site ID.
    func cachedColor(forSiteID id: String) -> NSColor? {
        cache.object(forKey: id as NSString)
    }

    private init() {}
}

extension NSColor {
    /// Initialize NSColor from a hex string (e.g., "#FF5733" or "rgb(255, 87, 51)").
    convenience init?(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: .whitespaces).lowercased()

        // Try hex format: #RGB, #RRGGBB, #RRGGBBAA
        if cleaned.hasPrefix("#") {
            let hex = String(cleaned.dropFirst())
            if let value = UInt64(hex, radix: 16), (hex.count == 6 || hex.count == 8) {
                let r, g, b, a: CGFloat
                if hex.count == 6 {
                    r = CGFloat((value >> 16) & 0xFF) / 255.0
                    g = CGFloat((value >> 8) & 0xFF) / 255.0
                    b = CGFloat(value & 0xFF) / 255.0
                    a = 1.0
                } else { // 8 digits: RRGGBBAA
                    r = CGFloat((value >> 24) & 0xFF) / 255.0
                    g = CGFloat((value >> 16) & 0xFF) / 255.0
                    b = CGFloat((value >> 8) & 0xFF) / 255.0
                    a = CGFloat(value & 0xFF) / 255.0
                }
                self.init(red: r, green: g, blue: b, alpha: a)
                return
            }
        }

        // Try rgb/rgba format: rgb(255, 87, 51) or rgba(255, 87, 51, 0.8)
        if cleaned.hasPrefix("rgb") {
            let pattern = "rgba?\\((\\d+),\\s*(\\d+),\\s*(\\d+)(?:,\\s*([\\d.]+))?\\)"
            let regex = try? NSRegularExpression(pattern: pattern)
            let nsStr = cleaned as NSString
            if let match = regex?.firstMatch(in: cleaned, range: NSRange(location: 0, length: nsStr.length)) {
                if match.numberOfRanges >= 4 {
                    let r = CGFloat(Int(nsStr.substring(with: match.range(at: 1))) ?? 0) / 255.0
                    let g = CGFloat(Int(nsStr.substring(with: match.range(at: 2))) ?? 0) / 255.0
                    let b = CGFloat(Int(nsStr.substring(with: match.range(at: 3))) ?? 0) / 255.0
                    let a = match.numberOfRanges > 4 ? CGFloat(Double(nsStr.substring(with: match.range(at: 4))) ?? 1.0) : 1.0
                    self.init(red: r, green: g, blue: b, alpha: a)
                    return
                }
            }
        }

        return nil
    }
}
