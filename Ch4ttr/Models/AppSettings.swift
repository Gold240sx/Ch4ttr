import Foundation

struct AppSettings: Codable, Equatable, Sendable {
    var microphone: String
    var engine: Engine
    var whisperModel: WhisperModel
    var groqApiKey: String
    var openAIApiKey: String
    var anthropicApiKey: String
    var localModelIdentifier: String
    var language: AppLanguage
    var recordingMode: RecordingMode
    var hotkey: Hotkey
    /// Hold this modifier alone for `longHoldDurationSeconds` to act like the hotkey (toggle once, or push-to-talk press / release).
    var longHoldTriggerEnabled: Bool
    var longHoldModifier: LongHoldModifierKey
    /// Seconds the modifier must stay down before firing (clamped when applied).
    var longHoldDurationSeconds: Double
    var showMiniRecorderTranscript: Bool
    var showMiniRecorderStatusPill: Bool
    var showMiniRecorderWaveform: Bool
    /// When true, smoothly lowers the default Mac **output** volume while the mic is recording (not a full mute).
    var duckMacSystemOutputWhileRecording: Bool
    /// Target level as a fraction of the output volume **before** dictation starts (e.g. `0.18` ≈ 18%).
    var macSystemOutputDuckRelativeLevel: Double
    /// Seconds for each fade when ducking and when restoring (smoothstep ramp).
    var macSystemOutputVolumeRampSeconds: Double

    init(
        microphone: String,
        engine: Engine,
        whisperModel: WhisperModel,
        groqApiKey: String,
        openAIApiKey: String,
        anthropicApiKey: String,
        localModelIdentifier: String,
        language: AppLanguage,
        recordingMode: RecordingMode,
        hotkey: Hotkey,
        longHoldTriggerEnabled: Bool = false,
        longHoldModifier: LongHoldModifierKey = .shift,
        longHoldDurationSeconds: Double = 2,
        showMiniRecorderTranscript: Bool = false,
        showMiniRecorderStatusPill: Bool = true,
        showMiniRecorderWaveform: Bool = true,
        duckMacSystemOutputWhileRecording: Bool = false,
        macSystemOutputDuckRelativeLevel: Double = 0.18,
        macSystemOutputVolumeRampSeconds: Double = 0.42
    ) {
        self.microphone = microphone
        self.engine = engine
        self.whisperModel = whisperModel
        self.groqApiKey = groqApiKey
        self.openAIApiKey = openAIApiKey
        self.anthropicApiKey = anthropicApiKey
        self.localModelIdentifier = localModelIdentifier
        self.language = language
        self.recordingMode = recordingMode
        self.hotkey = hotkey
        self.longHoldTriggerEnabled = longHoldTriggerEnabled
        self.longHoldModifier = longHoldModifier
        self.longHoldDurationSeconds = longHoldDurationSeconds
        self.showMiniRecorderTranscript = showMiniRecorderTranscript
        self.showMiniRecorderStatusPill = showMiniRecorderStatusPill
        self.showMiniRecorderWaveform = showMiniRecorderWaveform
        self.duckMacSystemOutputWhileRecording = duckMacSystemOutputWhileRecording
        self.macSystemOutputDuckRelativeLevel = macSystemOutputDuckRelativeLevel
        self.macSystemOutputVolumeRampSeconds = macSystemOutputVolumeRampSeconds
    }

    static let defaultValue = AppSettings(
        microphone: "default",
        engine: .appleSpeech,
        whisperModel: .small,
        groqApiKey: "",
        openAIApiKey: "",
        anthropicApiKey: "",
        localModelIdentifier: "",
        language: .english,
        recordingMode: .toggle,
        hotkey: Hotkey(
            keyCode: 49, // space
            modifiers: [.command, .shift]
        ),
        longHoldTriggerEnabled: false,
        longHoldModifier: .shift,
        longHoldDurationSeconds: 2,
        showMiniRecorderTranscript: false,
        showMiniRecorderStatusPill: true,
        showMiniRecorderWaveform: true,
        duckMacSystemOutputWhileRecording: false,
        macSystemOutputDuckRelativeLevel: 0.18,
        macSystemOutputVolumeRampSeconds: 0.42
    )

    private enum CodingKeys: String, CodingKey {
        case microphone
        case engine
        case whisperModel
        case groqApiKey
        case openAIApiKey
        case anthropicApiKey
        case localModelIdentifier
        case language
        case recordingMode
        case hotkey
        case longHoldTriggerEnabled
        case longHoldModifier
        case longHoldDurationSeconds
        case showMiniRecorderTranscript
        case showMiniRecorderStatusPill
        case showMiniRecorderWaveform
        case duckMacSystemOutputWhileRecording
        case macSystemOutputDuckRelativeLevel
        case macSystemOutputVolumeRampSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            microphone: try container.decode(String.self, forKey: .microphone),
            engine: try container.decode(Engine.self, forKey: .engine),
            whisperModel: try container.decode(WhisperModel.self, forKey: .whisperModel),
            groqApiKey: try container.decode(String.self, forKey: .groqApiKey),
            openAIApiKey: try container.decode(String.self, forKey: .openAIApiKey),
            anthropicApiKey: try container.decode(String.self, forKey: .anthropicApiKey),
            localModelIdentifier: try container.decode(String.self, forKey: .localModelIdentifier),
            language: try container.decode(AppLanguage.self, forKey: .language),
            recordingMode: try container.decode(RecordingMode.self, forKey: .recordingMode),
            hotkey: try container.decode(Hotkey.self, forKey: .hotkey),
            longHoldTriggerEnabled: try container.decodeIfPresent(Bool.self, forKey: .longHoldTriggerEnabled) ?? false,
            longHoldModifier: try container.decodeIfPresent(LongHoldModifierKey.self, forKey: .longHoldModifier) ?? .shift,
            longHoldDurationSeconds: try container.decodeIfPresent(Double.self, forKey: .longHoldDurationSeconds) ?? 2,
            showMiniRecorderTranscript: try container.decodeIfPresent(Bool.self, forKey: .showMiniRecorderTranscript) ?? false,
            showMiniRecorderStatusPill: try container.decodeIfPresent(Bool.self, forKey: .showMiniRecorderStatusPill) ?? true,
            showMiniRecorderWaveform: try container.decodeIfPresent(Bool.self, forKey: .showMiniRecorderWaveform) ?? true,
            duckMacSystemOutputWhileRecording: try container.decodeIfPresent(Bool.self, forKey: .duckMacSystemOutputWhileRecording) ?? false,
            macSystemOutputDuckRelativeLevel: try container.decodeIfPresent(Double.self, forKey: .macSystemOutputDuckRelativeLevel) ?? 0.18,
            macSystemOutputVolumeRampSeconds: try container.decodeIfPresent(Double.self, forKey: .macSystemOutputVolumeRampSeconds) ?? 0.42
        )
    }
}

enum Engine: String, Codable, Sendable {
    case localWhisper
    case appleSpeech
    case openAI
    case groq
    case anthropic
    case localModel
}

enum WhisperModel: String, Codable, Sendable {
    case small
    case medium
}

enum RecordingMode: String, Codable, Sendable {
    case toggle
    case pushToTalk
}

/// Modifier held alone (no other modifiers) for `longHoldDurationSeconds` to fire the recording trigger.
enum LongHoldModifierKey: String, Codable, Sendable, CaseIterable {
    case shift
    case option
    case control
    case command

    var displayName: String {
        switch self {
        case .shift: return "Shift"
        case .option: return "Option"
        case .control: return "Control"
        case .command: return "Command"
        }
    }
}

struct Hotkey: Codable, Equatable, Sendable {
    var keyCode: Int
    var modifiers: HotkeyModifiers

    var displayString: String {
        modifiers.displayString + KeyCodeNames.name(for: keyCode)
    }
}

struct HotkeyModifiers: OptionSet, Codable, Equatable, Sendable {
    let rawValue: Int

    static let command = HotkeyModifiers(rawValue: 1 << 0)
    static let option  = HotkeyModifiers(rawValue: 1 << 1)
    static let control = HotkeyModifiers(rawValue: 1 << 2)
    static let shift   = HotkeyModifiers(rawValue: 1 << 3)

    var displayString: String {
        var s = ""
        if contains(.command) { s += "⌘" }
        if contains(.shift) { s += "⇧" }
        if contains(.option) { s += "⌥" }
        if contains(.control) { s += "⌃" }
        return s
    }
}

enum KeyCodeNames {
    static func name(for keyCode: Int) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 51: return "Delete"
        case 48: return "Tab"
        case 53: return "Esc"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            return "Key\(keyCode)"
        }
    }
}
