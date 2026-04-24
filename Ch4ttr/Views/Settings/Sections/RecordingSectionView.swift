import SwiftUI

struct RecordingSectionView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var isRecordingHotkey: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeaderView(title: "Recording", subtitle: "Configure how you trigger dictation.")

            SettingCardView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Recording Mode")
                        .font(.headline)

                    HStack(spacing: 10) {
                        SegButtonView(title: "Toggle", isOn: model.settings.recordingMode == .toggle) {
                            Task { @MainActor in
                                model.settings.recordingMode = .toggle
                                model.persistSettings()
                            }
                        }
                        SegButtonView(title: "Push to Talk", isOn: model.settings.recordingMode == .pushToTalk) {
                            Task { @MainActor in
                                model.settings.recordingMode = .pushToTalk
                                model.persistSettings()
                            }
                        }
                    }

                    Divider().opacity(0.25)

                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Hotkey")
                                .font(.headline)
                            Text(model.settings.hotkey.displayString)
                                .font(.system(.body, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            if isRecordingHotkey {
                                Text("Recording… press modifiers + key (Esc to cancel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        HStack(spacing: 10) {
                            Button(isRecordingHotkey ? "Cancel" : "Record Hotkey") {
                                isRecordingHotkey.toggle()
                            }
                            Button("Trigger Now") {
                                Task { await model.toggleRecordingFromUI() }
                            }
                        }
                    }

                    HotkeyRecorderView(isRecording: isRecordingHotkey) { hotkey in
                        Task { @MainActor in
                            model.settings.hotkey = hotkey
                            model.persistSettings()
                            isRecordingHotkey = false
                        }
                    } onCancel: {
                        isRecordingHotkey = false
                    }
                    .frame(width: 0, height: 0)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

