import AppKit
import Foundation

/// Observes modifier keys globally (and locally when Ch4ttr is focused) and fires when a chosen modifier is held alone longer than a threshold.
@MainActor
final class LongHoldModifierMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var waitTask: Task<Void, Never>?
    private var holdGeneration = 0
    private var exclusiveTargetDown = false
    private var firedThisHold = false

    private var state: () -> (enabled: Bool, key: LongHoldModifierKey, duration: TimeInterval) = { (false, .shift, 2) }
    private var onThreshold: () -> Void = {}
    private var onReleaseAfterThreshold: () -> Void = {}

    func configure(
        state: @escaping @MainActor () -> (enabled: Bool, key: LongHoldModifierKey, duration: TimeInterval),
        onThreshold: @escaping @MainActor () -> Void,
        onReleaseAfterThreshold: @escaping @MainActor () -> Void
    ) {
        self.state = state
        self.onThreshold = onThreshold
        self.onReleaseAfterThreshold = onReleaseAfterThreshold
        reinstallMonitors()
    }

    func reinstallMonitors() {
        removeMonitors()
        waitTask?.cancel()
        waitTask = nil
        exclusiveTargetDown = false
        firedThisHold = false
        holdGeneration += 1

        let (enabled, _, _) = state()
        guard enabled else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFlagsChanged(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFlagsChanged(event) }
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let (enabled, key, duration) = state()
        guard enabled else { return }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let exclusive = Self.exclusiveTargetDown(flags, key: key)

        if exclusive {
            if !exclusiveTargetDown {
                exclusiveTargetDown = true
                firedThisHold = false
                scheduleThresholdWait(duration: Self.clampedDuration(duration))
            }
        } else {
            if exclusiveTargetDown {
                waitTask?.cancel()
                waitTask = nil
                if firedThisHold {
                    onReleaseAfterThreshold()
                }
                exclusiveTargetDown = false
                firedThisHold = false
                holdGeneration += 1
            }
        }
    }

    private func scheduleThresholdWait(duration: TimeInterval) {
        holdGeneration += 1
        let generation = holdGeneration
        waitTask?.cancel()
        waitTask = Task { [weak self] in
            let nanos = UInt64(duration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard generation == self.holdGeneration, self.exclusiveTargetDown, !self.firedThisHold else { return }
                self.firedThisHold = true
                self.onThreshold()
            }
        }
    }

    /// True when `key` is down and no other Command / Option / Control / Shift modifiers are down.
    nonisolated static func exclusiveTargetDown(_ flags: NSEvent.ModifierFlags, key: LongHoldModifierKey) -> Bool {
        let shift = flags.contains(.shift)
        let command = flags.contains(.command)
        let option = flags.contains(.option)
        let control = flags.contains(.control)

        let targetDown: Bool
        switch key {
        case .shift: targetDown = shift
        case .command: targetDown = command
        case .option: targetDown = option
        case .control: targetDown = control
        }

        guard targetDown else { return false }

        switch key {
        case .shift:
            return !command && !option && !control
        case .command:
            return !shift && !option && !control
        case .option:
            return !shift && !command && !control
        case .control:
            return !shift && !command && !option
        }
    }

    private static func clampedDuration(_ seconds: Double) -> TimeInterval {
        min(10, max(0.5, seconds))
    }
}
