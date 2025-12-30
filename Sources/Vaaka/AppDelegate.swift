import Cocoa
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: BrowserWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLogger.debug("AppDelegate.applicationDidFinishLaunching start")
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

    // MARK: - Menu actions
    @objc func openPrivacySettings(_ sender: Any?) {
        // Attempt to open System Settings > Privacy & Security. This URL scheme may vary by macOS version.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            if !NSWorkspace.shared.open(url) {
                // fallback: open the System Settings app using the modern API
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.SystemSettings") {
                    let cfg = NSWorkspace.OpenConfiguration()
                    NSWorkspace.shared.openApplication(at: appURL, configuration: cfg) { _, err in
                        if let e = err { DebugLogger.warn("Failed to open System Settings via modern API: \(e)") }
                    }
                } else {
                    DebugLogger.warn("Could not locate System Settings application")
                }
            }
        } else {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.SystemSettings") {
                let cfg = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.openApplication(at: appURL, configuration: cfg) { _, err in
                    if let e = err { DebugLogger.warn("Failed to open System Settings via modern API: \(e)") }
                }
            } else {
                DebugLogger.warn("Could not locate System Settings application")
            }
        }
    }

    @objc func openHelp(_ sender: Any?) {
        if let url = URL(string: "https://example.com/help") { NSWorkspace.shared.open(url) }
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
        appMenu.addItem(withTitle: "Privacy & Security…", action: #selector(openPrivacySettings(_:)), keyEquivalent: "p")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        // File menu (minimal)
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu

        // Edit menu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        // Standard edit actions forwarded to first responder
        editMenu.addItem(withTitle: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(NSMenuItem.separator())
        // Spelling & Grammar submenu - actions go to first responder (NSTextView will respond)
        let spellingItem = NSMenuItem(title: "Spelling and Grammar", action: nil, keyEquivalent: "")
        let spellingSub = NSMenu(title: "Spelling and Grammar")
        spellingSub.addItem(NSMenuItem(title: "Show Spelling and Grammar…", action: NSSelectorFromString("showGuessPanel:"), keyEquivalent: ""))
        spellingSub.addItem(NSMenuItem(title: "Check Document Now", action: NSSelectorFromString("checkSpelling:"), keyEquivalent: ""))
        spellingSub.addItem(NSMenuItem.separator())
        spellingSub.addItem(NSMenuItem(title: "Check Spelling While Typing", action: NSSelectorFromString("toggleContinuousSpellChecking:"), keyEquivalent: ""))
        spellingItem.submenu = spellingSub
        editMenu.addItem(spellingItem)
        editMenuItem.submenu = editMenu

        // Window menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu

        // Help menu
        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "Vaaka Help & Feedback…", action: #selector(openHelp(_:)), keyEquivalent: "?")
        helpMenuItem.submenu = helpMenu

        NSApp.mainMenu = mainMenu
    }

    

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
