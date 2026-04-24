import Foundation

enum SettingsSection: Hashable {
    case general
    case engine
    case recording
    case permissions
    case dictionary
}

enum RecordingState: String, Sendable {
    case standby
    case recording
    case analyzing
}

enum DownloadState: Equatable {
    case idle
    case downloading(phase: String, progress: Double)
    case failed(String)

    var isBusy: Bool {
        if case .downloading = self { return true }
        return false
    }
}

