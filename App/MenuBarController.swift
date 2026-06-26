import AppKit

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem

    var onSettingsClicked: (() -> Void)?
    var onQuitClicked: (() -> Void)?
    var onToggleClicked: ((Bool) -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "keyboard.badge.ellipsis",
                accessibilityDescription: "AIComplete"
            )
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: "Enabled",
            action: #selector(toggleEnabled(_:)),
            keyEquivalent: ""
        )
        toggleItem.state = .on
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit AIComplete",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        sender.state = sender.state == .on ? .off : .on
        onToggleClicked?(sender.state == .on)
    }

    @objc private func openSettings() {
        onSettingsClicked?()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
