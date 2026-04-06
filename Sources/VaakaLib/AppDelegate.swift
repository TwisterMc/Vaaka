import Cocoa
import WebKit

public class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: BrowserWindowController?
    private var preferencesWindowController: PreferencesWindowController?
    private let session = SessionManager()

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        SiteManager.shared.loadSites()

        Logger.shared.debug("[DEBUG] Vaaka starting - PID=\(ProcessInfo.processInfo.processIdentifier) bundleId=\(Bundle.main.bundleIdentifier ?? "<nil>")")

        SiteManager.shared.refreshFaviconsIfNeeded()

        windowController = BrowserWindowController()
        session.restore(to: windowController?.window)

        createMainMenu()

        windowController?.showWindow(self)
        NSApp.activate()
        windowController?.window?.makeKeyAndOrderFront(nil)

        // Silently check for updates on launch — only alerts if a newer version exists.
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            UpdateChecker.shared.checkForUpdates(silentIfCurrent: true)
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        session.save(window: windowController?.window)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // MARK: - Menu actions

    @objc func checkForUpdates(_ sender: Any?) {
        UpdateChecker.shared.checkForUpdates(silentIfCurrent: false)
    }

    @objc func showAboutPanel(_ sender: Any?) {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: AppVersion.name,
            .applicationVersion: AppVersion.version,
            .version: AppVersion.build,
        ]
        let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns")
            ?? Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        if let url = iconURL, let icon = NSImage(contentsOf: url) {
            options[.applicationIcon] = icon
        }
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    @objc func openHelp(_ sender: Any?) {
        if let url = URL(string: "https://github.com/TwisterMc/Vaaka") { NSWorkspace.shared.open(url) }
    }

    @objc func openDonate(_ sender: Any?) {
        if let url = URL(string: "https://ko-fi.com/twistermc") { NSWorkspace.shared.open(url) }
    }

    @objc func openPreferences(_ sender: Any?) {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController()
        }
        preferencesWindowController?.showWindow(self)
        NSApp.activate()
    }

    // MARK: - Menu construction

    private func createMainMenu() {
        let mainMenu = NSMenu()
        mainMenu.addItem(makeAppMenuItem())
        mainMenu.addItem(makeFileMenuItem())
        mainMenu.addItem(makeEditMenuItem())
        mainMenu.addItem(makeWindowMenuItem())
        mainMenu.addItem(makeHelpMenuItem())
        NSApp.mainMenu = mainMenu
    }

    private func makeAppMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu()
        menu.addItem(withTitle: "About \(AppVersion.name)", action: #selector(showAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Preferences...", action: #selector(openPreferences(_:)), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Donate", action: #selector(openDonate(_:)), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit \(AppVersion.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = menu
        return item
    }

    private func makeFileMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "File")
        menu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        item.submenu = menu
        return item
    }

    private func makeEditMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Edit")

        menu.addItem(withTitle: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        menu.addItem(withTitle: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "Z")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(NSMenuItem.separator())

        let spellingItem = NSMenuItem(title: "Spelling and Grammar", action: nil, keyEquivalent: "")
        let spellingSub = NSMenu(title: "Spelling and Grammar")
        spellingSub.addItem(NSMenuItem(title: "Show Spelling and Grammar…", action: NSSelectorFromString("showGuessPanel:"), keyEquivalent: ""))
        spellingSub.addItem(NSMenuItem(title: "Check Document Now", action: NSSelectorFromString("checkSpelling:"), keyEquivalent: ""))
        spellingSub.addItem(NSMenuItem.separator())
        spellingSub.addItem(NSMenuItem(title: "Check Spelling While Typing", action: NSSelectorFromString("toggleContinuousSpellChecking:"), keyEquivalent: ""))
        spellingItem.submenu = spellingSub
        menu.addItem(spellingItem)
        menu.addItem(NSMenuItem.separator())

        let findItem = NSMenuItem(title: "Find in Page…", action: #selector(BrowserWindowController.performFind(_:)), keyEquivalent: "f")
        findItem.keyEquivalentModifierMask = [.command]
        menu.addItem(findItem)

        let findNextItem = NSMenuItem(title: "Find Next", action: #selector(BrowserWindowController.performFindNextAction(_:)), keyEquivalent: "g")
        findNextItem.keyEquivalentModifierMask = [.command]
        menu.addItem(findNextItem)

        let findPrevItem = NSMenuItem(title: "Find Previous", action: #selector(BrowserWindowController.performFindPreviousAction(_:)), keyEquivalent: "g")
        findPrevItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(findPrevItem)

        item.submenu = menu
        return item
    }

    private func makeWindowMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")

        let tabOverviewItem = NSMenuItem(title: "Tab Overview", action: #selector(BrowserWindowController.tabOverviewClicked(_:)), keyEquivalent: "t")
        tabOverviewItem.keyEquivalentModifierMask = [.command]
        menu.addItem(tabOverviewItem)

        menu.addItem(NSMenuItem.separator())
        for i in 1...9 {
            let tabItem = NSMenuItem(title: "Select Tab \(i)", action: #selector(BrowserWindowController.selectTabMenuItem(_:)), keyEquivalent: "\(i)")
            tabItem.keyEquivalentModifierMask = [.command]
            tabItem.tag = i - 1
            menu.addItem(tabItem)
        }

        item.submenu = menu
        return item
    }

    private func makeHelpMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Help")
        menu.addItem(withTitle: "Vaaka Help & Feedback…", action: #selector(openHelp(_:)), keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
