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

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Name"
        nameColumn.width = 240
        tableView.addTableColumn(nameColumn)

        let urlColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("url"))
        urlColumn.title = "Start URL"
        urlColumn.width = 360
        tableView.addTableColumn(urlColumn)

        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAutomaticRowHeights = true
        tableView.allowsMultipleSelection = false
        // Support double-click to edit
        tableView.target = self
        tableView.doubleAction = #selector(editSelected)

        tableContainer = NSScrollView()
        tableContainer.documentView = tableView
        tableContainer.hasVerticalScroller = true

        let controls = NSStackView(views: [addButton, editButton, removeButton])
        controls.orientation = .horizontal
        controls.spacing = 8

        let stack = NSStackView(views: [header, tableContainer, controls])
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
    }

    // MARK: - Actions
    @objc private func addSite() {
        let alert = NSAlert()
        alert.messageText = "Add Site"
        alert.informativeText = "Provide a name and start URL (e.g., https://example.com):"

        let nameField = NSTextField(frame: NSRect(x: 0, y: 44, width: 420, height: 24))
        nameField.placeholderString = "Site Name"
        let urlField = NSTextField(frame: NSRect(x: 0, y: 12, width: 420, height: 24))
        urlField.placeholderString = "https://example.com"

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 72))
        container.addSubview(nameField)
        container.addSubview(urlField)

        alert.accessoryView = container
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let res = alert.runModal()
        if res == .alertFirstButtonReturn {
            let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            var urlStr = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !urlStr.isEmpty else {
                let a = NSAlert()
                a.messageText = "Invalid input"
                a.informativeText = "Name and domain are required."
                a.runModal()
                return
            }

            guard let normalized = SiteManager.normalizedURL(from: urlStr) else {
                let a = NSAlert()
                a.messageText = "Invalid domain or URL"
                a.informativeText = "Please enter a valid domain (example.com) or URL (https://example.com)."
                a.runModal()
                return
            }

            let newSite = Site(id: UUID().uuidString, name: name, url: normalized, favicon: nil)
            var s = SiteManager.shared.sites
            s.append(newSite)
            SiteManager.shared.replaceSites(s)
            tableView.reloadData()
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
        let site = SiteManager.shared.sites[selected]

        let alert = NSAlert()
        alert.messageText = "Edit Site"
        alert.informativeText = "Edit the name and start URL (e.g., example.com or https://example.com):"

        let nameField = NSTextField(frame: NSRect(x: 0, y: 44, width: 420, height: 24))
        nameField.placeholderString = "Site Name"
        nameField.stringValue = site.name
        let urlField = NSTextField(frame: NSRect(x: 0, y: 12, width: 420, height: 24))
        urlField.placeholderString = "example.com"
        // show host rather than full scheme when possible for clarity
        urlField.stringValue = site.url.host ?? site.url.absoluteString

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 72))
        container.addSubview(nameField)
        container.addSubview(urlField)

        alert.accessoryView = container
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let res = alert.runModal()
        if res == .alertFirstButtonReturn {
            let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            var urlStr = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !urlStr.isEmpty else { return }

            if URL(string: urlStr)?.host == nil {
                if let prefixed = URL(string: "https://\(urlStr)") {
                    urlStr = prefixed.absoluteString
                }
            }

            guard let u = URL(string: urlStr), u.host != nil else { return }

            var s = SiteManager.shared.sites
            let updated = Site(id: site.id, name: name, url: u, favicon: site.favicon)
            s[selected] = updated
            SiteManager.shared.replaceSites(s)
            tableView.reloadData()
        }
    }

    // MARK: - Table
    func numberOfRows(in tableView: NSTableView) -> Int {
        return SiteManager.shared.sites.count
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let tf = obj.object as? NSTextField else { return }
        let row = tableView.row(for: tf)
        let col = tableView.column(for: tf)
        guard row >= 0, row < SiteManager.shared.sites.count else { return }
        var sites = SiteManager.shared.sites
        let original = sites[row]
        let colId = tableView.tableColumns[col].identifier.rawValue

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

        if colId == "name" {
            let newName = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newName.isEmpty else {
                setError("Name cannot be empty")
                // revert to original
                tf.stringValue = original.name
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { setError(nil) }
                return
            }
            setError(nil)
            guard newName != original.name else { return }
            sites[row] = Site(id: original.id, name: newName, url: original.url, favicon: original.favicon)
            SiteManager.shared.replaceSites(sites)
            tableView.reloadData()
        } else if colId == "url" {
            var urlStr = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
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
                    sites[row] = Site(id: original.id, name: original.name, url: normalized, favicon: original.favicon)
                    SiteManager.shared.replaceSites(sites)
                    tableView.reloadData()
                } else {
                    tf.stringValue = normalized.host ?? normalized.absoluteString
                }
            } else {
                // invalid
                setError("Please enter a valid domain or URL (e.g. example.com or https://example.com)")
                // revert display but keep the error visible briefly
                tf.stringValue = original.url.host ?? original.url.absoluteString
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { setError(nil) }
                return
            }
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let site = SiteManager.shared.sites[row]
        if tableColumn?.identifier.rawValue == "name" {
            let tf = NSTextField(string: site.name)
            tf.isBordered = false
            tf.backgroundColor = .clear
            tf.lineBreakMode = .byTruncatingTail
            tf.isEditable = true
            tf.delegate = self
            // Accessibility/hint
            tf.toolTip = "Double-click or edit to change site name"
            return tf
        } else {
            // Show only the host (example.com) to the user
            let hostStr = site.url.host ?? site.url.absoluteString
            let tf = NSTextField(string: hostStr)
            tf.isBordered = false
            tf.backgroundColor = .clear
            tf.lineBreakMode = .byTruncatingTail
            tf.isEditable = true
            tf.delegate = self
            tf.toolTip = "Double-click or edit to change domain (e.g. example.com)"
            return tf
        }
    }
}
