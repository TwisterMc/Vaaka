import Foundation
import AppKit

extension Notification.Name {
    static let LogUpdated = Notification.Name("Vaaka.LogUpdated")
}

final class Logger {
    static let shared = Logger()

    private let queue = DispatchQueue(label: "vaaka.logger", qos: .utility)
    private var buffer: [String] = []
    private let maxBuffer = 500

    private init() {
        // Ensure log directory exists and touch the log file so `tail` can find it immediately
        do {
            let dir = logFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // Touch file if missing
            if !FileManager.default.fileExists(atPath: logFileURL.path) {
                try Data().write(to: logFileURL, options: .atomic)
            }
            // Small initial banner (also push into the in-memory buffer and notify listeners)
            let bannerLine = "[DEBUG] Vaaka log started - \(iso8601Date())"
            if let data = (bannerLine + "\n").data(using: .utf8) {
                try data.write(to: logFileURL, options: .atomic)
            }
            // Keep banner in the recent buffer and notify observers so open Dev Log isn't empty
            queue.async {
                self.buffer.append(bannerLine)
                NotificationCenter.default.post(name: .LogUpdated, object: bannerLine)
            }
        } catch {
            // best-effort only
            Swift.print("[WARN] Logger: failed to create log directory or file: \(error)")
        }
    }

    var logFileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Logs/Vaaka.log")
    }

    func log(_ message: String) {
        let line = "\(iso8601Date()) \(message)"
        queue.async {
            self.buffer.append(line)
            if self.buffer.count > self.maxBuffer { self.buffer.removeFirst(self.buffer.count - self.maxBuffer) }

            // Append to file
            do {
                let data = (line + "\n").data(using: .utf8)!
                if FileManager.default.fileExists(atPath: self.logFileURL.path) {
                    let fh = try FileHandle(forWritingTo: self.logFileURL)
                    defer { try? fh.close() }
                    try fh.seekToEnd()
                    try fh.write(contentsOf: data)
                } else {
                    try data.write(to: self.logFileURL, options: .atomic)
                }
            } catch {
                Swift.print("[WARN] Logger: failed to write log: \(error)")
            }

            NotificationCenter.default.post(name: .LogUpdated, object: line)
        }
    }

    func debug(_ message: String) {
        Swift.print(message)
        log(message)
    }

    func recentLogs() -> [String] {
        return queue.sync { buffer }
    }

    func clear() {
        queue.async {
            self.buffer.removeAll()
            do {
                try Data().write(to: self.logFileURL, options: .atomic)
            } catch {
                Swift.print("[WARN] Logger: failed to clear log file: \(error)")
            }
            NotificationCenter.default.post(name: .LogUpdated, object: "__CLEARED__")
        }
    }

    private func iso8601Date() -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt.string(from: Date())
    }
}
