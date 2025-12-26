import Cocoa
import WebKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: BrowserWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load or create whitelist
        WhitelistManager.shared.loadWhitelistIfNeeded()

        // Create main browser window
        windowController = BrowserWindowController()
        windowController?.showWindow(self)

        // Autosave/cleanup handlers could be added here
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Save state on quit (placeholder)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
