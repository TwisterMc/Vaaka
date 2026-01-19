import AppKit

final class DownloadRowView: NSView {
    private let checkImage = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let timestampLabel = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private let revealButton = NSButton(title: "Reveal", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private var downloadId: String?

    // Small helper to show a success state briefly before the row is removed
    private func showCompletedAnimation() {
        checkImage.isHidden = false
        checkImage.alphaValue = 0.0
        timestampLabel.isHidden = false
        timestampLabel.alphaValue = 0.0
        // Format timestamp
        let df = DateFormatter()
        df.timeStyle = .short
        df.dateStyle = .none
        timestampLabel.stringValue = df.string(from: Date())

        // Animate check and timestamp in
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            self.checkImage.animator().alphaValue = 1.0
            self.timestampLabel.animator().alphaValue = 1.0
        }, completionHandler: nil)
    }

    init(item: DownloadsManager.DownloadItem) {
        super.init(frame: .zero)
        setup()
        configure(with: item)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false

        label.font = NSFont.systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = NSColor.labelColor

        progress.isIndeterminate = false
        progress.controlSize = .small
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.minValue = 0.0
        progress.maxValue = 100.0
        progress.doubleValue = 0.0

        // Check image (hidden until completed)
        checkImage.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Completed") {
            checkImage.image = img
            checkImage.contentTintColor = NSColor.systemGreen
        }
        checkImage.isHidden = true
        addSubview(checkImage)

        revealButton.bezelStyle = .rounded
        revealButton.target = self
        revealButton.action = #selector(revealPressed)
        revealButton.translatesAutoresizingMaskIntoConstraints = false

        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        timestampLabel.font = NSFont.systemFont(ofSize: 11)
        timestampLabel.textColor = NSColor.secondaryLabelColor
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false
        timestampLabel.isHidden = true

        addSubview(label)
        addSubview(timestampLabel)
        addSubview(progress)
        addSubview(revealButton)
        addSubview(cancelButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),

            checkImage.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            checkImage.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkImage.widthAnchor.constraint(equalToConstant: 16),
            checkImage.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: checkImage.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            progress.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            progress.centerYAnchor.constraint(equalTo: centerYAnchor),
            progress.widthAnchor.constraint(equalToConstant: 160),

            timestampLabel.leadingAnchor.constraint(equalTo: progress.trailingAnchor, constant: 8),
            timestampLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            revealButton.leadingAnchor.constraint(equalTo: timestampLabel.trailingAnchor, constant: 8),
            revealButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            cancelButton.leadingAnchor.constraint(equalTo: revealButton.trailingAnchor, constant: 6),
            cancelButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            cancelButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        // Ensure layer for transform animations
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.cornerRadius = 6

        // Apply initial colors that adapt to current appearance
        updateColors()
    }

    private func dynamicRowBackground() -> NSColor {
        // Stronger contrast: light rows are slightly off-white, dark rows are near-black
        if effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(calibratedWhite: 0.12, alpha: 1.0)
        } else {
            return NSColor(calibratedWhite: 0.97, alpha: 1.0)
        }
    }

    private func updateColors() {
        // Use dynamic NSColor so that colors adapt when system appearance changes
        layer?.backgroundColor = dynamicRowBackground().cgColor
        // subtle border to separate rows in both appearances
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = (1.0 / (NSScreen.main?.backingScaleFactor ?? 1.0))
        label.textColor = NSColor.labelColor

        // Ensure buttons' title colors adapt to appearance for readability
        let titleAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.controlTextColor, .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]
        revealButton.attributedTitle = NSAttributedString(string: revealButton.title, attributes: titleAttrs)
        cancelButton.attributedTitle = NSAttributedString(string: cancelButton.title, attributes: titleAttrs)
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    var currentId: String? { return downloadId }

    func configure(with item: DownloadsManager.DownloadItem) {
        downloadId = item.id
        // Show the most meaningful label available: suggested filename -> source URL path -> 'Download'
        if !item.suggestedFilename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            label.stringValue = item.suggestedFilename
        } else if let src = item.sourceURL?.lastPathComponent, !src.isEmpty {
            label.stringValue = src
        } else if let dest = item.destinationURL?.lastPathComponent, !dest.isEmpty {
            label.stringValue = dest
        } else {
            label.stringValue = "Download"
        }

        // Ensure progress maps to 0..100 UI range
        progress.doubleValue = max(progress.minValue, min(progress.maxValue, item.progress * 100.0))

        switch item.status {
        case .inProgress:
            cancelButton.isHidden = false
            revealButton.isHidden = true
        case .completed:
            cancelButton.isHidden = true
            revealButton.isHidden = false
            progress.doubleValue = 100.0
            // Completed visual feedback
            showCompletedAnimation()
        case .failed, .cancelled:
            cancelButton.isHidden = true
            revealButton.isHidden = false
        }
        updateColors()
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
    private let background = NSVisualEffectView()
    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    private func setup() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        // Native vibrancy background
        background.translatesAutoresizingMaskIntoConstraints = false
        background.blendingMode = .withinWindow
        background.material = .contentBackground
        background.state = .active
        addSubview(background, positioned: .below, relativeTo: nil)

        stack.orientation = .vertical
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        updateColors()
    }

    private func updateColors() {
        // Visual effect handles background harmonization; add subtle border
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = (1.0 / (NSScreen.main?.backingScaleFactor ?? 1.0))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    func apply(items: [DownloadsManager.DownloadItem]) {
        // Keep existing rows where possible and animate additions/removals.
        let desired = items.sorted(by: { $0.status == .inProgress && $1.status != .inProgress })
        let desiredIds = desired.map { $0.id }

        // Map existing rows by id
        var existingRowsById: [String: DownloadRowView] = [:]
        for case let row as DownloadRowView in stack.arrangedSubviews {
            if let id = row.currentId { existingRowsById[id] = row }
        }

        // Remove rows that are not desired anymore (animate fade)
        for case let row as DownloadRowView in stack.arrangedSubviews {
            if let id = row.currentId, !desiredIds.contains(id) {
                // Fade + slide up
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.18
                    row.animator().alphaValue = 0.0
                }, completionHandler: {
                    // CA slide-up
                    let anim = CABasicAnimation(keyPath: "transform.translation.y")
                    anim.fromValue = 0
                    anim.toValue = -8
                    anim.duration = 0.18
                    anim.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    CATransaction.begin()
                    CATransaction.setCompletionBlock {
                        self.stack.removeArrangedSubview(row)
                        row.removeFromSuperview()
                    }
                    row.layer?.add(anim, forKey: "slideOut")
                    row.layer?.transform = CATransform3DMakeTranslation(0, -8, 0)
                    CATransaction.commit()
                })
            }
        }

        // Ensure rows are in the desired order; create or update as necessary
        for item in desired {
            if let existing = existingRowsById[item.id] {
                existing.configure(with: item)
                // ensure visible
                existing.alphaValue = 1.0
            } else {
                let row = DownloadRowView(item: item)
                row.alphaValue = 0.0
                // Prepare slide-in transform
                row.wantsLayer = true
                row.layer?.transform = CATransform3DMakeTranslation(0, -8, 0)
                stack.addArrangedSubview(row)
                row.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
                row.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
                // Animate in: fade + slide
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.22
                    row.animator().alphaValue = 1.0
                }, completionHandler: {
                    // CA animation for slide
                    let anim = CABasicAnimation(keyPath: "transform.translation.y")
                    anim.fromValue = -8
                    anim.toValue = 0
                    anim.duration = 0.22
                    anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    row.layer?.add(anim, forKey: "slideIn")
                    row.layer?.transform = CATransform3DIdentity
                })
            }
        }

        // Reorder arrangedSubviews to match desired order
        var ordered: [NSView] = []
        for item in desired {
            if let r = existingRowsById[item.id] {
                ordered.append(r)
            } else if let v = stack.arrangedSubviews.last(where: { ($0 as? DownloadRowView)?.currentId == item.id }) {
                ordered.append(v)
            }
        }
        // Apply reordering
        for v in ordered {
            stack.removeArrangedSubview(v)
            stack.addArrangedSubview(v)
        }
    }
}
