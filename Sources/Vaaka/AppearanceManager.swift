import Foundation
import AppKit

/// Manages appearance preferences: dark mode and theme-color support.
final class AppearanceManager {
    static let shared = AppearanceManager()

    enum DarkModePreference: String, Codable {
        case light = "light"
        case dark = "dark"
        case system = "system"
    }

    private let darkModeKey = "Vaaka.DarkModePreference"
    private let themeColorKey = "Vaaka.UseThemeColor"

    var darkModePreference: DarkModePreference {
        get {
            let raw = UserDefaults.standard.string(forKey: darkModeKey) ?? DarkModePreference.system.rawValue
            return DarkModePreference(rawValue: raw) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: darkModeKey)
            NotificationCenter.default.post(name: NSNotification.Name("Vaaka.AppearanceChanged"), object: nil)
        }
    }

    var useThemeColor: Bool {
        get { UserDefaults.standard.bool(forKey: themeColorKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: themeColorKey)
            NotificationCenter.default.post(name: NSNotification.Name("Vaaka.AppearanceChanged"), object: nil)
        }
    }

    /// Determine the effective appearance based on the preference and system setting.
    var effectiveAppearance: NSAppearance {
        switch darkModePreference {
        case .light:
            return NSAppearance(named: .aqua) ?? NSApp.effectiveAppearance
        case .dark:
            return NSAppearance(named: .darkAqua) ?? NSApp.effectiveAppearance
        case .system:
            return NSApp.effectiveAppearance
        }
    }

    /// CSS media query for prefers-color-scheme based on the effective appearance.
    var preferredColorSchemeCSSMedia: String {
        switch darkModePreference {
        case .light:
            return "(prefers-color-scheme: light)"
        case .dark:
            return "(prefers-color-scheme: dark)"
        case .system:
            // Use the current system setting
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? "(prefers-color-scheme: dark)" : "(prefers-color-scheme: light)"
        }
    }

    private init() {}
}
