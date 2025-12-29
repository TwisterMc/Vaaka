import Foundation

/// Lightweight heuristics to detect SSO/OAuth IdP navigation targets.
/// Conservative by default: relies on a small list of known IdP hostnames and URL patterns.
struct SSODetector {
    private static let knownIdPHosts: [String] = [
        "okta.com",
        "auth0.com",
        "login.microsoftonline.com",
        "accounts.google.com",
        "appleid.apple.com",
        "identity.azure.com",
        "sso.mycompany.com" // example placeholder
    ]

    private static let knownIdPHostSuffixes: [String] = [
        ".okta.com",
        ".auth0.com",
        ".login.microsoftonline.com"
    ]

    /// Returns true if the URL looks like an IdP/SSO endpoint based on host or known query/path patterns.
    static func isSSO(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }

        // Exact host matches
        for h in knownIdPHosts {
            if host == h { return true }
        }
        // Suffix matches (e.g. subdomains)
        for s in knownIdPHostSuffixes {
            if host.hasSuffix(s) { return true }
        }

        // URL parameter heuristics commonly seen in OAuth/SAML flows
        if let q = url.query?.lowercased() {
            if q.contains("samlrequest") || q.contains("samlresponse") || q.contains("relaystate") || q.contains("response_type=") || q.contains("client_id=") || q.contains("redirect_uri=") || q.contains("id_token=") {
                return true
            }
        }

        // Path heuristics
        let path = url.path.lowercased()
        if path.contains("/saml") || path.contains("/oauth") || path.contains("/auth") || path.contains("/signin") || path.contains("/login") {
            return true
        }

        return false
    }
}
