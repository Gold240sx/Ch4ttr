import AppKit

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    private let onOpenSettings: () -> Void
    private let onToggleRecording: () -> Void
    private let onQuit: () -> Void

    init(
        onOpenSettings: @escaping () -> Void,
        onToggleRecording: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onOpenSettings = onOpenSettings
        self.onToggleRecording = onToggleRecording
        self.onQuit = onQuit

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Ch4ttr")
            button.imagePosition = .imageOnly
        }

        rebuildMenu()
        statusItem.menu = menu
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let open = NSMenuItem(title: "Open Settings…", action: #selector(handleOpenSettings), keyEquivalent: ",")
        open.target = self
        menu.addItem(open)

        let toggle = NSMenuItem(title: "Toggle Recording", action: #selector(handleToggleRecording), keyEquivalent: " ")
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Ch4ttr", action: #selector(handleQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func handleOpenSettings() { onOpenSettings() }
    @objc private func handleToggleRecording() { onToggleRecording() }
    @objc private func handleQuit() { onQuit() }
}

