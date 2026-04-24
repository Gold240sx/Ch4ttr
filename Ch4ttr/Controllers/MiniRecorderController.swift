import AppKit
import SwiftUI

@MainActor
final class MiniRecorderController {
    static let shared = MiniRecorderController()

    fileprivate enum Layout {
        static let width: CGFloat = 420
        /// Fits `InputLevelMeterView` at `heightScale: 2` (caps + vertical padding).
        static let waveformHeight: CGFloat = 52

        static func height(isExpanded: Bool, showsTranscript: Bool, showsWaveform: Bool) -> CGFloat {
            let collapsedHeight: CGFloat = showsWaveform ? 88 : 64
            let transcriptHeight: CGFloat = showsTranscript ? 28 : 0
            let expandedHeight: CGFloat = isExpanded ? 232 : 0
            return collapsedHeight + transcriptHeight + expandedHeight
        }
    }

    private var window: NSWindow?
    private var restoreAccessoryOnClose: Bool = false

    func show() {
        if NSApp.activationPolicy() != .regular {
            restoreAccessoryOnClose = true
            NSApp.setActivationPolicy(.regular)
        }

        if window == nil {
            let root = MiniRecorderView(
                onLayoutChange: { [weak self] isExpanded, showsTranscript, showsWaveform in
                    self?.setLayout(
                        isExpanded: isExpanded,
                        showsTranscript: showsTranscript,
                        showsWaveform: showsWaveform
                    )
                },
                onClose: { [weak self] in self?.hide() }
            )
                .environmentObject(AppViewModel.shared)
            let hosting = NSHostingController(rootView: root)
            let w = NSPanel(contentViewController: hosting)
            w.styleMask = [.borderless, .nonactivatingPanel]
            w.isFloatingPanel = true
            w.level = .floating
            w.hidesOnDeactivate = false
            w.becomesKeyOnlyIfNeeded = true
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = true
            w.isMovableByWindowBackground = true
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.setContentSize(NSSize(
                width: Layout.width,
                height: Layout.height(
                    isExpanded: false,
                    showsTranscript: AppViewModel.shared.settings.showMiniRecorderTranscript,
                    showsWaveform: AppViewModel.shared.settings.showMiniRecorderWaveform
                )
            ))
            w.center()
            w.isReleasedWhenClosed = false

            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: w,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor [self] in
                    self.window = nil
                    if self.restoreAccessoryOnClose {
                        NSApp.setActivationPolicy(.accessory)
                        self.restoreAccessoryOnClose = false
                    }
                }
            }
            window = w
        }

        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func setLayout(isExpanded: Bool, showsTranscript: Bool, showsWaveform: Bool) {
        guard let window else { return }
        resizeWindow(
            window,
            isExpanded: isExpanded,
            showsTranscript: showsTranscript,
            showsWaveform: showsWaveform
        )
    }

    private func resizeWindow(_ window: NSWindow, isExpanded: Bool, showsTranscript: Bool, showsWaveform: Bool) {
        let nextHeight = Layout.height(
            isExpanded: isExpanded,
            showsTranscript: showsTranscript,
            showsWaveform: showsWaveform
        )
        var frame = window.frame
        let topY = frame.maxY
        frame.size = NSSize(width: Layout.width, height: nextHeight)
        frame.origin.y = topY - nextHeight
        window.setFrame(frame, display: true, animate: true)
    }
}

private struct MiniRecorderView: View {
    @EnvironmentObject private var model: AppViewModel
    @State private var isExpanded: Bool = false
    let onLayoutChange: (Bool, Bool, Bool) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Hide")

                if model.settings.showMiniRecorderStatusPill {
                    StatusPillView(state: model.recordingState)
                }

                if model.settings.showMiniRecorderWaveform {
                    InputLevelMeterView(
                        level: model.inputLevel,
                        waveform: model.inputWaveform,
                        heightScale: 2,
                        isActive: model.recordingState == .recording || model.isMicTesting
                    )
                        .frame(height: MiniRecorderController.Layout.waveformHeight)
                        .frame(minWidth: 90, maxWidth: .infinity)
                } else {
                    Spacer(minLength: 0)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(isExpanded ? "Collapse" : "Expand")

                RecordCircleButton(state: model.recordingState, disabled: model.isMicTesting) {
                    Task { await model.toggleRecordingFromUI() }
                }
            }

            if model.settings.showMiniRecorderTranscript || lastErrorText != nil {
                transcriptLine
            }

            if isExpanded {
                Divider().opacity(0.25)
                expandedContent
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(
            width: MiniRecorderController.Layout.width,
            height: MiniRecorderController.Layout.height(
                isExpanded: isExpanded,
                showsTranscript: showsTranscriptLine,
                showsWaveform: model.settings.showMiniRecorderWaveform
            ),
            alignment: .topLeading
        )
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onChange(of: isExpanded) { _, newValue in
            notifyLayoutChange(isExpanded: newValue)
        }
        .onChange(of: model.settings.showMiniRecorderTranscript) { _, newValue in
            notifyLayoutChange(showsTranscript: newValue || lastErrorText != nil)
        }
        .onChange(of: model.settings.showMiniRecorderWaveform) { _, newValue in
            notifyLayoutChange(showsWaveform: newValue)
        }
        .onChange(of: lastErrorText) { _, newValue in
            notifyLayoutChange(showsTranscript: model.settings.showMiniRecorderTranscript || newValue != nil)
        }
        .task {
            notifyLayoutChange()
        }
    }

    private var showsTranscriptLine: Bool {
        model.settings.showMiniRecorderTranscript || lastErrorText != nil
    }

    private var lastErrorText: String? {
        model.lastPasteError ?? model.lastTranscriptionError
    }

    private func notifyLayoutChange(
        isExpanded: Bool? = nil,
        showsTranscript: Bool? = nil,
        showsWaveform: Bool? = nil
    ) {
        onLayoutChange(
            isExpanded ?? self.isExpanded,
            showsTranscript ?? showsTranscriptLine,
            showsWaveform ?? model.settings.showMiniRecorderWaveform
        )
    }

    @ViewBuilder
    private var transcriptLine: some View {
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
            Text(model.lastTranscript)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        } else if model.recordingState == .recording {
            Text("Listening…")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if model.isMicTesting {
            Text("Testing microphone… speak now")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("After you stop, the last transcript will appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Mic")
                    .font(.caption.weight(.semibold))
                    .frame(width: 60, alignment: .leading)
                    .foregroundStyle(.secondary)
                Picker("Microphone", selection: $model.settings.microphone) {
                    ForEach(model.microphones, id: \.name) { mic in
                        Text(mic.displayName).tag(mic.name)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                Button {
                    Task { await model.testMicrophone() }
                } label: {
                    Text(model.isMicTesting ? "Testing…" : "Test")
                        .frame(minWidth: 54)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.isMicTesting || model.recordingState != .standby)
            }
            .onChange(of: model.settings.microphone) { _, _ in
                model.queuePersistSettings()
            }

            HStack(spacing: 8) {
                Text("Engine")
                    .font(.caption.weight(.semibold))
                    .frame(width: 60, alignment: .leading)
                    .foregroundStyle(.secondary)
                Picker("Engine", selection: $model.settings.engine) {
                    Text("Local Whisper").tag(Engine.localWhisper)
                    Text("Apple Speech").tag(Engine.appleSpeech)
                    Text("OpenAI").tag(Engine.openAI)
                    Text("Groq").tag(Engine.groq)
                }
                .labelsHidden()
                .controlSize(.small)
            }
            .onChange(of: model.settings.engine) { _, _ in
                model.queuePersistSettings()
            }

            HStack(spacing: 8) {
                Text("Transcript")
                    .font(.caption.weight(.semibold))
                    .frame(width: 60, alignment: .leading)
                    .foregroundStyle(.secondary)
                Toggle("Show", isOn: $model.settings.showMiniRecorderTranscript)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                Spacer(minLength: 0)
            }
            .onChange(of: model.settings.showMiniRecorderTranscript) { _, _ in
                model.queuePersistSettings()
            }

            HStack(spacing: 12) {
                Text("Mini UI")
                    .font(.caption.weight(.semibold))
                    .frame(width: 60, alignment: .leading)
                    .foregroundStyle(.secondary)

                Toggle("Status", isOn: $model.settings.showMiniRecorderStatusPill)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Toggle("Wave", isOn: $model.settings.showMiniRecorderWaveform)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Spacer(minLength: 0)
            }
            .onChange(of: model.settings.showMiniRecorderStatusPill) { _, _ in
                model.queuePersistSettings()
            }
            .onChange(of: model.settings.showMiniRecorderWaveform) { _, _ in
                model.queuePersistSettings()
            }

            if model.settings.engine == .localWhisper {
                HStack(spacing: 8) {
                    Text("Model")
                        .font(.caption.weight(.semibold))
                        .frame(width: 60, alignment: .leading)
                        .foregroundStyle(.secondary)
                    Picker("Model", selection: $model.settings.whisperModel) {
                        Text("Small (~466 MB)").tag(WhisperModel.small)
                        Text("Medium (~1.5 GB)").tag(WhisperModel.medium)
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    if !model.isSelectedModelDownloaded {
                        Button {
                            Task { await model.downloadSelectedModel() }
                        } label: {
                            Text(model.downloadState.isBusy ? "…" : "Download")
                                .frame(minWidth: 72)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(model.downloadState.isBusy)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .onChange(of: model.settings.whisperModel) { _, _ in
                    model.queuePersistSettings()
                }
                if case .downloading(let phase, let pct) = model.downloadState {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(phase).font(.caption2).foregroundStyle(.secondary)
                        ProgressView(value: pct).controlSize(.mini)
                    }
                    .padding(.leading, 68)
                }
            }
        }
    }

}

private struct RecordCircleButton: View {
    let state: RecordingState
    let disabled: Bool
    let onTap: () -> Void

    private let container: CGFloat = 40

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.secondary.opacity(0.35), lineWidth: 1.5)
                .frame(width: container, height: container)
                .opacity(isRecording ? 0 : 1)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fillColor)
                .frame(width: shapeSize, height: shapeSize)
                .shadow(color: .black.opacity(0.15), radius: 1.5, y: 0.5)
        }
        .frame(width: container, height: container)
        .contentShape(Rectangle())
        .opacity(disabled || state == .analyzing ? 0.55 : 1)
        .onTapGesture {
            guard !disabled, state != .analyzing else { return }
            onTap()
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: state)
        .help(helpText)
    }

    private var isRecording: Bool { state == .recording }

    private var shapeSize: CGFloat {
        isRecording ? container * 0.95 : container * 0.55
    }

    private var cornerRadius: CGFloat {
        isRecording ? 6 : container / 2
    }

    private var fillColor: Color {
        isRecording ? Color(nsColor: .tertiaryLabelColor) : Color.red
    }

    private var helpText: String {
        switch state {
        case .standby: return "Start recording"
        case .recording: return "Stop recording"
        case .analyzing: return "Working…"
        }
    }
}
