import AppKit

class PreferencesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let tableView = NSTableView()
    private var tableContainer: NSScrollView!
    // Detail pane references for Settings-style sheet
    private var detailPane: NSView?
    private var generalPane: NSView?
    private var privacyPane: NSView?
    private var appearancePane: NSView?
    private var splitStack: NSStackView?
    // Sidebar source-list
    private var sidebarTable: NSTableView?
    private let sidebarItems = ["General", "Appearance", "Privacy"]
    // Remote update helper UI
    private var remoteStatusLabel: NSTextField?
    private var importEasyButton: NSButton?
    // Last-updated display
    private var lastUpdatedLabel: NSTextField?
    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 640, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings"
        self.init(window: window)
        setupUI()
    }

    override init(window: NSWindow?) {
        super.init(window: window)
        // Observe appearance changes
        NotificationCenter.default.addObserver(self, selector: #selector(appearanceChanged), name: NSNotification.Name("Vaaka.AppearanceChanged"), object: nil)
        // Apply appearance preference
        applyAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupUI() {
        guard let content = window?.contentView else { return }
        content.subviews.forEach { $0.removeFromSuperview() }

        let addButton = NSButton(title: "Add Site", target: self, action: #selector(addSite))
        addButton.bezelStyle = .rounded

        let removeButton = NSButton(title: "Remove Selected", target: self, action: #selector(removeSelected))
        removeButton.bezelStyle = .rounded

        let editButton = NSButton(title: "Edit Selected", target: self, action: #selector(editSelected))
        editButton.bezelStyle = .rounded

        let header = NSTextField(labelWithString: "Sites (Whitelist)")
        header.font = NSFont.boldSystemFont(ofSize: 14)
        header.alignment = .left

        // Only show the site domain column — name is derived automatically from the host
        let urlColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("url"))
        urlColumn.title = "Site"
        urlColumn.width = 600
        tableView.addTableColumn(urlColumn)

        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAutomaticRowHeights = true
        tableView.allowsMultipleSelection = false
        // Support double-click to edit
        tableView.target = self
        tableView.doubleAction = #selector(editSelected)
        // Allow single-click inline editing
        tableView.delegate = self

        tableContainer = NSScrollView()
        tableContainer.documentView = tableView
        tableContainer.hasVerticalScroller = true

        let controls = NSStackView(views: [addButton, editButton, removeButton])
        controls.orientation = .horizontal
        controls.spacing = 8

        // Diagnostics controls (logging level)
        // Hint and warning
        let hintLabel = NSTextField(labelWithString: "Enter domains like apple.com")
        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = NSColor.secondaryLabelColor

        // Privacy controls (block trackers, DNT)
        let blockTrackers = NSButton(checkboxWithTitle: "Block trackers and ads", target: self, action: #selector(toggleBlockTrackers(_:)))
        blockTrackers.state = UserDefaults.standard.bool(forKey: "Vaaka.BlockTrackers") ? .on : .off
        blockTrackers.toolTip = "Block common trackers and ads using a content rule list"

        let sendDNT = NSButton(checkboxWithTitle: "Send 'Do Not Track' header", target: self, action: #selector(toggleSendDNT(_:)))
        sendDNT.state = UserDefaults.standard.bool(forKey: "Vaaka.SendDNT") ? .on : .off
        sendDNT.toolTip = "Send DNT: 1 for top-level page loads when enabled"

        // Warning label (place near bottom)
        let warningLabel = NSTextField(labelWithString: "Note: This app doesn't work with all sites due to their security standards (e.g., Slack).")
        warningLabel.font = NSFont.systemFont(ofSize: 11)
        warningLabel.textColor = NSColor.systemRed
        warningLabel.lineBreakMode = .byWordWrapping
        warningLabel.maximumNumberOfLines = 0

        // Remote update controls for blocker
        // EasyList-only controls
        let importEasy = NSButton(title: "Update Ad-Blocking Rules", target: self, action: #selector(importEasyListPressed))
        importEasy.bezelStyle = .rounded
        importEasy.toolTip = "Fetch EasyList and convert to content-blocker rules"

        // Last-updated label
        let lastUpdatedLabel = NSTextField(labelWithString: "Last updated: " + (ContentBlockerManager.shared.lastUpdatedString() ?? "Never"))
        lastUpdatedLabel.font = NSFont.systemFont(ofSize: 11)
        lastUpdatedLabel.textColor = NSColor.secondaryLabelColor
        lastUpdatedLabel.alignment = .left
        lastUpdatedLabel.translatesAutoresizingMaskIntoConstraints = false

        // Keep references (assigned after statusLabel is created below)
        self.importEasyButton = importEasy
        self.lastUpdatedLabel = lastUpdatedLabel

        // Accessibility
        importEasy.setAccessibilityLabel("Update EasyList now")

        // For layout, select the General pane by default (General will be visible)
        // and ensure import button is enabled/visible based on BlockTrackers pref
        self.importEasyButton?.isEnabled = UserDefaults.standard.bool(forKey: "Vaaka.BlockTrackers")

        // Settings-style UI: Sidebar + Detail panes

        // Sidebar: using a source-list-style NSTableView for accessibility and HIG compliance
        let sidebarContainer = NSScrollView()
        sidebarContainer.hasVerticalScroller = true
        sidebarContainer.translatesAutoresizingMaskIntoConstraints = false
        sidebarContainer.borderType = .noBorder

        let sidebarTable = NSTableView()
        sidebarTable.headerView = nil
        sidebarTable.focusRingType = .none
        sidebarTable.rowHeight = 44
        sidebarTable.intercellSpacing = NSSize(width: 0, height: 4)
        sidebarTable.selectionHighlightStyle = .regular
        sidebarTable.translatesAutoresizingMaskIntoConstraints = false

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebar"))
        col.width = 140
        sidebarTable.addTableColumn(col)

        sidebarContainer.documentView = sidebarTable

        // Keep a reference and set delegate/datasource
        self.sidebarTable = sidebarTable
        sidebarTable.delegate = self
        sidebarTable.dataSource = self
        sidebarTable.target = self
        sidebarTable.action = #selector(sidebarTableClicked(_:))
        sidebarTable.focusRingType = .default
        sidebarTable.setAccessibilityLabel("Settings Sidebar")

        // Select first row by default (General)
        DispatchQueue.main.async { sidebarTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }

        // General pane
        let generalPane = NSView()
        generalPane.translatesAutoresizingMaskIntoConstraints = false
        let sitesStack = NSStackView(views: [header, hintLabel, tableContainer, controls])
        sitesStack.orientation = .vertical
        sitesStack.spacing = 8
        sitesStack.translatesAutoresizingMaskIntoConstraints = false
        generalPane.addSubview(sitesStack)
        NSLayoutConstraint.activate([
            sitesStack.leadingAnchor.constraint(equalTo: generalPane.leadingAnchor, constant: 12),
            sitesStack.trailingAnchor.constraint(equalTo: generalPane.trailingAnchor, constant: -12),
            sitesStack.topAnchor.constraint(equalTo: generalPane.topAnchor, constant: 12),
            sitesStack.bottomAnchor.constraint(equalTo: generalPane.bottomAnchor, constant: -12)
        ])

        // Privacy pane
        let privacyPane = NSView()
        privacyPane.translatesAutoresizingMaskIntoConstraints = false
        let privacyHeader = NSTextField(labelWithString: "Privacy & Blocking")
        privacyHeader.font = NSFont.boldSystemFont(ofSize: 13)
        privacyHeader.textColor = NSColor.labelColor
        privacyHeader.alignment = .left
        // URL row: remote field, copy button, update button and inline status
        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = NSColor.secondaryLabelColor
        statusLabel.alignment = .left
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let urlRow = NSStackView(views: [importEasy, statusLabel, lastUpdatedLabel])
        urlRow.orientation = .horizontal
        urlRow.spacing = 12
        urlRow.alignment = .centerY
        urlRow.translatesAutoresizingMaskIntoConstraints = false
        importEasy.setContentHuggingPriority(.required, for: .horizontal)
        // Keep references
        self.remoteStatusLabel = statusLabel
        // add import button to view hierarchy later (used in layout)
        self.importEasyButton = importEasy
        self.lastUpdatedLabel = lastUpdatedLabel

        // remove deprecated fields
        self.blockerRemoteURLField = nil

        // Accessibility
        // (No custom URL or updateNow — EasyList only)

        let privacyStack = NSStackView(views: [privacyHeader, blockTrackers, sendDNT, urlRow])
        privacyStack.orientation = .vertical
        privacyStack.alignment = .leading
        privacyStack.spacing = 10
        privacyStack.translatesAutoresizingMaskIntoConstraints = false
        privacyPane.addSubview(privacyStack)
        NSLayoutConstraint.activate([
            privacyStack.leadingAnchor.constraint(equalTo: privacyPane.leadingAnchor, constant: 12),
            privacyStack.trailingAnchor.constraint(equalTo: privacyPane.trailingAnchor, constant: -12),
            privacyStack.topAnchor.constraint(equalTo: privacyPane.topAnchor, constant: 12),

            privacyStack.bottomAnchor.constraint(equalTo: privacyPane.bottomAnchor, constant: -12)
        ])

        // Container split: place the sidebar scroll view followed by the detail pane container
        let detailContainer = NSView()
        detailContainer.translatesAutoresizingMaskIntoConstraints = false
        let splitStack = NSStackView(views: [sidebarContainer, detailContainer])
        splitStack.orientation = .horizontal
        splitStack.spacing = 16
        splitStack.alignment = .top
        splitStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(splitStack)

        // Keep references for swapping
        self.splitStack = splitStack

        // Put general pane into the detail container and add privacyPane as hidden child
        // Appearance pane
        let appearancePane = NSView()
        appearancePane.translatesAutoresizingMaskIntoConstraints = false
        let appearanceHeader = NSTextField(labelWithString: "Appearance")
        appearanceHeader.font = NSFont.boldSystemFont(ofSize: 13)
        appearanceHeader.textColor = NSColor.labelColor
        appearanceHeader.alignment = .left

        // Dark mode controls
        let darkModeLabel = NSTextField(labelWithString: "Dark Mode:")
        darkModeLabel.font = NSFont.systemFont(ofSize: 11)
        let darkModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        darkModePopup.addItems(withTitles: ["Light", "Dark", "Match System"])
        let currentDarkMode = AppearanceManager.shared.darkModePreference
        let selectedIndex = currentDarkMode == .light ? 0 : (currentDarkMode == .dark ? 1 : 2)
        darkModePopup.selectItem(at: selectedIndex)
        darkModePopup.target = self
        darkModePopup.action = #selector(darkModeChanged(_:))
        darkModePopup.setAccessibilityLabel("Dark Mode")
        let darkModeRow = NSStackView(views: [darkModeLabel, darkModePopup])
        darkModeRow.orientation = .horizontal
        darkModeRow.spacing = 8
        darkModeRow.alignment = .centerY
        darkModeLabel.setContentHuggingPriority(.required, for: .horizontal)

        // Theme color control
        let useThemeColor = NSButton(checkboxWithTitle: "Use site color", target: self, action: #selector(toggleUseThemeColor(_:)))
        useThemeColor.state = AppearanceManager.shared.useThemeColor ? .on : .off
        useThemeColor.toolTip = "Tint the window and sidebar with the site’s color (from favicon)"

        let appearanceStack = NSStackView(views: [appearanceHeader, darkModeRow, useThemeColor])
        appearanceStack.orientation = .vertical
        appearanceStack.alignment = .leading
        appearanceStack.spacing = 10
        appearanceStack.translatesAutoresizingMaskIntoConstraints = false
        appearancePane.addSubview(appearanceStack)
        NSLayoutConstraint.activate([
            appearanceStack.leadingAnchor.constraint(equalTo: appearancePane.leadingAnchor, constant: 12),
            appearanceStack.trailingAnchor.constraint(equalTo: appearancePane.trailingAnchor, constant: -12),
            appearanceStack.topAnchor.constraint(equalTo: appearancePane.topAnchor, constant: 12),
            appearanceStack.bottomAnchor.constraint(equalTo: appearancePane.bottomAnchor, constant: -12)
        ])

        detailContainer.addSubview(generalPane)
        detailContainer.addSubview(appearancePane)
        detailContainer.addSubview(privacyPane)
        privacyPane.isHidden = true
        appearancePane.isHidden = true
        generalPane.translatesAutoresizingMaskIntoConstraints = false
        appearancePane.translatesAutoresizingMaskIntoConstraints = false
        privacyPane.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            generalPane.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            generalPane.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            generalPane.topAnchor.constraint(equalTo: detailContainer.topAnchor),

            appearancePane.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            appearancePane.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            appearancePane.topAnchor.constraint(equalTo: detailContainer.topAnchor),

            privacyPane.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            privacyPane.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            privacyPane.topAnchor.constraint(equalTo: detailContainer.topAnchor)
        ])

        // Sidebar width
        sidebarContainer.widthAnchor.constraint(equalToConstant: 160).isActive = true
        detailContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 420).isActive = true


        // Warning under split
        warningLabel.stringValue = "Note: Some sites may not work correctly when blocking is enabled (e.g., Slack)."
        warningLabel.font = NSFont.systemFont(ofSize: 11)
        warningLabel.textColor = NSColor.secondaryLabelColor
        warningLabel.alignment = .left
        warningLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(warningLabel)

        NSLayoutConstraint.activate([
            splitStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            splitStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            splitStack.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),

            tableContainer.heightAnchor.constraint(equalToConstant: 220),

            warningLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            warningLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            warningLabel.topAnchor.constraint(equalTo: splitStack.bottomAnchor, constant: 12),
            warningLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])



        // Keep references for swapping
        self.generalPane = generalPane
        self.appearancePane = appearancePane
        self.privacyPane = privacyPane
        self.detailPane = generalPane

        // default to General
        selectPane(.general)

        // local actions and references
        blockTrackers.target = self
        sendDNT.target = self
        importEasy.target = self
        self.importEasyButton = importEasy
    }

    // MARK: - Actions
    @objc private func addSite() {
        // Start inline editing on the trailing add-row instead of opening a modal
        let addRow = SiteManager.shared.sites.count
        tableView.reloadData()
        // Ensure the row exists and start editing the cell
        if addRow >= 0 {
            tableView.editColumn(0, row: addRow, with: nil, select: true)
        }
    }

    @objc private func removeSelected() {
        let selected = tableView.selectedRow
        guard selected >= 0 else { return }
        var s = SiteManager.shared.sites
        s.remove(at: selected)
        SiteManager.shared.replaceSites(s)
        tableView.reloadData()
    }

    @objc private func editSelected() {
        let selected = tableView.selectedRow
        guard selected >= 0 else { return }
        // Always start inline editing (no modal)
        // If the trailing row was selected, it's the add row; otherwise it's an edit of an existing row
        tableView.editColumn(0, row: selected, with: nil, select: true)
    }

    @objc private func toggleBlockTrackers(_ sender: NSButton) {
        let on = sender.state == .on
        UserDefaults.standard.set(on, forKey: "Vaaka.BlockTrackers")
        if on { _ = ContentBlockerManager.shared } // will compile async
        // For immediate effect, compile/apply is handled by the manager via observer
    }

    @objc private func toggleSendDNT(_ sender: NSButton) {
        let on = sender.state == .on
        UserDefaults.standard.set(on, forKey: "Vaaka.SendDNT")
    }

    @objc private func darkModeChanged(_ sender: NSPopUpButton) {
        let selectedIndex = sender.indexOfSelectedItem
        let preference: AppearanceManager.DarkModePreference
        switch selectedIndex {
        case 0:
            preference = .light
        case 1:
            preference = .dark
        default:
            preference = .system
        }
        AppearanceManager.shared.darkModePreference = preference
    }

    @objc private func toggleUseThemeColor(_ sender: NSButton) {
        let on = sender.state == .on
        AppearanceManager.shared.useThemeColor = on
    }



    @objc private func updateBlockerNow() {
        guard let urlStr = blockerRemoteURLField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !urlStr.isEmpty, let url = URL(string: urlStr) else { return }
        UserDefaults.standard.set(urlStr, forKey: "Vaaka.BlockerRemoteURL")
        // Update tooltip for full URL
        blockerRemoteURLField?.toolTip = urlStr
        remoteStatusLabel?.stringValue = "Updating…"
        remoteStatusLabel?.textColor = NSColor.secondaryLabelColor
        ContentBlockerManager.shared.fetchRemoteRules(url: url) { success in
            DispatchQueue.main.async {
                if success {
                    self.remoteStatusLabel?.stringValue = "Updated"
                    self.remoteStatusLabel?.textColor = NSColor.systemGreen
                } else {
                    self.remoteStatusLabel?.stringValue = "Update failed"
                    self.remoteStatusLabel?.textColor = NSColor.systemRed
                }
                // Clear the status after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    self.remoteStatusLabel?.stringValue = ""
                }
            }
        }
    }

    @objc private func importEasyListPressed() {
        // well-known raw EasyList URL in the upstream GitHub
        guard let url = URL(string: "https://raw.githubusercontent.com/easylist/easylist/master/easylist_general_block.txt") else { return }
        remoteStatusLabel?.stringValue = "Importing EasyList…"
        remoteStatusLabel?.textColor = NSColor.secondaryLabelColor
        ContentBlockerManager.shared.fetchAndConvertEasyList(from: url) { success in
            DispatchQueue.main.async {
                if success {
                    self.remoteStatusLabel?.stringValue = "EasyList imported"
                    self.remoteStatusLabel?.textColor = NSColor.systemGreen
                } else {
                    self.remoteStatusLabel?.stringValue = "Import failed"
                    self.remoteStatusLabel?.textColor = NSColor.systemRed
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { self.remoteStatusLabel?.stringValue = "" }
            }
        }
    }

    // MARK: - Settings-style sidebar helpers
    private enum PrefPane { case general, appearance, privacy }

    @objc private func sidebarTableClicked(_ sender: Any?) {
        guard let tv = sidebarTable else { return }
        let row = tv.selectedRow
        if row >= 0 && row < sidebarItems.count {
            switch row {
            case 0: selectPane(.general)
            case 1: selectPane(.appearance)
            default: selectPane(.privacy)
            }
        }
    }

    private func selectPane(_ pane: PrefPane) {
        // Toggle visibility of panes and update sidebar selection
        switch pane {
        case .general:
            generalPane?.isHidden = false
            appearancePane?.isHidden = true
            privacyPane?.isHidden = true
            sidebarTable?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        case .appearance:
            generalPane?.isHidden = true
            appearancePane?.isHidden = false
            privacyPane?.isHidden = true
            sidebarTable?.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        case .privacy:
            generalPane?.isHidden = true
            appearancePane?.isHidden = true
            privacyPane?.isHidden = false
            sidebarTable?.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        }
        switch pane {
        case .general: detailPane = generalPane
        case .appearance: detailPane = appearancePane
        case .privacy: detailPane = privacyPane
        }
    }





    // Allow single-click editing
    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        return tableView == self.tableView
    }

    // Keep text color readable when rows are selected
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTableView else { return }
        if tv == self.tableView {
            let selected = tableView.selectedRow
            for row in 0..<tableView.numberOfRows {
                if let v = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) {
                    // find the text field in the view (could be the cell itself or a container)
                    if let tf = v as? NSTextField {
                        tf.textColor = (row == selected) ? NSColor.selectedTextColor : NSColor.labelColor
                    } else {
                        for sub in v.subviews {
                            if let tf = sub as? NSTextField {
                                tf.textColor = (row == selected) ? NSColor.selectedTextColor : NSColor.labelColor
                            }
                        }
                    }
                }
            }
        } else if tv == self.sidebarTable {
            let row = sidebarTable?.selectedRow ?? -1
            if row == 0 { selectPane(.general) } else if row == 1 { selectPane(.appearance) } else if row == 2 { selectPane(.privacy) }
        }
    }

    // MARK: - Table
    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == self.tableView {
            // Allow an extra blank row for inline 'Add site' edits
            return SiteManager.shared.sites.count + 1
        } else if tableView == self.sidebarTable {
            return sidebarItems.count
        }
        return 0
    }

    // MARK: - Remote blocker helpers (fields)
    private var blockerRemoteURLField: NSTextField? = nil

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let tf = obj.object as? NSTextField else { return }
        let row = tableView.row(for: tf)
        let col = tableView.column(for: tf)
        let sitesCount = SiteManager.shared.sites.count

        func setError(_ message: String?) {
            if let msg = message {
                tf.wantsLayer = true
                tf.layer?.borderColor = NSColor.systemRed.cgColor
                tf.layer?.borderWidth = 1.0
                tf.toolTip = msg
            } else {
                tf.layer?.borderWidth = 0
                tf.toolTip = nil
            }
        }

        // If editing the trailing new-row, treat as Add
        if row == sitesCount {
            let urlStr = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !urlStr.isEmpty else { tf.stringValue = ""; return }
            guard let normalized = SiteManager.normalizedURL(from: urlStr) else {
                setError("Please enter a valid domain or URL (e.g. apple.com or https://apple.com)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { setError(nil); tf.stringValue = "" }
                return
            }
            let host = normalized.host ?? normalized.absoluteString
            let firstLabel = host.split(separator: ".").first.map { String($0).capitalized } ?? host
            var s = SiteManager.shared.sites
            let newSite = Site(id: UUID().uuidString, name: firstLabel, url: normalized, favicon: nil)
            s.append(newSite)
            SiteManager.shared.replaceSites(s)
            tableView.reloadData()
            // Select the newly added row
            if let idx = SiteManager.shared.sites.firstIndex(where: { $0.id == newSite.id }) {
                tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
            }
            return
        }

        // Otherwise editing an existing site
        guard row >= 0, row < SiteManager.shared.sites.count else { return }
        var sites = SiteManager.shared.sites
        let original = sites[row]
        let colId = tableView.tableColumns[col].identifier.rawValue

        // Only url column exists now; validate and update host
        if colId == "url" {
            let urlStr = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !urlStr.isEmpty else {
                setError("Domain cannot be empty")
                tf.stringValue = original.url.host ?? original.url.absoluteString
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { setError(nil) }
                return
            }

            if let normalized = SiteManager.normalizedURL(from: urlStr) {
                // accepted
                setError(nil)
                // Only update if host changed
                if normalized.host != original.url.host {
                    let host = normalized.host ?? normalized.absoluteString
                    let firstLabel = host.split(separator: ".").first.map { String($0).capitalized } ?? host
                    sites[row] = Site(id: original.id, name: firstLabel, url: normalized, favicon: original.favicon)
                    SiteManager.shared.replaceSites(sites)
                    tableView.reloadData()
                } else {
                    tf.stringValue = normalized.host ?? normalized.absoluteString
                }
            } else {
                // invalid
                setError("Please enter a valid domain or URL (e.g. apple.com or https://apple.com)")
                // revert display but keep the error visible briefly
                tf.stringValue = original.url.host ?? original.url.absoluteString
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { setError(nil) }
                return
            }
        }
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let tf = obj.object as? NSTextField else { return }
        // If the remote URL field is focused, expose the full URL as a tooltip and select all text for easy copying
        if tf == blockerRemoteURLField {
            tf.toolTip = tf.stringValue
            tf.currentEditor()?.selectAll(nil)
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView == self.tableView {
            let sites = SiteManager.shared.sites
            // If row is the trailing empty row, show placeholder for adding
            if row >= sites.count {
                let tf = NSTextField(string: "")
                tf.placeholderString = ""
                tf.isBordered = false
                tf.backgroundColor = .clear
                tf.lineBreakMode = .byTruncatingTail
                tf.isEditable = true
                tf.delegate = self
                tf.textColor = NSColor.labelColor
                tf.toolTip = "Enter a domain and press Enter to add"
                return tf
            }

            let site = sites[row]
            // Single column table: show only the host (e.g. apple.com) to the user
            let hostStr = site.url.host ?? site.url.absoluteString
            let tf = NSTextField(string: hostStr)
            tf.isBordered = false
            tf.backgroundColor = .clear
            tf.lineBreakMode = .byTruncatingTail
            tf.isEditable = true
            tf.delegate = self
            tf.textColor = NSColor.labelColor
            tf.toolTip = "Double-click or edit to change domain (e.g. apple.com)"
            return tf
        } else if tableView == self.sidebarTable {
            // Sidebar cell — use a container view to vertically center the label for HIG/accessibility
            let title = sidebarItems[row]
            let container = NSView()
            container.translatesAutoresizingMaskIntoConstraints = false
            let tf = NSTextField(labelWithString: title)
            tf.alignment = .left
            tf.font = NSFont.systemFont(ofSize: 14)
            tf.backgroundColor = .clear
            tf.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(tf)
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
                tf.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
            return container
        }
        return nil
    }

    @objc private func appearanceChanged() {
        applyAppearance()
    }

    private func applyAppearance() {
        guard let win = self.window else { return }
        win.appearance = AppearanceManager.shared.effectiveAppearance
    }
}
