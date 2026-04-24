import Foundation
import Speech

final class AppleSpeechTranscriber {
    func transcribe(audioURL: URL, language: AppLanguage) async throws -> String {
        try await SpeechPermission.ensureSpeechPermission()

        let locale = Locale(identifier: language.rawValue)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw AppleSpeechError.unsupportedLocale
        }
        if !recognizer.isAvailable {
            throw AppleSpeechError.unavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        if #available(macOS 13.0, *) {
            request.requiresOnDeviceRecognition = true
        }

        return try await withCheckedThrowingContinuation { cont in
            var didResume = false
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    if !didResume {
                        didResume = true
                        let ns = error as NSError
                        cont.resume(throwing: AppleSpeechError.recognitionFailed(domain: ns.domain, code: ns.code, message: ns.localizedDescription, userInfo: ns.userInfo))
                    }
                    return
                }
                guard let result else { return }
                if result.isFinal {
                    if !didResume {
                        didResume = true
                        cont.resume(returning: result.bestTranscription.formattedString)
                    }
                }
            }
        }
    }
}

enum AppleSpeechError: Error {
    case unsupportedLocale
    case unavailable
    case recognitionFailed(domain: String, code: Int, message: String, userInfo: [String: Any])
}

enum SpeechPermission {
    static func ensureSpeechPermission() async throws {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return
        case .notDetermined:
            let granted: Bool = await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { status in
                    cont.resume(returning: status == .authorized)
                }
            }
            if !granted { throw PermissionError.speechDenied }
        default:
            throw PermissionError.speechDenied
        }
    }
}

extension PermissionError {
    static let speechDenied = PermissionError.microphoneDenied
}

