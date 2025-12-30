import AppKit

class PreferencesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let tableView = NSTableView()
    private var tableContainer: NSScrollView!

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 640, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Preferences"
        self.init(window: window)
        setupUI()
    }

    override init(window: NSWindow?) {
        super.init(window: window)
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

        // Place the privacy controls and list
        let stack = NSStackView(views: [header, hintLabel, blockTrackers, sendDNT, tableContainer, controls, warningLabel])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            tableContainer.heightAnchor.constraint(equalToConstant: 240)
        ])

        // local actions
        blockTrackers.target = self
        sendDNT.target = self
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

    // Allow single-click editing
    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        return true
    }

    // Keep text color readable when rows are selected
    func tableViewSelectionDidChange(_ notification: Notification) {
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
    }

    // MARK: - Table
    func numberOfRows(in tableView: NSTableView) -> Int {
        // Allow an extra blank row for inline 'Add site' edits
        return SiteManager.shared.sites.count + 1
    }

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

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let sites = SiteManager.shared.sites
        // If row is the trailing empty row, show placeholder for adding
        if row >= sites.count {
            let tf = NSTextField(string: "")
            // No placeholder per UX request — trailing add-row is blank
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
    }
}
