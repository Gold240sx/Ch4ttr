import SwiftUI

struct PermissionsSectionView: View {
    private let permissions = PermissionsService()
    @State private var micStatus: PermissionStatus = .notDetermined
    @State private var speechStatus: PermissionStatus = .notDetermined
    @State private var accessibilityStatus: PermissionStatus = .denied

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeaderView(title: "Permissions", subtitle: "Grant access so recording, speech recognition, and auto‑paste work reliably.")

            SettingCardView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Privacy & Security")
                        .font(.headline)

                    PermissionRow(
                        title: "Microphone",
                        status: micStatus.rawValue,
                        isAuthorized: micStatus == .authorized,
                        actionTitle: micStatus == .notDetermined ? "Request" : "Open Settings"
                    ) {
                        if micStatus == .notDetermined {
                            Task {
                                _ = await permissions.requestMicrophone()
                                refreshStatuses()
                            }
                        } else {
                            permissions.openPrivacyMicrophone()
                        }
                    }

                    PermissionRow(
                        title: "Speech Recognition",
                        status: speechStatus.rawValue,
                        isAuthorized: speechStatus == .authorized,
                        actionTitle: speechStatus == .notDetermined ? "Request" : "Open Settings"
                    ) {
                        if speechStatus == .notDetermined {
                            Task {
                                _ = await permissions.requestSpeech()
                                refreshStatuses()
                            }
                        } else {
                            permissions.openPrivacySpeechRecognition()
                        }
                    }

                    Divider().opacity(0.25)

                    PermissionRow(
                        title: "Accessibility",
                        status: accessibilityStatus == .authorized ? "authorized" : "required for auto‑paste",
                        isAuthorized: accessibilityStatus == .authorized,
                        actionTitle: accessibilityStatus == .denied ? "Open Settings" : "Request"
                    ) {
                        if accessibilityStatus == .authorized { return }
                        permissions.requestAccessibilityPrompt()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            if permissions.accessibilityStatus() != .authorized {
                                permissions.openPrivacyAccessibility()
                            }
                            refreshStatuses()
                        }
                    }

                    HStack {
                        Spacer(minLength: 0)
                        Button("Open Privacy Settings") {
                            permissions.openPrivacyAccessibility()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .onAppear { refreshStatuses() }
    }

    private func refreshStatuses() {
        micStatus = permissions.microphoneStatus()
        speechStatus = permissions.speechStatus()
        accessibilityStatus = permissions.accessibilityStatus()
    }
}

private struct PermissionRow: View {
    let title: String
    let status: String
    let isAuthorized: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isAuthorized {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.green)
                    .accessibilityLabel("Authorized")
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}
