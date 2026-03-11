import AppKit

class FindBarView: NSView {
    let searchField = NSSearchField()
    private let matchLabel = NSTextField(labelWithString: "")
    private let previousButton = NSButton(title: "Prev", target: nil, action: nil)
    private let nextButton = NSButton(title: "Next", target: nil, action: nil)
    private let doneButton = NSButton(title: "Close", target: nil, action: nil)

    var onSearch: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onClose: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        // Use a visual effect background so the bar adapts to light/dark appearances
        let bgView = NSVisualEffectView()
        bgView.translatesAutoresizingMaskIntoConstraints = false
        bgView.material = .sidebar
        bgView.blendingMode = .withinWindow
        bgView.state = .active
        addSubview(bgView, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            bgView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bgView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bgView.topAnchor.constraint(equalTo: topAnchor),
            bgView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Accessibility: make the bar a group and expose children in a logical order
        self.setAccessibilityElement(true)
        self.setAccessibilityRole(.group)
        self.setAccessibilityLabel("Find in page")

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.target = self
        searchField.action = #selector(searchFieldChanged)
        searchField.delegate = self
        searchField.setAccessibilityLabel("Find field")
        searchField.setAccessibilityIdentifier("FindBar.SearchField")

        // Make the search field use a compact bezel and draw its background so it looks native in both modes
        searchField.bezelStyle = .roundedBezel
        searchField.controlSize = .small
        searchField.drawsBackground = true
        searchField.backgroundColor = NSColor.controlBackgroundColor
        let placeholderAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.placeholderTextColor]
        searchField.placeholderAttributedString = NSAttributedString(string: "Find in page", attributes: placeholderAttrs)

        matchLabel.translatesAutoresizingMaskIntoConstraints = false
        matchLabel.font = .systemFont(ofSize: 11)
        matchLabel.textColor = .secondaryLabelColor
        matchLabel.setAccessibilityLabel("Match count")
        matchLabel.setAccessibilityIdentifier("FindBar.MatchLabel")

        previousButton.translatesAutoresizingMaskIntoConstraints = false
        previousButton.target = self
        previousButton.action = #selector(previousClicked)
        previousButton.setAccessibilityLabel("Previous result")
        previousButton.setAccessibilityIdentifier("FindBar.PreviousButton")

        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.target = self
        nextButton.action = #selector(nextClicked)
        nextButton.setAccessibilityLabel("Next result")
        nextButton.setAccessibilityIdentifier("FindBar.NextButton")

        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.target = self
        doneButton.action = #selector(closeClicked)
        doneButton.setAccessibilityLabel("Close find bar")
        doneButton.setAccessibilityIdentifier("FindBar.CloseButton")

        addSubview(searchField)
        addSubview(matchLabel)
        addSubview(previousButton)
        addSubview(nextButton)
        addSubview(doneButton)

        // Ensure VoiceOver traverses elements in a logical order
        self.setAccessibilityChildren([searchField, matchLabel, previousButton, nextButton, doneButton])

        // Keyboard: allow Tab/Shift-Tab navigation between controls
        // Order: searchField -> previousButton -> nextButton -> doneButton -> back to searchField
        searchField.nextKeyView = previousButton
        previousButton.nextKeyView = nextButton
        nextButton.nextKeyView = doneButton
        doneButton.nextKeyView = searchField

        // Make focus rings visible when controls receive keyboard focus
        previousButton.focusRingType = .default
        nextButton.focusRingType = .default
        doneButton.focusRingType = .default

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 240),

            matchLabel.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 8),
            matchLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            previousButton.leadingAnchor.constraint(equalTo: matchLabel.trailingAnchor, constant: 8),
            previousButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            nextButton.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: 8),
            nextButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            doneButton.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 12),
            doneButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            doneButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
        ])

        // Observe appearance changes and apply initial appearance
        NotificationCenter.default.addObserver(self, selector: #selector(appearanceChanged), name: NSNotification.Name("Vaaka.AppearanceChanged"), object: nil)
        updateAppearance()
    }

    @objc private func searchFieldChanged() {
        onSearch?(searchField.stringValue)
    }

    func controlTextDidChange(_ obj: Notification) {
        onSearch?(searchField.stringValue)
    }

    @objc private func previousClicked() { onPrevious?() }
    @objc private func nextClicked() { onNext?() }
    @objc private func closeClicked() { onClose?() }

    func updateMatchCount(current: Int, total: Int) {
        if total > 0 {
            matchLabel.stringValue = "\(current) of \(total)"
        } else {
            matchLabel.stringValue = searchField.stringValue.isEmpty ? "" : "No matches"
        }
    }

    @objc private func appearanceChanged() { updateAppearance() }

    private func updateAppearance() {
        // Use the current drawing appearance so semantic colors resolve correctly
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            self.matchLabel.textColor = .secondaryLabelColor
            self.searchField.textColor = .textColor
            self.searchField.backgroundColor = NSColor.controlBackgroundColor
            // Ensure button titles tint appropriately in dark mode
            if #available(macOS 10.14, *) {
                self.previousButton.contentTintColor = .labelColor
                self.nextButton.contentTintColor = .labelColor
                self.doneButton.contentTintColor = .labelColor
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension FindBarView: NSSearchFieldDelegate {}
