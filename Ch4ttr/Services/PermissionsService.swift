import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import Speech

enum PermissionStatus: String, Sendable {
    case notDetermined
    case denied
    case authorized
}

@MainActor
final class PermissionsService {
    func microphoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .authorized
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    func speechStatus() -> PermissionStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .authorized
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    func requestMicrophone() async -> Bool {
        await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                cont.resume(returning: ok)
            }
        }
    }

    func requestSpeech() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    func openPrivacyMicrophone() {
        openSystemSettings(anchor: "Privacy_Microphone")
    }

    func openPrivacySpeechRecognition() {
        openSystemSettings(anchor: "Privacy_SpeechRecognition")
    }

    func openPrivacyAccessibility() {
        openSystemSettings(anchor: "Privacy_Accessibility")
    }

    func accessibilityStatus() -> PermissionStatus {
        AXIsProcessTrusted() ? .authorized : .denied
    }

    func requestAccessibilityPrompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    private func openSystemSettings(anchor: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        NSWorkspace.shared.open(url)
    }
}
