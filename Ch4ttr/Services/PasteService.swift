import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

final class PasteService {
    private var liveInsertion: LiveInsertionSession?

    @MainActor
    func pasteTextAndSimulatePaste(_ text: String) -> Result<Void, PasteError> {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        return simulatePasteFromClipboard()
    }

    /// Command–V (uses whatever is already on the general pasteboard).
    @MainActor
    func simulatePasteFromClipboard() -> Result<Void, PasteError> {
        postKeyDownUp(virtualKey: 0x09, flags: .maskCommand) // V
    }

    /// Command–A (select all in the focused text field in most apps).
    @MainActor
    func simulateSelectAll() -> Result<Void, PasteError> {
        postKeyDownUp(virtualKey: 0x00, flags: .maskCommand) // A
    }

    /// Option–Up then Option–Shift–Down: best-effort “select paragraph” in many Cocoa-style fields.
    @MainActor
    func simulateSelectParagraphBestEffort() async -> Result<Void, PasteError> {
        let r1 = postKeyDownUp(virtualKey: 0x7E, flags: .maskAlternate) // Up + Option
        guard case .success = r1 else { return r1 }
        try? await Task.sleep(for: .milliseconds(75))
        return postKeyDownUp(virtualKey: 0x7D, flags: [.maskAlternate, .maskShift]) // Down + Option + Shift
    }

    /// Option–Shift–Left then Option–Shift–Right: best-effort “select sentence” around the caret.
    @MainActor
    func simulateSelectSentenceBestEffort() async -> Result<Void, PasteError> {
        let r1 = postKeyDownUp(virtualKey: 0x7B, flags: [.maskAlternate, .maskShift]) // Left
        guard case .success = r1 else { return r1 }
        try? await Task.sleep(for: .milliseconds(75))
        return postKeyDownUp(virtualKey: 0x7C, flags: [.maskAlternate, .maskShift]) // Right
    }

    @MainActor
    private func postKeyDownUp(virtualKey: CGKeyCode, flags: CGEventFlags) -> Result<Void, PasteError> {
        guard AXIsProcessTrusted() else {
            return .failure(.accessibilityDenied)
        }
        let src = CGEventSource(stateID: .combinedSessionState)
        guard
            let down = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: true),
            let up = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: false)
        else {
            return .failure(.eventCreationFailed)
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return .success(())
    }

    @MainActor
    func beginLiveInsertion() -> Result<Void, PasteError> {
        guard AXIsProcessTrusted() else {
            return .failure(.accessibilityDenied)
        }

        liveInsertion = LiveInsertionSession()
        return .success(())
    }

    @MainActor
    func replaceLiveInsertion(with text: String) -> Result<Void, PasteError> {
        guard let liveInsertion else {
            return pasteTextAndSimulatePaste(text)
        }

        return liveInsertion.replace(with: text)
    }

    @MainActor
    func finishLiveInsertion() {
        liveInsertion = nil
    }

    private func simulateCmdVViaCGEvent() -> Result<Void, PasteError> {
        simulatePasteFromClipboard()
    }

    private func pasteReplacingSelection(_ text: String) -> Result<Void, PasteError> {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        return simulateCmdVViaCGEvent()
    }

    private func deleteSelectionViaCGEvent() -> Result<Void, PasteError> {
        guard AXIsProcessTrusted() else {
            return .failure(.accessibilityDenied)
        }

        let src = CGEventSource(stateID: .combinedSessionState)
        // Virtual key 0x33 = Delete / Backspace.
        guard
            let down = CGEvent(keyboardEventSource: src, virtualKey: 0x33, keyDown: true),
            let up = CGEvent(keyboardEventSource: src, virtualKey: 0x33, keyDown: false)
        else {
            return .failure(.eventCreationFailed)
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return .success(())
    }

    private func replaceSelection(with text: String) -> Result<Void, PasteError> {
        text.isEmpty ? deleteSelectionViaCGEvent() : pasteReplacingSelection(text)
    }

    private func selectPreviousCharacters(_ characterCount: Int) -> Result<Void, PasteError> {
        guard AXIsProcessTrusted() else {
            return .failure(.accessibilityDenied)
        }
        guard characterCount > 0 else {
            return .success(())
        }

        let src = CGEventSource(stateID: .combinedSessionState)
        for _ in 0..<characterCount {
            guard
                let down = CGEvent(keyboardEventSource: src, virtualKey: 0x7B, keyDown: true),
                let up = CGEvent(keyboardEventSource: src, virtualKey: 0x7B, keyDown: false)
            else {
                return .failure(.eventCreationFailed)
            }
            down.flags = [.maskShift]
            up.flags = [.maskShift]
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }

        return .success(())
    }

    private final class LiveInsertionSession {
        private let target = AccessibilityTextTarget.captureFocusedTarget()
        private var previousText = ""

        @MainActor
        func replace(with text: String) -> Result<Void, PasteError> {
            if text == previousText {
                return .success(())
            }

            let delta = ReplacementDelta(previousText: previousText, nextText: text)

            if let target, target.replace(previousText: previousText, with: text, delta: delta) {
                previousText = text
                return .success(())
            }

            if let target, target.replaceSelectedText(previousText: previousText, delta: delta) {
                previousText = text
                return .success(())
            }

            let result = replaceViaPasteboard(with: text, delta: delta)
            if case .success = result {
                previousText = text
            }
            return result
        }

        @MainActor
        private func replaceViaPasteboard(with text: String, delta: ReplacementDelta) -> Result<Void, PasteError> {
            let service = PasteService()

            if previousText.isEmpty {
                return service.replaceSelection(with: text)
            }

            if delta.removedCharacterCount > 0 {
                let selectResult = service.selectPreviousCharacters(delta.removedCharacterCount)
                if case .failure = selectResult {
                    return selectResult
                }
            }

            return service.replaceSelection(with: delta.insertedText)
        }
    }

    private struct ReplacementDelta {
        let commonPrefixUTF16Length: Int
        let removedUTF16Length: Int
        let removedCharacterCount: Int
        let insertedText: String

        init(previousText: String, nextText: String) {
            var previousIndex = previousText.startIndex
            var nextIndex = nextText.startIndex

            while previousIndex < previousText.endIndex,
                  nextIndex < nextText.endIndex,
                  previousText[previousIndex] == nextText[nextIndex] {
                previousIndex = previousText.index(after: previousIndex)
                nextIndex = nextText.index(after: nextIndex)
            }

            let commonPrefix = previousText[..<previousIndex]
            let removedText = previousText[previousIndex...]
            let insertedText = nextText[nextIndex...]

            self.commonPrefixUTF16Length = commonPrefix.utf16.count
            self.removedUTF16Length = removedText.utf16.count
            self.removedCharacterCount = removedText.count
            self.insertedText = String(insertedText)
        }
    }

    private final class AccessibilityTextTarget {
        private let element: AXUIElement
        private let anchorLocation: Int
        private let initialSelectedLength: Int

        private init(element: AXUIElement, selectedRange: CFRange) {
            self.element = element
            self.anchorLocation = selectedRange.location
            self.initialSelectedLength = selectedRange.length
        }

        static func captureFocusedTarget() -> AccessibilityTextTarget? {
            let systemWide = AXUIElementCreateSystemWide()
            var focusedRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                systemWide,
                kAXFocusedUIElementAttribute as CFString,
                &focusedRef
            ) == .success else {
                return nil
            }
            guard let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
                return nil
            }
            let element = focusedRef as! AXUIElement

            guard let selectedRange = copySelectedRange(from: element) else {
                return nil
            }

            return AccessibilityTextTarget(element: element, selectedRange: selectedRange)
        }

        func replace(previousText: String, with text: String, delta: ReplacementDelta) -> Bool {
            guard let current = copyStringValue() else {
                return false
            }

            let currentLength = current.length
            guard previousText.isEmpty || currentContainsPreviousText(current, previousText: previousText) else {
                return false
            }

            let replacementLength = replacementLength(previousText: previousText, delta: delta)
            let replacementRange = NSRange(
                location: anchorLocation + delta.commonPrefixUTF16Length,
                length: replacementLength
            )

            guard replacementRange.location >= 0, NSMaxRange(replacementRange) <= currentLength else {
                return false
            }

            let nextValue = current.replacingCharacters(in: replacementRange, with: delta.insertedText)
            guard AXUIElementSetAttributeValue(
                element,
                kAXValueAttribute as CFString,
                nextValue as CFTypeRef
            ) == .success else {
                return false
            }

            var cursorRange = CFRange(
                location: anchorLocation + (text as NSString).length,
                length: 0
            )
            guard let cursorValue = AXValueCreate(.cfRange, &cursorRange) else {
                return false
            }

            _ = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                cursorValue
            )
            return true
        }

        func replaceSelectedText(previousText: String, delta: ReplacementDelta) -> Bool {
            guard canApplyReplacement(previousText: previousText) else {
                return false
            }
            guard selectReplacementRange(previousText: previousText, delta: delta) else {
                return false
            }

            return AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                delta.insertedText as CFTypeRef
            ) == .success
        }

        private func selectReplacementRange(previousText: String, delta: ReplacementDelta) -> Bool {
            let replacementLength = replacementLength(previousText: previousText, delta: delta)
            var replacementRange = CFRange(
                location: anchorLocation + delta.commonPrefixUTF16Length,
                length: replacementLength
            )
            guard let rangeValue = AXValueCreate(.cfRange, &replacementRange) else {
                return false
            }

            return AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                rangeValue
            ) == .success
        }

        private func replacementLength(previousText: String, delta: ReplacementDelta) -> Int {
            previousText.isEmpty ? initialSelectedLength : delta.removedUTF16Length
        }

        private func canApplyReplacement(previousText: String) -> Bool {
            guard !previousText.isEmpty, let current = copyStringValue() else {
                return true
            }
            return currentContainsPreviousText(current, previousText: previousText)
        }

        private func currentContainsPreviousText(_ current: NSString, previousText: String) -> Bool {
            let previousLength = (previousText as NSString).length
            let previousRange = NSRange(location: anchorLocation, length: previousLength)
            guard previousRange.location >= 0, NSMaxRange(previousRange) <= current.length else {
                return false
            }
            return current.substring(with: previousRange) == previousText
        }

        private func copyStringValue() -> NSString? {
            var valueRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                element,
                kAXValueAttribute as CFString,
                &valueRef
            ) == .success else {
                return nil
            }
            guard let string = valueRef as? String else {
                return nil
            }
            return string as NSString
        }

        private static func copySelectedRange(from element: AXUIElement) -> CFRange? {
            var rangeRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                &rangeRef
            ) == .success else {
                return nil
            }
            guard let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() else {
                return nil
            }

            let rangeValue = rangeRef as! AXValue
            var range = CFRange()
            guard AXValueGetValue(rangeValue, .cfRange, &range) else {
                return nil
            }
            return range
        }
    }
}

enum PasteError: Error, CustomStringConvertible {
    case accessibilityDenied
    case eventCreationFailed

    var description: String {
        switch self {
        case .accessibilityDenied:
            return "Paste failed: Accessibility permission required. Grant it in System Settings → Privacy & Security → Accessibility."
        case .eventCreationFailed:
            return "Paste failed: could not create keyboard event."
        }
    }
}
