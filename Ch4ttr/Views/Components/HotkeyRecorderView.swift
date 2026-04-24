import AppKit
import SwiftUI

struct HotkeyRecorderView: NSViewRepresentable {
    var isRecording: Bool
    var onRecorded: (Hotkey) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> RecorderNSView {
        let v = RecorderNSView()
        v.onRecorded = onRecorded
        v.onCancel = onCancel
        return v
    }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        nsView.isRecording = isRecording
        nsView.onRecorded = onRecorded
        nsView.onCancel = onCancel
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

final class RecorderNSView: NSView {
    var isRecording: Bool = false
    var onRecorded: ((Hotkey) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 { // Esc
            onCancel?()
            return
        }

        let mods = HotkeyModifiers.from(event.modifierFlags)
        if mods.isEmpty { return } // avoid stealing normal typing

        let keyCode = Int(event.keyCode)
        let hotkey = Hotkey(keyCode: keyCode, modifiers: mods)
        onRecorded?(hotkey)
    }
}

extension HotkeyModifiers {
    static func from(_ flags: NSEvent.ModifierFlags) -> HotkeyModifiers {
        var mods: HotkeyModifiers = []
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        return mods
    }
}

