import Cocoa

class UpdateChecker {
    static let shared = UpdateChecker()
    private let releasesURL = URL(string: "https://api.github.com/repos/TwisterMc/Vaaka/releases?per_page=1")!
    private let releasesPageURL = URL(string: "https://github.com/TwisterMc/Vaaka/releases")!

    private init() {}

    func checkForUpdates(silentIfCurrent: Bool = false) {
        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("\(AppVersion.name)/\(AppVersion.version)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            if let error {
                Logger.shared.debug("[UpdateChecker] Network error: \(error.localizedDescription)")
                if !silentIfCurrent {
                    DispatchQueue.main.async { self.showError(detail: error.localizedDescription) }
                }
                return
            }

            guard let data else {
                if !silentIfCurrent {
                    DispatchQueue.main.async { self.showError(detail: "No data received.") }
                }
                return
            }

            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let body = String(data: data, encoding: .utf8) ?? ""
                Logger.shared.debug("[UpdateChecker] HTTP \(http.statusCode): \(body)")
                if http.statusCode == 404 {
                    // No published releases yet — not an error worth surfacing
                    if !silentIfCurrent {
                        DispatchQueue.main.async { self.showNoReleases() }
                    }
                } else if !silentIfCurrent {
                    DispatchQueue.main.async { self.showError(detail: "HTTP \(http.statusCode)") }
                }
                return
            }

            guard
                let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else {
                let body = String(data: data, encoding: .utf8) ?? ""
                Logger.shared.debug("[UpdateChecker] Unexpected response: \(body)")
                if !silentIfCurrent {
                    DispatchQueue.main.async { self.showError(detail: "Unexpected response from GitHub.") }
                }
                return
            }

            guard let tagName = releases.first?["tag_name"] as? String else {
                // Empty releases list
                if !silentIfCurrent {
                    DispatchQueue.main.async { self.showNoReleases() }
                }
                return
            }

            let latestVersion = tagName.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("v")
                ? String(tagName.dropFirst())
                : tagName

            DispatchQueue.main.async {
                self.presentResult(latestVersion: latestVersion, silentIfCurrent: silentIfCurrent)
            }
        }.resume()
    }

    private func presentResult(latestVersion: String, silentIfCurrent: Bool) {
        let current = AppVersion.version

        if isNewerVersion(latestVersion, than: current) {
            let alert = NSAlert()
            alert.messageText = "Update Available"
            alert.informativeText = "A new version of \(AppVersion.name) is available: \(latestVersion)\n\nYou're currently running version \(current)."
            alert.addButton(withTitle: "View Release")
            alert.addButton(withTitle: "Not Now")
            alert.alertStyle = .informational
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(releasesPageURL)
            }
        } else if !silentIfCurrent {
            let alert = NSAlert()
            alert.messageText = "\(AppVersion.name) is Up to Date"
            alert.informativeText = "You're running the latest version (\(current))."
            alert.addButton(withTitle: "OK")
            alert.alertStyle = .informational
            alert.runModal()
        }
    }

    private func showNoReleases() {
        let alert = NSAlert()
        alert.messageText = "No Releases Found"
        alert.informativeText = "There are no published releases for \(AppVersion.name) yet."
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .informational
        alert.runModal()
    }

    private func showError(detail: String = "") {
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = "Could not reach GitHub to check for updates. Please try again later."
            + (detail.isEmpty ? "" : "\n\n(\(detail))")
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .warning
        alert.runModal()
    }

    /// Returns true if `candidate` is strictly newer than `current` using semantic versioning.
    private func isNewerVersion(_ candidate: String, than current: String) -> Bool {
        let lhs = versionComponents(candidate)
        let rhs = versionComponents(current)
        let maxLen = max(lhs.count, rhs.count)
        for i in 0..<maxLen {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    private func versionComponents(_ version: String) -> [Int] {
        version.split(separator: ".").compactMap { Int($0) }
    }
}
