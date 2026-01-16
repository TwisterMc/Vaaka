import AppKit

final class DownloadRowView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private let revealButton = NSButton(title: "Reveal", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private var downloadId: String?

    init(item: DownloadsManager.DownloadItem) {
        super.init(frame: .zero)
        setup()
        configure(with: item)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.98).cgColor
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false

        label.font = NSFont.systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false

        progress.isIndeterminate = false
        progress.controlSize = .small
        progress.translatesAutoresizingMaskIntoConstraints = false

        revealButton.bezelStyle = .rounded
        revealButton.target = self
        revealButton.action = #selector(revealPressed)
        revealButton.translatesAutoresizingMaskIntoConstraints = false

        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        addSubview(progress)
        addSubview(revealButton)
        addSubview(cancelButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            progress.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            progress.centerYAnchor.constraint(equalTo: centerYAnchor),
            progress.widthAnchor.constraint(equalToConstant: 160),

            revealButton.leadingAnchor.constraint(equalTo: progress.trailingAnchor, constant: 8),
            revealButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            cancelButton.leadingAnchor.constraint(equalTo: revealButton.trailingAnchor, constant: 6),
            cancelButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func configure(with item: DownloadsManager.DownloadItem) {
        downloadId = item.id
        label.stringValue = item.suggestedFilename
        progress.doubleValue = item.progress * 100.0
        switch item.status {
        case .inProgress:
            cancelButton.isHidden = false
            revealButton.isHidden = true
        case .completed:
            cancelButton.isHidden = true
            revealButton.isHidden = false
            progress.doubleValue = 100.0
        case .failed, .cancelled:
            cancelButton.isHidden = true
            revealButton.isHidden = false
        }
    }

    @objc private func revealPressed() {
        guard let id = downloadId, let item = DownloadsManager.shared.allItems().first(where: { $0.id == id }), let dest = item.destinationURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([dest])
    }

    @objc private func cancelPressed() {
        guard let id = downloadId else { return }
        DownloadsManager.shared.cancel(id: id)
    }
}

final class DownloadsBarView: NSView {
    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func apply(items: [DownloadsManager.DownloadItem]) {
        // Rebuild minimal rows (small number expected)
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for item in items.sorted(by: { $0.status == .inProgress && $1.status != .inProgress }) {
            let row = DownloadRowView(item: item)
            stack.addArrangedSubview(row)
            row.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        }
    }
}
