import Foundation

/// Lightweight in-memory telemetry recorder for navigation events and watchdogs.
/// Records per-site aggregated stats and a short recent-event buffer; persists periodically
/// to Application Support/vaaka_telemetry.json for offline analysis.
final class Telemetry {
    static let shared = Telemetry()

    struct SiteStats: Codable {
        var totalNavigations: Int = 0
        var totalFailures: Int = 0
        var totalDurationMs: Int = 0
        var lastNavigationStart: Date? = nil
        var loadWatchdogFired: Int = 0
        var stuckWatchdogFired: Int = 0
        var finalFallbacks: Int = 0
    }

    struct Event: Codable {
        let timestamp: Date
        let siteId: String
        let type: String
        let info: String?
    }

    private let queue = DispatchQueue(label: "vaaka.telemetry", qos: .utility)
    private var stats: [String: SiteStats] = [:]
    private var recentEvents: [Event] = []
    private var persistTimer: DispatchSourceTimer?
    private let maxEvents = 512

    private init() {
        startPersistTimer()
        loadPersistedIfAny()
    }

    // MARK: - Recording
    func recordNavigationStart(siteId: String, url: URL?) {
        queue.async { [weak self] in
            guard let self = self else { return }
            var s = self.stats[siteId] ?? SiteStats()
            s.lastNavigationStart = Date()
            self.stats[siteId] = s
            self.appendEvent(Event(timestamp: Date(), siteId: siteId, type: "navigation_start", info: url?.absoluteString))
        }
    }

    func recordNavigationFinish(siteId: String, url: URL?) {
        queue.async { [weak self] in
            guard let self = self else { return }
            var s = self.stats[siteId] ?? SiteStats()
            if let start = s.lastNavigationStart {
                let dur = Int(Date().timeIntervalSince(start) * 1000.0)
                s.totalDurationMs += dur
                s.totalNavigations += 1
                s.lastNavigationStart = nil
                self.stats[siteId] = s
                self.appendEvent(Event(timestamp: Date(), siteId: siteId, type: "navigation_finish", info: "url=\(url?.absoluteString ?? "<no-url>") dur_ms=\(dur)"))
            } else {
                // Unknown start; still increment
                s.totalNavigations += 1
                self.stats[siteId] = s
                self.appendEvent(Event(timestamp: Date(), siteId: siteId, type: "navigation_finish_no_start", info: url?.absoluteString))
            }
        }
    }

    func recordNavigationFailure(siteId: String, url: URL?, domain: String?, code: Int, description: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            var s = self.stats[siteId] ?? SiteStats()
            s.totalFailures += 1
            s.lastNavigationStart = nil
            self.stats[siteId] = s
            self.appendEvent(Event(timestamp: Date(), siteId: siteId, type: "navigation_failure", info: "url=\(url?.absoluteString ?? "<no-url>") domain=\(domain ?? "<no-domain>") code=\(code) desc=\(description)"))
        }
    }

    func recordLoadWatchdog(siteId: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            var s = self.stats[siteId] ?? SiteStats()
            s.loadWatchdogFired += 1
            self.stats[siteId] = s
            self.appendEvent(Event(timestamp: Date(), siteId: siteId, type: "load_watchdog", info: nil))
        }
    }

    func recordStuckWatchdog(siteId: String, phase: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            var s = self.stats[siteId] ?? SiteStats()
            s.stuckWatchdogFired += 1
            if phase == "final_fallback" { s.finalFallbacks += 1 }
            self.stats[siteId] = s
            self.appendEvent(Event(timestamp: Date(), siteId: siteId, type: "stuck_watchdog_\(phase)", info: nil))
        }
    }

    func recordExternalOpen(siteId: String, url: URL?) {
        queue.async { [weak self] in
            guard let self = self else { return }
            // Record the external open as an event; do not mutate per-site totals here.
            self.appendEvent(Event(timestamp: Date(), siteId: siteId, type: "external_open", info: url?.absoluteString))
        }
    }

    /// Record a coarse-grained user action taken from UI surfaces (e.g., Retry/Open/Dismiss on error page).
    func recordUserAction(siteId: String, action: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.appendEvent(Event(timestamp: Date(), siteId: siteId, type: "user_action", info: action))
        }
    }

    // MARK: - Helpers
    private func appendEvent(_ e: Event) {
        recentEvents.append(e)
        if recentEvents.count > maxEvents { recentEvents.removeFirst(recentEvents.count - maxEvents) }
    }

    // MARK: - Persistence
    private var persistURL: URL? {
        let fm = FileManager.default
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dir = appSupport.appendingPathComponent("Vaaka", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("telemetry.json")
        }
        return nil
    }

    private func startPersistTimer() {
        persistTimer = DispatchSource.makeTimerSource(queue: queue)
        persistTimer?.schedule(deadline: .now() + 30.0, repeating: 30.0)
        persistTimer?.setEventHandler { [weak self] in self?.persistToDisk() }
        persistTimer?.resume()
    }

    private func persistToDisk() {
        guard let url = persistURL else { return }
        let snapshot = Snapshot(ts: Date(), stats: stats, recentEvents: recentEvents)
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url)
            // Best-effort; no logging to avoid recursion with app logs
        } catch {
            // ignore
        }
    }

    private func loadPersistedIfAny() {
        guard let url = persistURL else { return }
        do {
            let data = try Data(contentsOf: url)
            let snap = try JSONDecoder().decode(Snapshot.self, from: data)
            self.stats = snap.stats
            self.recentEvents = snap.recentEvents
        } catch {
            // ignore failures
        }
    }

    // Expose read-only snapshot for debugging
    func snapshot() -> Snapshot {
        return queue.sync {
            return Snapshot(ts: Date(), stats: stats, recentEvents: recentEvents)
        }
    }

    struct Snapshot: Codable {
        let ts: Date
        let stats: [String: SiteStats]
        let recentEvents: [Event]
    }
}
