import XCTest
import AVFoundation
@testable import Ch4ttr

final class RecordingTests: XCTestCase {
    func testRecordsTwoSecondsProducesAudioFile() async throws {
        let recorder = AudioRecorder()
        let wavURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: wavURL) }

        try recorder.start(preferredDeviceName: "default")
        try await Task.sleep(for: .seconds(2))
        try recorder.stopAndWriteWav(to: wavURL)

        let attrs = try FileManager.default.attributesOfItem(atPath: wavURL.path)
        let byteCount = (attrs[.size] as? Int) ?? 0
        // 2s mono 16kHz int16 = 64,000 bytes PCM + 44-byte WAV header.
        XCTAssertGreaterThan(byteCount, 60_000,
            "Expected ~64 KB WAV for 2s of audio, got \(byteCount) bytes")
    }
}
