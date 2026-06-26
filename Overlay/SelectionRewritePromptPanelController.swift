import AppKit

@MainActor
final class SelectionRewritePromptPanelController: NSObject {
    private final class PromptPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    var onSubmit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    var isVisible: Bool { panel.isVisible }

    private let panel: PromptPanel
    private let promptField = NSTextField()
    private let selectedTextPreviewLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let applyButton = NSButton(title: "Apply", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private var currentAnchor = NSRect.zero

    override init() {
        panel = PromptPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 170),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
        configureContent()
    }

    func show(near anchor: NSRect, selectedText: String) {
        currentAnchor = anchor
        setSelectedTextPreview(selectedText)
        setLoading(false)
        setStatus("")
        placePanel(near: anchor)

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(promptField)
    }

    func hide() {
        panel.orderOut(nil)
        setLoading(false)
        setStatus("")
        promptField.stringValue = ""
    }

    func updateAnchor(_ anchor: NSRect) {
        currentAnchor = anchor
        guard panel.isVisible else { return }
        placePanel(near: anchor)
    }

    func setLoading(_ isLoading: Bool) {
        promptField.isEnabled = !isLoading
        cancelButton.isEnabled = !isLoading
        applyButton.isEnabled = !isLoading
        applyButton.title = isLoading ? "Applying..." : "Apply"
    }

    func setStatus(_ text: String, isError: Bool = false) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError
            ? NSColor.systemRed
            : NSColor.secondaryLabelColor
    }

    // MARK: - Actions

    @objc
    private func handleApply() {
        let prompt = promptField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            setStatus("Enter prompt", isError: true)
            return
        }
        onSubmit?(prompt)
    }

    @objc
    private func handleCancel() {
        hide()
        onCancel?()
    }

    // MARK: - Setup

    private func configurePanel() {
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
    }

    private func configureContent() {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 170))
        contentView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = contentView

        let titleLabel = NSTextField(labelWithString: "Rewrite selected text")
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor

        selectedTextPreviewLabel.font = .systemFont(ofSize: 12, weight: .regular)
        selectedTextPreviewLabel.textColor = .secondaryLabelColor
        selectedTextPreviewLabel.lineBreakMode = .byTruncatingTail
        selectedTextPreviewLabel.maximumNumberOfLines = 2
        selectedTextPreviewLabel.usesSingleLineMode = false

        promptField.placeholderString = "User prompt (e.g. make concise + formal)"
        promptField.target = self
        promptField.action = #selector(handleApply)
        promptField.focusRingType = .default

        statusLabel.font = .systemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = ""

        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"
        applyButton.target = self
        applyButton.action = #selector(handleApply)

        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(handleCancel)

        let buttonsRow = NSStackView(views: [cancelButton, applyButton])
        buttonsRow.orientation = .horizontal
        buttonsRow.alignment = .centerY
        buttonsRow.distribution = .gravityAreas
        buttonsRow.spacing = 8

        let stack = NSStackView(views: [titleLabel, selectedTextPreviewLabel, promptField, statusLabel, buttonsRow])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),

            promptField.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
            statusLabel.heightAnchor.constraint(equalToConstant: 14)
        ])
    }

    private func setSelectedTextPreview(_ selectedText: String) {
        let compact = selectedText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if compact.isEmpty {
            selectedTextPreviewLabel.stringValue = "Selection: (empty)"
            return
        }
        let preview = compact.count > 140 ? String(compact.prefix(140)) + "…" : compact
        selectedTextPreviewLabel.stringValue = "Selection: \(preview)"
    }

    private func placePanel(near anchor: NSRect) {
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(anchor) || $0.frame.contains(anchor.origin) }
            ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = panel.frame.size

        let preferredX = anchor.midX - size.width * 0.5
        let x = min(max(preferredX, frame.minX + 8), frame.maxX - size.width - 8)

        let preferredBelow = anchor.minY - size.height - 10
        let preferredAbove = anchor.maxY + 10
        let y: CGFloat
        if preferredBelow >= frame.minY + 6 {
            y = preferredBelow
        } else if preferredAbove + size.height <= frame.maxY - 6 {
            y = preferredAbove
        } else {
            y = min(max(preferredBelow, frame.minY + 6), frame.maxY - size.height - 6)
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
