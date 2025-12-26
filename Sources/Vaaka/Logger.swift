import Foundation

func vaakaLog(_ message: String) {
    let s = "[Vaaka] \(ISO8601DateFormatter().string(from: Date())) - \(message)\n"
    let url = URL(fileURLWithPath: "/tmp/vaaka_debug.log")
    if let data = s.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: url.path) {
            if let fh = try? FileHandle(forWritingTo: url) {
                fh.seekToEndOfFile()
                fh.write(data)
                try? fh.close()
            }
        } else {
            try? data.write(to: url)
        }
    }
}
