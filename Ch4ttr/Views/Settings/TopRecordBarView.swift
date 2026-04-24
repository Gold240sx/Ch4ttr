import AppKit
import SwiftUI

struct TopRecordBarView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                StatusPillView(state: model.recordingState)

                InputLevelMeterView(level: model.inputLevel, waveform: model.inputWaveform)
                    .frame(height: 26)
                    .opacity(model.recordingState == .recording ? 1 : 0.55)

                Spacer(minLength: 0)

                Button {
                    Task { await model.toggleRecordingFromUI() }
                } label: {
                    Text(buttonTitle)
                        .frame(minWidth: 90)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.recordingState == .analyzing)
            }

            if let err = model.lastPasteError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if let err = model.lastTranscriptionError {
                Text("Transcription failed: " + err)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            } else if model.recordingState == .recording, !model.livePreviewText.isEmpty {
                Text(model.livePreviewText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if !model.lastTranscript.isEmpty {
                HStack(spacing: 10) {
                    Text(model.lastTranscript)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Spacer(minLength: 0)

                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.lastTranscript, forType: .string)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                Text(model.recordingState == .recording ? "Listening…" : "After you stop, the last transcript will appear here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var buttonTitle: String {
        switch model.recordingState {
        case .standby: return "Record"
        case .recording: return "Stop"
        case .analyzing: return "Working…"
        }
    }
}
