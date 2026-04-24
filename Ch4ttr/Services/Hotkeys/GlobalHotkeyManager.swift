import Carbon
import Foundation

enum HotkeyEvent: Sendable {
    case pressed
    case released
}

@MainActor
final class GlobalHotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handler: ((HotkeyEvent) -> Void)?
    private var eventHandlerRef: EventHandlerRef?
    private var isDown = false

    func setHandler(_ handler: @escaping (HotkeyEvent) -> Void) {
        self.handler = handler
        installEventHandlerIfNeeded()
    }

    func register(hotkey: Hotkey) {
        unregister()
        installEventHandlerIfNeeded()

        var hotKeyID = EventHotKeyID(signature: OSType(0x4334_5434), id: 1) // 'C4TT'
        let mods = carbonModifiers(from: hotkey.modifiers)

        let status = RegisterEventHotKey(
            UInt32(hotkey.keyCode),
            mods,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            // Non-fatal: hotkey may fail due to permissions / conflicts.
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        isDown = false
    }

    private func installEventHandlerIfNeeded() {
        if eventHandlerRef != nil { return }

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        let unmanagedSelf = Unmanaged.passUnretained(self)

        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let userData else { return noErr }
                let this = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()

                let kind = GetEventKind(event)
                if kind == UInt32(kEventHotKeyPressed) {
                    if !this.isDown {
                        this.isDown = true
                        Task { @MainActor in this.handler?(.pressed) }
                    }
                } else if kind == UInt32(kEventHotKeyReleased) {
                    if this.isDown {
                        this.isDown = false
                        Task { @MainActor in this.handler?(.released) }
                    }
                }
                return noErr
            },
            eventTypes.count,
            &eventTypes,
            unmanagedSelf.toOpaque(),
            &eventHandlerRef
        )

        if status != noErr {
            eventHandlerRef = nil
        }
    }

    private func carbonModifiers(from mods: HotkeyModifiers) -> UInt32 {
        var out: UInt32 = 0
        if mods.contains(.command) { out |= UInt32(cmdKey) }
        if mods.contains(.option) { out |= UInt32(optionKey) }
        if mods.contains(.control) { out |= UInt32(controlKey) }
        if mods.contains(.shift) { out |= UInt32(shiftKey) }
        return out
    }
}

