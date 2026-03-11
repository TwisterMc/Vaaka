import Foundation

/// Canonical User-Agent string we use for network requests and WebViews to appear like Safari.
/// Keep this single source of truth so tests and network code can assert consistency.
struct UserAgent {
    static let safari = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15"
}
