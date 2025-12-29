import Cocoa
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: BrowserWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[DEBUG] AppDelegate.applicationDidFinishLaunching start")
        // Ensure sites are loaded from settings (bundled or persisted)
        SiteManager.shared.loadSites()

        // Create main browser window
        windowController = BrowserWindowController()
        // Restore frame before showing the window so it appears with the correct size
        restoreSession()
        windowController?.showWindow(self)

        // Ensure the app is activated and visible
        NSApp.activate(ignoringOtherApps: true)
        windowController?.window?.makeKeyAndOrderFront(nil)

        print("[DEBUG] Vaaka launched: window frame=\(windowController?.window?.frame ?? .zero)")
        vaakaLog("Launched; window frame=\(windowController?.window?.frame ?? .zero)")

        // Create a minimal app menu so standard actions are available
        createMainMenu()

        // Log final launched frame
        print("[DEBUG] Vaaka launched: window frame=\(windowController?.window?.frame ?? .zero)")
        vaakaLog("Launched; window frame=\(windowController?.window?.frame ?? .zero)")
    }

    private func sessionFileURL() -> URL? {
        let fm = FileManager.default
        if let appSupport = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            let dir = appSupport.appendingPathComponent("Vaaka", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("session.json")
        }
        return nil
    }

    private func saveSession() {
        guard let wc = windowController else { return }
        var session: [String: Any] = [:]
        // window frame
        if let w = wc.window {
            session["frame"] = NSStringFromRect(w.frame)
        }

        if let file = sessionFileURL() {
            if let data = try? JSONSerialization.data(withJSONObject: session, options: [.prettyPrinted]) {
                try? data.write(to: file)
            }
        }
    }

    private func restoreSession() {
        guard let wc = windowController else { return }
        guard let file = sessionFileURL(), FileManager.default.fileExists(atPath: file.path) else { return }
        guard let data = try? Data(contentsOf: file), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let frameStr = obj["frame"] as? String {
            var rect = NSRectFromString(frameStr)
            // Enforce sensible minimums so a corrupt/small saved frame can't make the window unusable
            let minW: CGFloat = wc.window?.minSize.width ?? 800
            let minH: CGFloat = wc.window?.minSize.height ?? 400
            if rect.size.width < minW { rect.size.width = minW }
            if rect.size.height < minH { rect.size.height = minH }
            wc.window?.setFrame(rect, display: false)
            vaakaLog("Restored window frame (clamped if needed)=\(rect)")
        }

        // SiteTabManager already restores site tabs and active site
    }
        // Autosave/cleanup handlers could be added here

    func applicationWillTerminate(_ notification: Notification) {
        saveSession()
    }

    @objc func openPreferences(_ sender: Any?) {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController()
        }
        preferencesWindowController?.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var preferencesWindowController: PreferencesWindowController?


    private func createMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        let appName = ProcessInfo.processInfo.processName
        appMenu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Preferences...", action: #selector(openPreferences(_:)), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        NSApp.mainMenu = mainMenu
    }

    

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
