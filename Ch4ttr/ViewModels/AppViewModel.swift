import AppKit
import AVFoundation
import Combine
import Foundation
import os

/// App-wide state + orchestration (record/transcribe/paste, profiles, hotkeys).
@MainActor
final class AppViewModel: ObservableObject {
    static let shared = AppViewModel()
    private static let logger = Logger(subsystem: "com.michaelMartell.Ch4ttr", category: "AppViewModel")

    // MARK: - Navigation/UI
    @Published var selectedSection: SettingsSection = .general

    // MARK: - Profiles (local)
    @Published private(set) var users: [UserProfile] = []
    @Published private(set) var selectedUserId: UUID?

    // MARK: - Per-user editable state
    @Published var settings: AppSettings = .defaultValue
    @Published var dictionary: [DictionaryEntry] = []

    // MARK: - Devices + state
    @Published private(set) var microphones: [Microphone] = []
    @Published private(set) var recordingState: RecordingState = .standby

    // MARK: - Engine UX
    @Published private(set) var downloadState: DownloadState = .idle
    @Published private(set) var isSelectedModelDownloaded: Bool = false

    // MARK: - Verification
    @Published private(set) var lastTranscript: String = ""
    @Published private(set) var lastPasteError: String?
    @Published private(set) var lastTranscriptionError: String?
    @Published private(set) var inputLevel: Double = 0
    @Published private(set) var inputWaveform: [Double] = Array(repeating: 0, count: 24)
    @Published private(set) var livePreviewText: String = ""
    @Published private(set) var isMicTesting: Bool = false

    // MARK: - Services
    private let profilesStore = ProfilesStore()
    private let micProvider = MicrophoneProvider()
    private let modelStore = ModelStore()
    private let downloader = ModelDownloader()
    private let overlay = OverlayController()
    private let hotkey = GlobalHotkeyManager()
    private let longHoldMonitor = LongHoldModifierMonitor()
    private let recorder = AudioRecorder()
    private let groq = GroqTranscriber()
    private let local = LocalWhisperTranscriber()
    private let liveSpeech = AppleSpeechStreamingTranscriber()
    private let cleanup = CleanupService()
    private let voiceCommands = VoiceCommandService()
    private let paste = PasteService()
    private let mini = MiniRecorderController.shared
    private let permissions = PermissionsService()

    private var didStartup = false
    private var liveSpeechRunning = false
    private var useLiveInsertionForCurrentRecording = false
    private var lastLiveInsertedText = ""
    /// Apple Speech often restarts `formattedString` after a pause; we keep finalized / prior-phrase text here and only treat the latest phrase as unstable.
    private var liveStableTranscriptPrefix = ""
    private var liveUnstableTranscriptSuffix = ""
    private var isStoppingFromVoiceCommand = false
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        // Persist dictionary edits safely without triggering SwiftUI update warnings.
        $dictionary
            .dropFirst()
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.persistDictionary()
            }
            .store(in: &cancellables)
    }

    func startup() async {
        if didStartup { return }
        didStartup = true

        let state = profilesStore.load()
        users = state.users
        selectedUserId = state.selectedUserId
        applySelectedUserToPublishedState()

        microphones = micProvider.listMicrophones(preferredName: settings.microphone)
        if !microphones.contains(where: { $0.name == settings.microphone }) {
            settings.microphone = microphones.first?.name ?? "default"
            persistSettings()
        }

        overlay.show()
        refreshModelDownloadedFlag()

        hotkey.setHandler { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                await self.handleHotkey(event: event)
            }
        }
        hotkey.register(hotkey: settings.hotkey)
        configureLongHoldMonitor()
    }

    // MARK: - Profiles
    func selectUser(_ id: UUID) {
        selectedUserId = id
        applySelectedUserToPublishedState()
        persistProfiles()
    }

    func persistSettings() {
        writeBackPublishedStateToSelectedUser()
        persistProfiles()
        hotkey.register(hotkey: settings.hotkey)
        configureLongHoldMonitor()
        refreshModelDownloadedFlag()
    }

    private func configureLongHoldMonitor() {
        longHoldMonitor.configure(
            state: { [weak self] in
                guard let self else { return (false, .shift, 2) }
                let d = self.settings.longHoldDurationSeconds
                let clamped = min(10, max(0.5, d))
                return (
                    self.settings.longHoldTriggerEnabled,
                    self.settings.longHoldModifier,
                    clamped
                )
            },
            onThreshold: { [weak self] in
                Task { @MainActor in
                    await self?.handleLongHoldThreshold()
                }
            },
            onReleaseAfterThreshold: { [weak self] in
                Task { @MainActor in
                    await self?.handleLongHoldReleaseAfterThreshold()
                }
            }
        )
    }

    private func handleLongHoldThreshold() async {
        switch settings.recordingMode {
        case .toggle:
            await toggleRecording(mode: .toggle)
        case .pushToTalk:
            await toggleRecording(mode: .pushToTalkPressed)
        }
    }

    private func handleLongHoldReleaseAfterThreshold() async {
        guard settings.recordingMode == .pushToTalk else { return }
        await toggleRecording(mode: .pushToTalkReleased)
    }

    /// Use from SwiftUI `onChange` and custom `Binding` setters. Running `persistSettings()` in the
    /// same update cycle as a `$model.settings` change triggers “Publishing from within view updates.”
    func queuePersistSettings() {
        Task { @MainActor in
            self.persistSettings()
        }
    }

    /// Same as `selectUser` but safe when invoked from a view update / binding.
    func queueSelectUser(_ id: UUID) {
        Task { @MainActor in
            self.selectUser(id)
        }
    }

    func persistDictionary() {
        writeBackPublishedStateToSelectedUser()
        persistProfiles()
    }

    // MARK: - Recording
    func toggleRecordingFromUI() async {
        await toggleRecording(mode: .toggle)
    }

    private func handleHotkey(event: HotkeyEvent) async {
        switch settings.recordingMode {
        case .toggle:
            guard event == .pressed else { return }
            await toggleRecording(mode: .toggle)
        case .pushToTalk:
            switch event {
            case .pressed:
                await toggleRecording(mode: .pushToTalkPressed)
            case .released:
                await toggleRecording(mode: .pushToTalkReleased)
            }
        }
    }

    private enum ToggleMode {
        case toggle
        case pushToTalkPressed
        case pushToTalkReleased
    }

    private func toggleRecording(mode: ToggleMode) async {
        switch mode {
        case .toggle:
            switch recordingState {
            case .standby:
                await startRecording()
            case .recording:
                await stopAndTranscribe()
            case .analyzing:
                NSSound.beep()
            }
        case .pushToTalkPressed:
            if recordingState == .standby { await startRecording() }
        case .pushToTalkReleased:
            if recordingState == .recording { await stopAndTranscribe() }
        }
    }

    private func startRecording() async {
        lastPasteError = nil
        lastTranscriptionError = nil
        lastTranscript = ""
        livePreviewText = ""
        lastLiveInsertedText = ""
        liveStableTranscriptPrefix = ""
        liveUnstableTranscriptSuffix = ""
        isStoppingFromVoiceCommand = false
        useLiveInsertionForCurrentRecording = false

        do {
            if permissions.microphoneStatus() == .denied {
                throw NSError(domain: "Ch4ttr.Permissions", code: 10, userInfo: [
                    NSLocalizedDescriptionKey: "Microphone permission is denied.",
                    NSLocalizedRecoverySuggestionErrorKey: "Open System Settings → Privacy & Security → Microphone and enable Ch4ttr."
                ])
            }

            if settings.engine == .appleSpeech {
                if permissions.speechStatus() == .denied {
                    throw NSError(domain: "Ch4ttr.Permissions", code: 11, userInfo: [
                        NSLocalizedDescriptionKey: "Speech Recognition permission is denied.",
                        NSLocalizedRecoverySuggestionErrorKey: "Open System Settings → Privacy & Security → Speech Recognition and enable Ch4ttr."
                    ])
                }

                switch paste.beginLiveInsertion() {
                case .success:
                    useLiveInsertionForCurrentRecording = true
                case .failure(let err):
                    lastPasteError = err.description
                }

                try await liveSpeech.start(
                    language: settings.language,
                    onTranscript: { [weak self] text, isFinal in
                        Task { @MainActor in
                            self?.handleLiveTranscript(text, isFinal: isFinal)
                        }
                    },
                    onError: { [weak self] error in
                        Task { @MainActor in
                            self?.handleLiveSpeechError(error)
                        }
                    }
                )
                liveSpeechRunning = true
            }
        } catch {
            let message = Self.describe(error: error)
            lastTranscriptionError = message
            Self.logger.error("Start recording failed: \(message, privacy: .public)")
            paste.finishLiveInsertion()
            useLiveInsertionForCurrentRecording = false
            liveSpeech.stop()
            liveSpeechRunning = false
            return
        }

        recordingState = .recording
        overlay.set(state: .recording)
        mini.show()

        do {
            recorder.onLevel = { [weak self] level in
                guard let self else { return }
                Task { @MainActor [self] in
                    self.inputLevel = level
                }
            }
            recorder.onWaveform = { [weak self] bands in
                guard let self else { return }
                Task { @MainActor [self] in
                    self.inputWaveform = bands
                }
            }
            if settings.engine == .appleSpeech {
                recorder.onAudioBuffer = { [weak liveSpeech] buffer in
                    liveSpeech?.append(buffer)
                }
            } else {
                recorder.onAudioBuffer = nil
            }
            try recorder.start(preferredDeviceName: settings.microphone)
        } catch {
            let message = Self.describe(error: error)
            lastTranscriptionError = message
            Self.logger.error("Start recording failed: \(message, privacy: .public)")
            liveSpeech.stop()
            liveSpeechRunning = false
            paste.finishLiveInsertion()
            useLiveInsertionForCurrentRecording = false
            recordingState = .standby
            overlay.set(state: .standby)
            mini.hide()
        }
    }

    private func stopAndTranscribe() async {
        lastPasteError = nil
        lastTranscriptionError = nil
        recordingState = .analyzing
        overlay.set(state: .analyzing)
        mini.show()
        liveSpeech.stop()
        liveSpeechRunning = false
        recorder.onAudioBuffer = nil

        let shouldReplaceLiveInsertion = useLiveInsertionForCurrentRecording
        defer {
            paste.finishLiveInsertion()
            useLiveInsertionForCurrentRecording = false
            lastLiveInsertedText = ""
            liveStableTranscriptPrefix = ""
            liveUnstableTranscriptSuffix = ""
            isStoppingFromVoiceCommand = false
        }

        let tempWav = modelStore.appSupportDirectory.appendingPathComponent("temp_recording.wav")

        do {
            try recorder.stopAndWriteWav(to: tempWav)
            inputLevel = 0
            inputWaveform = Array(repeating: 0, count: inputWaveform.count)

            let rawText: String
            switch settings.engine {
            case .localWhisper:
                let modelURL = modelStore.modelURL(settings.whisperModel)
                let coreURL = modelStore.coreMLEncoderURL(settings.whisperModel)
                rawText = try await local.transcribe(
                    modelURL: modelURL,
                    coreMLEncoderURL: coreURL,
                    audioURL: tempWav,
                    language: settings.language
                )
            case .appleSpeech:
                if permissions.speechStatus() == .denied {
                    throw NSError(domain: "Ch4ttr.Permissions", code: 11, userInfo: [
                        NSLocalizedDescriptionKey: "Speech Recognition permission is denied.",
                        NSLocalizedRecoverySuggestionErrorKey: "Open System Settings → Privacy & Security → Speech Recognition and enable Ch4ttr."
                    ])
                }
                // A second `SFSpeechRecognizer` pass on the WAV often disagrees with the streaming session and replaces
                // good live text with a worse transcript. When live insertion ran, keep what the user already saw.
                if shouldReplaceLiveInsertion {
                    let joined = Self.joinLiveTranscriptSegments(
                        liveStableTranscriptPrefix,
                        liveUnstableTranscriptSuffix
                    )
                    let polished = cleanup.postProcessJoinedLiveDisplay(
                        joined,
                        language: settings.language,
                        dictionary: dictionary
                    )
                    let trimmed = polished.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        rawText = polished
                    } else {
                        rawText = try await AppleSpeechTranscriber().transcribe(audioURL: tempWav, language: settings.language)
                    }
                } else {
                    rawText = try await AppleSpeechTranscriber().transcribe(audioURL: tempWav, language: settings.language)
                }
            case .openAI:
                rawText = try await OpenAITranscriber().transcribe(apiKey: settings.openAIApiKey, audioURL: tempWav, language: settings.language)
            case .groq:
                rawText = try await groq.transcribe(apiKey: settings.groqApiKey, audioURL: tempWav, language: settings.language)
            case .anthropic:
                throw NSError(domain: "Ch4ttr", code: 1, userInfo: [NSLocalizedDescriptionKey: "Anthropic does not provide an audio transcription API. Use Local Whisper, Apple Speech, or OpenAI; then optionally use Anthropic for rewriting."])
            case .localModel:
                throw NSError(domain: "Ch4ttr", code: 2, userInfo: [NSLocalizedDescriptionKey: "Local Model engine is a placeholder. Wire in a Core ML model pipeline for `localModelIdentifier`."])
            }

            try? FileManager.default.removeItem(at: tempWav)

            let voiceCommandResult = voiceCommands.apply(to: rawText)
            performVoiceEditingIntents(voiceCommandResult)
            let commandFilteredText = voiceCommandResult.text
            let cleaned = cleanup.cleanupText(commandFilteredText, language: settings.language, dictionary: dictionary)
            lastTranscript = cleaned
            livePreviewText = ""
            if shouldReplaceLiveInsertion || !cleaned.isEmpty {
                let pasteResult = shouldReplaceLiveInsertion
                    ? paste.replaceLiveInsertion(with: cleaned)
                    : paste.pasteTextAndSimulatePaste(cleaned)
                switch pasteResult {
                case .success:
                    break
                case .failure(let err):
                    lastPasteError = err.description
                }
            }
        } catch {
            let message = Self.describe(error: error)
            lastTranscriptionError = message
            Self.logger.error("Stop/transcribe failed: \(message, privacy: .public)")
            NSSound.beep()
        }

        recordingState = .standby
        overlay.set(state: .standby)
        mini.show()
    }

    private func handleLiveTranscript(_ text: String, isFinal: Bool) {
        guard liveSpeechRunning, settings.engine == .appleSpeech else { return }

        let commandResult = voiceCommands.apply(to: text)
        performVoiceEditingIntents(commandResult)
        let cleaned = cleanup.cleanupStreamingPartial(
            commandResult.text,
            language: settings.language,
            dictionary: dictionary,
            isUtteranceFinal: isFinal
        )
        let allowsEmptyUpdate = commandResult.handledCommand
        if cleaned.isEmpty, !allowsEmptyUpdate, commandResult.editingIntent == nil {
            requestStopFromVoiceCommandIfNeeded(commandResult)
            return
        }

        if cleaned.isEmpty, allowsEmptyUpdate, commandResult.editingIntent == nil {
            liveStableTranscriptPrefix = ""
            liveUnstableTranscriptSuffix = ""
            livePreviewText = ""
            lastTranscript = ""
            if useLiveInsertionForCurrentRecording {
                _ = paste.replaceLiveInsertion(with: "")
            }
            lastLiveInsertedText = ""
            requestStopFromVoiceCommandIfNeeded(commandResult)
            return
        }

        if isFinal {
            liveStableTranscriptPrefix = Self.joinLiveTranscriptSegments(liveStableTranscriptPrefix, cleaned)
            liveUnstableTranscriptSuffix = ""
        } else {
            if liveUnstableTranscriptSuffix.isEmpty {
                liveUnstableTranscriptSuffix = cleaned
            } else {
                let previous = liveUnstableTranscriptSuffix
                let isRefinement = Self.liveTranscriptIsRefinement(previous: previous, next: cleaned)
                if isRefinement {
                    liveUnstableTranscriptSuffix = cleaned
                } else {
                    let split = LiveTranscriptOverlap.splitNonRefinementUpdate(previous: previous, next: cleaned)
                    liveStableTranscriptPrefix = Self.joinLiveTranscriptSegments(liveStableTranscriptPrefix, split.head)
                    liveUnstableTranscriptSuffix = split.tail
                }
            }
        }

        let displayJoined = Self.joinLiveTranscriptSegments(liveStableTranscriptPrefix, liveUnstableTranscriptSuffix)
        let displayPolished = cleanup.postProcessJoinedLiveDisplay(
            displayJoined,
            language: settings.language,
            dictionary: dictionary
        )
        if displayPolished == lastLiveInsertedText {
            requestStopFromVoiceCommandIfNeeded(commandResult)
            return
        }

        livePreviewText = displayPolished
        lastTranscript = displayPolished

        guard useLiveInsertionForCurrentRecording else {
            lastLiveInsertedText = displayPolished
            requestStopFromVoiceCommandIfNeeded(commandResult)
            return
        }

        switch paste.replaceLiveInsertion(with: displayPolished) {
        case .success:
            lastLiveInsertedText = displayPolished
            requestStopFromVoiceCommandIfNeeded(commandResult)
        case .failure(let err):
            lastPasteError = err.description
            requestStopFromVoiceCommandIfNeeded(commandResult)
        }
    }

    /// True when `next` is the same open phrase as `previous`, extended or revised (handles cleanup-added trailing `.` etc.).
    private static func liveTranscriptIsRefinement(previous: String, next: String) -> Bool {
        if next.hasPrefix(previous) || previous.hasPrefix(next) { return true }
        let p = previous.trimmingCharacters(in: .whitespacesAndNewlines).trimmingTrailingSentencePunctuation()
        let n = next.trimmingCharacters(in: .whitespacesAndNewlines).trimmingTrailingSentencePunctuation()
        if p.isEmpty || n.isEmpty { return false }
        return n.hasPrefix(p) || p.hasPrefix(n)
    }

    /// Joins speech segments with a single space when neither side already has boundary whitespace.
    private static func joinLiveTranscriptSegments(_ a: String, _ b: String) -> String {
        let t1 = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let t2 = b.trimmingCharacters(in: .whitespacesAndNewlines)
        if t1.isEmpty { return t2 }
        if t2.isEmpty { return t1 }
        if let c1 = t1.last, c1.isWhitespace { return t1 + t2 }
        if let c2 = t2.first, c2.isWhitespace { return t1 + t2 }
        return t1 + " " + t2
    }

    private func performVoiceEditingIntents(_ result: VoiceCommandService.CommandResult) {
        guard let intent = result.editingIntent else { return }
        Task { @MainActor in
            await self.runVoiceEditingIntent(intent)
        }
    }

    private func runVoiceEditingIntent(_ intent: VoiceEditingIntent) async {
        let outcome: Result<Void, PasteError>
        switch intent {
        case .selectAll:
            outcome = paste.simulateSelectAll()
        case .paste:
            outcome = paste.simulatePasteFromClipboard()
        case .selectParagraph:
            outcome = await paste.simulateSelectParagraphBestEffort()
        case .selectSentence:
            outcome = await paste.simulateSelectSentenceBestEffort()
        }
        if case .failure(let err) = outcome {
            lastPasteError = err.description
        }
    }

    private func requestStopFromVoiceCommandIfNeeded(_ commandResult: VoiceCommandService.CommandResult) {
        guard commandResult.shouldStopRecording, !isStoppingFromVoiceCommand, recordingState == .recording else {
            return
        }

        isStoppingFromVoiceCommand = true
        Task { @MainActor in
            await self.stopAndTranscribe()
        }
    }

    private func handleLiveSpeechError(_ error: Error) {
        guard liveSpeechRunning else { return }
        let message = Self.describe(error: error)
        lastTranscriptionError = message
        Self.logger.error("Live speech recognition failed: \(message, privacy: .public)")
    }

    // MARK: - Mic test
    func testMicrophone() async {
        guard recordingState == .standby, !isMicTesting else { return }
        if permissions.microphoneStatus() == .denied {
            lastTranscriptionError = "Microphone permission is denied. Grant it in System Settings → Privacy & Security → Microphone."
            return
        }
        isMicTesting = true
        lastTranscriptionError = nil

        recorder.onLevel = { [weak self] level in
            guard let self else { return }
            Task { @MainActor [self] in self.inputLevel = level }
        }
        recorder.onWaveform = { [weak self] bands in
            guard let self else { return }
            Task { @MainActor [self] in self.inputWaveform = bands }
        }

        do {
            try recorder.start(preferredDeviceName: settings.microphone)
        } catch {
            lastTranscriptionError = Self.describe(error: error)
            isMicTesting = false
            return
        }

        try? await Task.sleep(for: .seconds(3))

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("mic_test.wav")
        try? recorder.stopAndWriteWav(to: tempURL)
        try? FileManager.default.removeItem(at: tempURL)

        inputLevel = 0
        inputWaveform = Array(repeating: 0, count: inputWaveform.count)
        isMicTesting = false
    }

    // MARK: - Model download
    func refreshModelDownloadedFlag() {
        isSelectedModelDownloaded = modelStore.isModelDownloaded(settings.whisperModel)
    }

    func downloadSelectedModel() async {
        guard settings.engine == .localWhisper else { return }
        if isSelectedModelDownloaded { return }

        downloadState = .downloading(phase: "Whisper model (GGML)", progress: 0)
        do {
            let m = settings.whisperModel
            let willFetchCore = !modelStore.hasCoreMLEncoder(m)
            if !modelStore.hasGgmlModel(m) {
                let url = modelStore.modelDownloadURL(m)
                let dest = modelStore.modelURL(m)
                try await downloader.download(from: url, to: dest) { [weak self] pct in
                    Task { @MainActor in
                        if willFetchCore {
                            self?.downloadState = .downloading(phase: "Whisper model (GGML)", progress: pct * 0.55)
                        } else {
                            self?.downloadState = .downloading(phase: "Whisper model (GGML)", progress: pct)
                        }
                    }
                }
            }

            if !modelStore.hasCoreMLEncoder(m) {
                let (rangeStart, rangeSpan): (Double, Double) = modelStore.hasGgmlModel(m) ? (0, 1) : (0.55, 0.45)
                let zipURL = modelStore.coreMLEncoderZipDownloadURL(m)
                let tempZip = FileManager.default.temporaryDirectory
                    .appendingPathComponent("ch4ttr-coreml-encoder-\(m.rawValue).zip")
                try? FileManager.default.removeItem(at: tempZip)

                try await downloader.download(from: zipURL, to: tempZip) { [weak self] pct in
                    Task { @MainActor in
                        self?.downloadState = .downloading(
                            phase: "Core ML encoder (Neural Engine)",
                            progress: rangeStart + pct * rangeSpan
                        )
                    }
                }
                let encoderDir = modelStore.coreMLEncoderURL(m)
                if FileManager.default.fileExists(atPath: encoderDir.path) {
                    try? FileManager.default.removeItem(at: encoderDir)
                }
                try ModelDownloader.unpackCoreMLEncoderArchive(
                    zipURL: tempZip,
                    into: modelStore.appSupportDirectory
                )
                try? FileManager.default.removeItem(at: tempZip)
            }

            downloadState = .idle
            refreshModelDownloadedFlag()
        } catch {
            downloadState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Private persistence helpers
    private func persistProfiles() {
        guard let selectedUserId else { return }
        profilesStore.save(ProfilesState(selectedUserId: selectedUserId, users: users))
    }

    private func applySelectedUserToPublishedState() {
        guard let id = selectedUserId, let u = users.first(where: { $0.id == id }) else {
            if let first = users.first {
                selectedUserId = first.id
                settings = first.settings
                dictionary = first.dictionary
            } else {
                let fallback = UserProfile(name: "Me", settings: .defaultValue, dictionary: [])
                users = [fallback]
                selectedUserId = fallback.id
                settings = fallback.settings
                dictionary = fallback.dictionary
            }
            return
        }
        settings = u.settings
        dictionary = u.dictionary
        refreshModelDownloadedFlag()
    }

    private func writeBackPublishedStateToSelectedUser() {
        guard let id = selectedUserId, let idx = users.firstIndex(where: { $0.id == id }) else { return }
        users[idx].settings = settings
        users[idx].dictionary = dictionary
    }

    private static func describe(error: Error) -> String {
        // Preserve useful info from bridged Objective‑C errors.
        let ns = error as NSError
        var parts: [String] = []

        if ns.domain != "Swift.CancellationError" {
            parts.append("\(ns.domain) (\(ns.code))")
        }

        if !ns.localizedDescription.isEmpty {
            parts.append(ns.localizedDescription)
        }

        if let reason = ns.localizedFailureReason, !reason.isEmpty {
            parts.append("Reason: \(reason)")
        }
        if let suggestion = ns.localizedRecoverySuggestion, !suggestion.isEmpty {
            parts.append("Suggestion: \(suggestion)")
        }

        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("Underlying: \(underlying.domain) (\(underlying.code)) \(underlying.localizedDescription)")
        }

        // Make Speech failures easier to spot.
        if ns.domain == "com.apple.speech.recognition" || ns.domain.contains("Speech") {
            parts.append("Note: Apple Speech on-device recognition can fail if the language model isn’t available offline.")
        }

        return parts.joined(separator: " — ")
    }
}

private extension String {
    func trimmingTrailingSentencePunctuation() -> String {
        var s = self
        while let last = s.last, last == "." || last == "!" || last == "?" {
            s.removeLast()
        }
        return s
    }
}
