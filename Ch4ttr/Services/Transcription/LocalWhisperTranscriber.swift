import Foundation

final class LocalWhisperTranscriber {
    func transcribe(modelURL: URL, coreMLEncoderURL: URL, audioURL: URL, language: AppLanguage) async throws -> String {
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw WhisperError.modelMissing
        }
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: coreMLEncoderURL.path, isDirectory: &isDir) || !isDir.boolValue {
            throw WhisperError.coreMLEncoderMissing
        }

        let binaryURL = try locateWhisperBinary()
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = [
            "-m", modelURL.path,
            "-f", audioURL.path,
            "--no-timestamps",
            "-l", language.rawValue,
        ]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()

        return try await withCheckedThrowingContinuation { cont in
            process.terminationHandler = { p in
                let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                if p.terminationStatus != 0 {
                    cont.resume(throwing: WhisperError.processFailed(stderr.isEmpty ? stdout : stderr))
                    return
                }
                cont.resume(returning: stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    private func locateWhisperBinary() throws -> URL {
        // We ship `whisper-cpp` as an embedded executable.
        // If it’s in "Copy Files → Executables", it ends up beside the main app executable:
        // `Ch4ttr.app/Contents/MacOS/whisper-cpp`
        if let exeDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            let candidate = exeDir.appendingPathComponent("whisper-cpp")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        // Fall back to Resources (useful during dev if it’s copied as a resource).
        if let url = Bundle.main.url(forResource: "whisper-cpp", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }

        throw WhisperError.binaryMissing
    }
}

enum WhisperError: Error, CustomNSError {
    case modelMissing
    case coreMLEncoderMissing
    case binaryMissing
    case processFailed(String)

    static var errorDomain: String { "Ch4ttr.WhisperError" }

    var errorCode: Int {
        switch self {
        case .modelMissing: return 0
        case .coreMLEncoderMissing: return 1
        case .binaryMissing: return 2
        case .processFailed: return 3
        }
    }

    var errorUserInfo: [String: Any] {
        switch self {
        case .modelMissing:
            return [
                NSLocalizedDescriptionKey: "Whisper model file is missing.",
                NSLocalizedRecoverySuggestionErrorKey: "Open Settings → Engine and download/select a Whisper model.",
            ]
        case .coreMLEncoderMissing:
            return [
                NSLocalizedDescriptionKey: "Core ML encoder bundle is missing (required for the bundled Local Whisper).",
                NSLocalizedRecoverySuggestionErrorKey: "Open Settings → Engine and use Download to fetch the Core ML encoder next to the GGML model, or re-download the model.",
            ]
        case .binaryMissing:
            return [
                NSLocalizedDescriptionKey: "Local Whisper binary (`whisper-cpp`) is missing from the app bundle.",
                NSLocalizedRecoverySuggestionErrorKey: "In Xcode, add `whisper-cpp` to the target and copy it via Build Phases → Copy Files (Destination: Executables). Ensure it’s code signed and has executable permissions.",
            ]
        case .processFailed(let details):
            return [
                NSLocalizedDescriptionKey: "Local Whisper failed to run.",
                NSLocalizedFailureReasonErrorKey: details,
            ]
        }
    }
}

