import Cocoa
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: BrowserWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load or create whitelist
        WhitelistManager.shared.loadWhitelistIfNeeded()

        // Create main browser window
        windowController = BrowserWindowController()
        windowController?.showWindow(self)

        // Ensure the app is activated and visible
        NSApp.activate(ignoringOtherApps: true)
        windowController?.window?.makeKeyAndOrderFront(nil)

        // Create a minimal app menu so standard actions are available
        createMainMenu()

        // Autosave/cleanup handlers could be added here
    }

    @objc func openPreferences(_ sender: Any?) {
        // Placeholder: show preferences window when implemented
        NSLog("Preferences requested")
    }

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

    func applicationWillTerminate(_ notification: Notification) {
        // Save state on quit (placeholder)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
