import Foundation

final class ModelStore {
    var appSupportDirectory: URL {
        AppDirectories.appSupportDirectory(appIdentifier: "com.typr.app")
    }

    func modelURL(_ model: WhisperModel) -> URL {
        appSupportDirectory.appendingPathComponent(modelFilename(model), isDirectory: false)
    }

    /// The compiled Core ML bundle whisper.cpp loads when built with `WHISPER_COREML=1` (sits beside the `.bin`).
    func coreMLEncoderURL(_ model: WhisperModel) -> URL {
        appSupportDirectory
            .appendingPathComponent("ggml-\(model.rawValue)-encoder.mlmodelc", isDirectory: true)
    }

    /// Same directory layout for any on-disk `ggml-*.bin` (e.g. if paths ever diverge from `modelURL`).
    static func coreMLEncoderURL(adjacentToGgmlBin ggmlModelURL: URL) -> URL {
        let name = ggmlModelURL.deletingPathExtension().lastPathComponent
        return ggmlModelURL.deletingLastPathComponent()
            .appendingPathComponent("\(name)-encoder.mlmodelc", isDirectory: true)
    }

    func hasGgmlModel(_ model: WhisperModel) -> Bool {
        FileManager.default.fileExists(atPath: modelURL(model).path)
    }

    func hasCoreMLEncoder(_ model: WhisperModel) -> Bool {
        var isDir: ObjCBool = false
        let p = coreMLEncoderURL(model).path
        return FileManager.default.fileExists(atPath: p, isDirectory: &isDir) && isDir.boolValue
    }

    /// GGML weights + Core ML encoder (required for the Core ML–enabled sidecar build).
    func isModelDownloaded(_ model: WhisperModel) -> Bool {
        hasGgmlModel(model) && hasCoreMLEncoder(model)
    }

    func modelFilename(_ model: WhisperModel) -> String {
        "ggml-\(model.rawValue).bin"
    }

    func modelDownloadURL(_ model: WhisperModel) -> URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(modelFilename(model))")!
    }

    /// HuggingFace hosts zip archives; contents unpack to `ggml-<name>-encoder.mlmodelc/`.
    func coreMLEncoderZipDownloadURL(_ model: WhisperModel) -> URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(model.rawValue)-encoder.mlmodelc.zip")!
    }
}

