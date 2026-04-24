import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var appModel: AppViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menubar app (no Dock icon)

        if appModel == nil {
            appModel = .shared
        }

        if let model = appModel {
            Task { await model.startup() }
        }

        // If the WindowGroup was created at launch, hide it.
        DispatchQueue.main.async {
            NSApp.windows.forEach { $0.orderOut(nil) }
            MiniRecorderController.shared.show()
        }
    }
}

