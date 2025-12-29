import Foundation

/// Small logging helper that centralizes leveled logging (trace/debug/info/warn/error).
/// By default only `info`+ are enabled; set `VAAKA_DEBUG=1` to enable `debug`, and `VAAKA_LOG_LEVEL=trace` to enable trace.
final class DebugLogger {
    enum Level: String {
        case trace, debug, info, warn, error
    }

    private static var configuredLevel: Level = {
        let env = ProcessInfo.processInfo.environment
        if let v = env["VAAKA_LOG_LEVEL"]?.lowercased(), let lv = Level(rawValue: v) { return lv }
        if env["VAAKA_DEBUG"] == "1" { return .debug }
        return .info
    }()

    private static func shouldLog(_ level: Level) -> Bool {
        return levelPriority(level) >= levelPriority(configuredLevel)
    }

    private static func levelPriority(_ level: Level) -> Int {
        switch level {
        case .trace: return 4
        case .debug: return 3
        case .info:  return 2
        case .warn:  return 1
        case .error: return 0
        }
    }

    static func trace(_ message: String) {
        if shouldLog(.trace) { print("[TRACE] \(message)") }
    }

    static func debug(_ message: String) {
        if shouldLog(.debug) { print("[DEBUG] \(message)") }
    }

    static func info(_ message: String) {
        if shouldLog(.info) { print("[INFO] \(message)") }
    }

    static func warn(_ message: String) {
        if shouldLog(.warn) { print("[WARN] \(message)") }
    }

    static func error(_ message: String) {
        // Always print errors
        print("[ERROR] \(message)")
    }
}
