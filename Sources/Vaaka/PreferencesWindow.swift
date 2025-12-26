import AppKit

class PreferencesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = NSTableView()
    private var tableContainer: NSScrollView!

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 480, height: 320), styleMask: [.titled, .closable], backing: .buffered, defer: false)
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

        let addButton = NSButton(title: "Add Domain", target: self, action: #selector(addDomain))
        addButton.bezelStyle = .rounded

        let removeButton = NSButton(title: "Remove Selected", target: self, action: #selector(removeSelected))
        removeButton.bezelStyle = .rounded

        let header = NSTextField(labelWithString: "Whitelisted Domains")
        header.font = NSFont.boldSystemFont(ofSize: 14)

        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("domain")))
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAutomaticRowHeights = true

        tableContainer = NSScrollView()
        tableContainer.documentView = tableView
        tableContainer.hasVerticalScroller = true

        let controls = NSStackView(views: [addButton, removeButton])
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
            tableContainer.heightAnchor.constraint(equalToConstant: 200)
        ])
    }

    // MARK: - Actions
    @objc private func addDomain() {
        let alert = NSAlert()
        alert.messageText = "Add domain"
        alert.informativeText = "Enter a domain to whitelist (e.g., example.com):"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        alert.accessoryView = input
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let res = alert.runModal()
        if res == .alertFirstButtonReturn {
            let domain = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !domain.isEmpty else { return }
            WhitelistManager.shared.addDomain(domain)
            tableView.reloadData()
        }
    }

    @objc private func removeSelected() {
        let selected = tableView.selectedRow
        guard selected >= 0 else { return }
        let domain = WhitelistManager.shared.simpleDomains[selected]
        WhitelistManager.shared.removeDomain(domain)
        tableView.reloadData()
    }

    // MARK: - Table
    func numberOfRows(in tableView: NSTableView) -> Int {
        return WhitelistManager.shared.simpleDomains.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let domain = WhitelistManager.shared.simpleDomains[row]
        let cell = NSTextField(labelWithString: domain)
        cell.lineBreakMode = .byTruncatingTail
        return cell
    }
}
