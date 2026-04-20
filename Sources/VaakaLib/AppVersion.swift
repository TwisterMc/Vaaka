import Foundation

enum AppVersion {
    static let name = "Vaaka"
    static let version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    static let build: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
}
