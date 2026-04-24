import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var restoreAccessoryOnClose: Bool = false

    func show(with model: AppViewModel) {
        // Accessory apps can fail to present/activate normal windows.
        // Temporarily switch to regular so the window reliably appears.
        if NSApp.activationPolicy() != .regular {
            restoreAccessoryOnClose = true
            NSApp.setActivationPolicy(.regular)
        }

        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let view = ContentView().environmentObject(model)
        let hosting = NSHostingController(rootView: view)

        let w = NSWindow(contentViewController: hosting)
        w.title = "Ch4ttr"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        if #available(macOS 11.0, *) {
            w.toolbarStyle = .unified
        }
        let tb = NSToolbar(identifier: "Ch4ttrToolbar")
        tb.displayMode = .iconOnly
        tb.showsBaselineSeparator = false
        w.toolbar = tb
        w.setContentSize(NSSize(width: 900, height: 600))
        w.isReleasedWhenClosed = false
        w.center()

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: w,
            queue: .main
        ) { [weak self] _ in
            self?.window = nil
            if self?.restoreAccessoryOnClose == true {
                NSApp.setActivationPolicy(.accessory)
                self?.restoreAccessoryOnClose = false
            }
        }

        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

