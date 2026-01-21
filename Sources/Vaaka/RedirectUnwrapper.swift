import Foundation

/// Utility to detect and unwrap common redirect/wrapper URLs (Gmail, Facebook link shim, Outlook Safe Links, Proofpoint, shorteners, etc.).
/// The function returns a decoded target URL if one can be safely extracted, or the original shortener URL for known shorteners.
enum RedirectUnwrapper {
    private static let hostsWithParams: [String: [String]] = [
        "mail.google.com": ["data-saferedirecturl"],
        "l.facebook.com": ["u", "url"],
        "lm.facebook.com": ["u", "url"],
        "safelinks.protection.outlook.com": ["url"],
        "urldefense.proofpoint.com": ["u", "url"],
        "click.redditmedia.com": ["u", "url"],
    ]

    private static let knownShorteners: Set<String> = [
        "t.co", "lnkd.in", "bit.ly", "goo.gl", "tinyurl.com"
    ]

    /// Attempts to return an unwrapped destination URL if the provided `url` appears to be a wrapper.
    /// Returns `nil` if no unwrapped destination is found.
    static func unwrap(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased() else { return nil }

        // Hosts that encode the destination in a well-known query parameter
        if let params = hostsWithParams[host], let comps = URLComponents(url: url, resolvingAgainstBaseURL: false), let items = comps.queryItems {
            for name in params {
                if let value = items.first(where: { $0.name == name })?.value, !value.isEmpty {
                    if let decoded = decodeSmart(value), let target = URL(string: decoded), let scheme = target.scheme?.lowercased(), (scheme == "http" || scheme == "https") {
                        return target
                    }
                }
            }
            return nil
        }

        // Known shorteners — return the shortener URL itself so callers can open it externally
        if knownShorteners.contains(host) {
            return url
        }

        // Generic fallback: look for common query parameter names
        let commonParams = ["data-saferedirecturl", "url", "u", "redirect", "target", "dest", "q"]
        if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false), let items = comps.queryItems {
            for name in commonParams {
                if let value = items.first(where: { $0.name == name })?.value, !value.isEmpty {
                    if let decoded = decodeSmart(value), let target = URL(string: decoded), let scheme = target.scheme?.lowercased(), (scheme == "http" || scheme == "https") {
                        return target
                    }
                }
            }
        }

        return nil
    }

    private static func decodeSmart(_ s: String) -> String? {
        // Try up to two iterations of percent-decoding to handle double-encoded values.
        var decoded = s
        if let once = decoded.removingPercentEncoding { decoded = once }
        if let twice = decoded.removingPercentEncoding, twice != decoded { decoded = twice }
        // Cap length to avoid pathological inputs
        if decoded.count > 2000 { return nil }
        return decoded
    }
}
