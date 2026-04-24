import Foundation

final class ModelDownloader: NSObject, URLSessionDownloadDelegate {
    private var progressHandler: ((Double) -> Void)?
    private var continuation: CheckedContinuation<Void, Error>?
    private var destinationURL: URL?

    func download(from url: URL, to destinationURL: URL, onProgress: @escaping (Double) -> Void) async throws {
        self.progressHandler = onProgress
        self.destinationURL = destinationURL

        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let configuration = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
            let task = session.downloadTask(with: url)
            task.resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let pct = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler?(pct)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let dest = destinationURL else { return }
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
            continuation?.resume()
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, continuation != nil {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    // MARK: - Core ML encoder zip (HuggingFace)

    /// Unpacks a `ggml-*-encoder.mlmodelc.zip` so the `.mlmodelc` bundle lives under `parentDirectory`.
    static func unpackCoreMLEncoderArchive(zipURL: URL, into parentDirectory: URL) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-o", "-q", zipURL.path, "-d", parentDirectory.path]
        let err = Pipe()
        proc.standardError = err

        do {
            try proc.run()
        } catch {
            throw NSError(
                domain: "Ch4ttr.Unzip",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to start unzip: \(error.localizedDescription)"]
            )
        }
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "unzip failed"
            throw NSError(
                domain: "Ch4ttr.Unzip",
                code: Int(proc.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        }
    }
}

