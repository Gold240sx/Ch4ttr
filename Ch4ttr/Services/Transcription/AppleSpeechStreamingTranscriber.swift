import AVFoundation
import Foundation
import Speech

final class AppleSpeechStreamingTranscriber {
    typealias TranscriptHandler = (_ text: String, _ isFinal: Bool) -> Void
    typealias ErrorHandler = (_ error: Error) -> Void

    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isStopping = false

    func start(
        language: AppLanguage,
        onTranscript: @escaping TranscriptHandler,
        onError: @escaping ErrorHandler
    ) async throws {
        stop()
        try await SpeechPermission.ensureSpeechPermission()

        let locale = Locale(identifier: language.rawValue)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw AppleSpeechError.unsupportedLocale
        }
        if !recognizer.isAvailable {
            throw AppleSpeechError.unavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if #available(macOS 13.0, *) {
            request.requiresOnDeviceRecognition = true
        }

        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                onTranscript(result.bestTranscription.formattedString, result.isFinal)
            }

            if let error {
                let shouldReport: Bool
                self?.lock.lock()
                shouldReport = !(self?.isStopping ?? true)
                self?.lock.unlock()

                if shouldReport {
                    onError(error)
                }
            }
        }

        setActive(request: request, task: task)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let request = self.request
        lock.unlock()

        request?.append(buffer)
    }

    func stop() {
        lock.lock()
        isStopping = true
        let request = self.request
        let task = self.task
        self.request = nil
        self.task = nil
        lock.unlock()

        request?.endAudio()
        task?.cancel()
    }

    private func setActive(
        request: SFSpeechAudioBufferRecognitionRequest,
        task: SFSpeechRecognitionTask
    ) {
        lock.lock()
        self.request = request
        self.task = task
        isStopping = false
        lock.unlock()
    }
}
