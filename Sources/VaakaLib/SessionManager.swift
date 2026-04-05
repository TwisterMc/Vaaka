import Cocoa

class SessionManager {
    private struct SessionData: Codable {
        var frameX: Double
        var frameY: Double
        var frameWidth: Double
        var frameHeight: Double
    }

    private func sessionFileURL() -> URL? {
        let fm = FileManager.default
        guard let appSupport = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else { return nil }
        let dir = appSupport.appendingPathComponent("Vaaka", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("session.json")
    }

    func save(window: NSWindow?) {
        guard let frame = window?.frame, let file = sessionFileURL() else { return }
        let session = SessionData(frameX: frame.origin.x, frameY: frame.origin.y,
                                  frameWidth: frame.size.width, frameHeight: frame.size.height)
        DispatchQueue.global(qos: .utility).async {
            do {
                let data = try JSONEncoder().encode(session)
                try data.write(to: file, options: .atomic)
            } catch {
                Logger.shared.debug("[DEBUG] Session save failed: \(error)")
            }
        }
    }

    func restore(to window: NSWindow?) {
        guard let window, let file = sessionFileURL() else { return }
        guard FileManager.default.fileExists(atPath: file.path),
              let data = try? Data(contentsOf: file),
              let session = try? JSONDecoder().decode(SessionData.self, from: data) else { return }

        var rect = NSRect(x: session.frameX, y: session.frameY,
                          width: session.frameWidth, height: session.frameHeight)
        let minSize = window.minSize
        rect.size.width = max(rect.size.width, minSize.width > 0 ? minSize.width : 800)
        rect.size.height = max(rect.size.height, minSize.height > 0 ? minSize.height : 400)
        window.setFrame(rect, display: false)
    }
}
