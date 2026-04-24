import AVFoundation
import Foundation

final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var tempPCMURL: URL?
    private var pcmFile: AVAudioFile?
    private let writeQueue = DispatchQueue(label: "ch4ttr.audio.write", qos: .userInitiated)
    private var isCapturing = false
    var onLevel: (@Sendable (Double) -> Void)?
    var onWaveform: (@Sendable ([Double]) -> Void)?
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    private var lastLevelSentAt: CFAbsoluteTime = 0
    private var lastBands: [Double] = Array(repeating: 0, count: 24)
    private var lastAbsMean: Double = 0

    func start(preferredDeviceName: String) throws {
        if engine.isRunning {
            throw RecorderError.alreadyRunning
        }

        try AudioPermission.ensureMicrophonePermission()

        let inputNode = engine.inputNode
        engine.reset()

        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("ch4ttr_pcm.caf")
        tempPCMURL = url
        pcmFile = nil
        isCapturing = true
        lastLevelSentAt = 0
        lastAbsMean = 0
        lastBands = Array(repeating: 0, count: lastBands.count)
        onLevel?(0)
        onWaveform?(lastBands)

        inputNode.removeTap(onBus: 0)
        // Passing `format: nil` avoids tap installation crashes when CoreAudio
        // is mid-reconfiguration (sample rate changes, aggregate devices, etc).
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            if !self.isCapturing { return }

            self.emitLevelIfNeeded(buffer: buffer)
            self.onAudioBuffer?(buffer)

            // AVAudioFile writes aren't guaranteed thread-safe; serialize.
            self.writeQueue.async { [weak self] in
                guard let self else { return }
                if !self.isCapturing { return }
                do {
                    if self.pcmFile == nil, let url = self.tempPCMURL {
                        // Create the file using the *actual* buffer format.
                        self.pcmFile = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
                    }
                    guard let pcmFile = self.pcmFile else { return }
                    try pcmFile.write(from: buffer)
                } catch {
                    // non-fatal
                }
            }
        }

        engine.prepare()
        try engine.start()
    }

    func stopAndWriteWav(to wavURL: URL) throws {
        guard engine.isRunning else { throw RecorderError.notRunning }
        isCapturing = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()

        // Ensure any in-flight writes have finished before reading the file.
        writeQueue.sync { }
        // Force the writer file to close/flush before we reopen it for reading.
        pcmFile = nil

        guard let pcmURL = tempPCMURL else { throw RecorderError.missingTempFile }
        let pcm: AVAudioFile
        do {
            pcm = try AVAudioFile(forReading: pcmURL)
        } catch {
            throw RecorderError.wrap(stage: "readTempPCM", error)
        }

        // Convert to mono 16kHz PCM.
        let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        )!

        guard let converter = AVAudioConverter(from: pcm.processingFormat, to: outFormat) else {
            throw RecorderError.wrap(stage: "createConverter", RecorderError.conversionFailed)
        }

        do {
            try FileManager.default.createDirectory(at: wavURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: wavURL.path) {
                try FileManager.default.removeItem(at: wavURL)
            }
        } catch {
            throw RecorderError.wrap(stage: "prepareWavDestination", error)
        }

        let outFile: AVAudioFile
        do {
            outFile = try AVAudioFile(
                forWriting: wavURL,
                settings: outFormat.settings,
                commonFormat: outFormat.commonFormat,
                interleaved: outFormat.isInterleaved
            )
        } catch {
            throw RecorderError.wrap(stage: "createWavFile", error)
        }

        let bufferCapacity: AVAudioFrameCount = 4096
        let inputBuffer = AVAudioPCMBuffer(pcmFormat: pcm.processingFormat, frameCapacity: bufferCapacity)!

        // Read only the remaining frames each iteration to avoid CoreAudio errors
        // when requesting more frames than remain.
        while pcm.framePosition < pcm.length {
            let remaining = pcm.length - pcm.framePosition
            let toRead = AVAudioFrameCount(min(Int64(bufferCapacity), remaining))
            do {
                try pcm.read(into: inputBuffer, frameCount: toRead)
            } catch {
                throw RecorderError.wrap(stage: "readPCMChunk", error)
            }
            if inputBuffer.frameLength == 0 { break }

            let ratio = outFormat.sampleRate / pcm.processingFormat.sampleRate
            let outFrames = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 16
            let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outFrames)!

            var error: NSError?
            let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return inputBuffer
            }
            if status == .error {
                throw RecorderError.wrap(stage: "convertChunk", error ?? RecorderError.conversionFailed)
            }

            do {
                try outFile.write(from: outBuffer)
            } catch {
                throw RecorderError.wrap(stage: "writeWavChunk", error)
            }
        }

        // Cleanup temp.
        try? FileManager.default.removeItem(at: pcmURL)
        pcmFile = nil
        tempPCMURL = nil
        onAudioBuffer = nil
        onLevel?(0)
        lastAbsMean = 0
        lastBands = Array(repeating: 0, count: lastBands.count)
        onWaveform?(lastBands)
    }

    private func emitLevelIfNeeded(buffer: AVAudioPCMBuffer) {
        let now = CFAbsoluteTimeGetCurrent()
        // Throttle UI updates.
        if now - lastLevelSentAt < 1.0 / 30.0 { return }
        lastLevelSentAt = now

        guard let channel = buffer.floatChannelData?.pointee else { return }
        let frameCount = Int(buffer.frameLength)
        if frameCount == 0 { return }

        var sumSq: Double = 0
        var sumAbs: Double = 0
        var sumDiffSq: Double = 0

        var prev = Double(channel[0])
        for i in 0..<frameCount {
            let x = Double(channel[i])
            sumSq += x * x
            sumAbs += abs(x)
            let d = x - prev
            sumDiffSq += d * d
            prev = x
        }

        let rms = sqrt(sumSq / Double(frameCount))
        let absMean = sumAbs / Double(frameCount)
        let diffRms = sqrt(sumDiffSq / Double(frameCount))

        // UI-friendly scalar level (0...1).
        let level = min(1.0, pow(rms, 0.5))
        onLevel?(level)

        // Cheap "bass → treble" bands without FFT:
        // - low proxy: smoothed absolute mean (envelope)
        // - high proxy: derivative RMS (transient/brightness)
        // - mid proxy: sits between them
        let absSmooth = (0.80 * lastAbsMean) + (0.20 * absMean)
        lastAbsMean = absSmooth

        // Normalize with a real floor so room noise stays as dots, while speech
        // still jumps visibly across the bars.
        let voiceGate = normalized(rms, floor: 0.010, ceiling: 0.075)
        let low = normalized(absSmooth, floor: 0.004, ceiling: 0.050) * voiceGate
        let high = normalized(diffRms, floor: 0.0015, ceiling: 0.020) * voiceGate
        let mid = min(1.0, (normalized(rms, floor: 0.012, ceiling: 0.085) * 0.70) + (voiceGate * 0.30))

        let bandCount = lastBands.count
        var next: [Double] = Array(repeating: 0, count: bandCount)
        for i in 0..<bandCount {
            let t = Double(i) / Double(max(1, bandCount - 1)) // 0...1
            // Tilt energy from low -> high across the bars with a smaller mid
            // contribution, so quiet frequency regions remain visibly quiet.
            let lowWeight = pow(1.0 - t, 1.45)
            let highWeight = pow(t, 1.45)
            let midWeight = sin(t * .pi)
            let body = (low * lowWeight) + (mid * midWeight * 0.42) + (high * highWeight)
            var v = min(1.0, pow(body, 0.72))

            // Smooth with a fast attack + slower decay to feel "audio-like".
            let prevBand = lastBands[i]
            let attack = 0.55
            let decay = 0.18
            if v > prevBand {
                v = prevBand + (v - prevBand) * attack
            } else {
                v = prevBand + (v - prevBand) * decay
            }
            next[i] = v
        }
        lastBands = next
        onWaveform?(next)
    }

    private func normalized(_ value: Double, floor: Double, ceiling: Double) -> Double {
        guard ceiling > floor else { return 0 }
        let scaled = (value - floor) / (ceiling - floor)
        return min(max(scaled, 0), 1)
    }
}

enum RecorderError: Error, CustomNSError {
    case alreadyRunning
    case notRunning
    case missingTempFile
    case conversionFailed
    case stage(String, Error)

    static func wrap(stage: String, _ error: Error) -> RecorderError {
        .stage(stage, error)
    }

    static var errorDomain: String { "Ch4ttr.RecorderError" }

    var errorCode: Int {
        switch self {
        case .alreadyRunning: return 1
        case .notRunning: return 2
        case .missingTempFile: return 3
        case .conversionFailed: return 4
        case .stage: return 100
        }
    }

    var errorUserInfo: [String: Any] {
        switch self {
        case .stage(let stage, let underlying):
            return [
                NSLocalizedDescriptionKey: "Recorder failed during \(stage).",
                NSUnderlyingErrorKey: underlying,
                "stage": stage,
            ]
        default:
            return [NSLocalizedDescriptionKey: String(describing: self)]
        }
    }
}

enum AudioPermission {
    static func ensureMicrophonePermission() throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let sem = DispatchSemaphore(value: 0)
            var granted = false
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                granted = ok
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + 8)
            if !granted { throw PermissionError.microphoneDenied }
        default:
            throw PermissionError.microphoneDenied
        }
    }
}

enum PermissionError: Error {
    case microphoneDenied
}
