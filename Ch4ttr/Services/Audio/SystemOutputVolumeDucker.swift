import AudioToolbox
import CoreAudio
import Foundation

/// Smoothly lowers the **default Mac output device** volume while dictating, then restores the level
/// captured at the start of the session. Uses Core Audio output `kAudioDevicePropertyVolumeScalar` when
/// the device exposes it (built‑in speakers/headphones usually do; some HDMI paths do not).
///
/// Ducking is **relative** (a fraction of whatever the output level was), not a hard mute, with
/// smooth ramps so changes are easy on the ears.
final class SystemOutputVolumeDucker: @unchecked Sendable {
    static let shared = SystemOutputVolumeDucker()

    private let queue = DispatchQueue(label: "ch4ttr.system-output-volume-duck")

    private var session: (savedScalar: Float, deviceID: AudioDeviceID, id: UUID)?

    private init() {}

    /// `relativeLevel` is a fraction of the **current** output volume (e.g. `0.18` → 18% of whatever it was).
    func beginDuckingIfNeeded(
        enabled: Bool,
        relativeLevel: Double,
        rampDuration: TimeInterval,
        sessionID: UUID
    ) {
        guard enabled else { return }
        let clampedLevel = Float(max(0.04, min(0.55, relativeLevel)))
        let ramp = max(0.12, min(1.2, rampDuration))

        queue.async { [weak self] in
            guard let self else { return }

            // If a prior duck never got an `end` (crash, race), restore before starting a new ramp.
            if let (orphanSaved, orphanDev, _) = self.session {
                self.session = nil
                let now = Self.readVolumeScalar(deviceID: orphanDev) ?? orphanSaved
                Self.rampVolume(deviceID: orphanDev, from: now, to: orphanSaved, duration: min(ramp, 0.28))
            }

            guard let deviceID = Self.defaultOutputDeviceID() else { return }
            guard Self.isVolumeScalarWritable(deviceID: deviceID) else { return }

            guard let current = Self.readVolumeScalar(deviceID: deviceID) else { return }
            let target = max(0.02, min(1, current * clampedLevel))
            if abs(current - target) < 0.02 {
                return
            }

            self.session = (current, deviceID, sessionID)
            Self.rampVolume(deviceID: deviceID, from: current, to: target, duration: ramp)
        }
    }

    /// Ramps back to the saved level from whatever the device is at now (handles interrupted ramps).
    func endDuckingIfNeeded(rampDuration: TimeInterval, sessionID: UUID) {
        let ramp = max(0.12, min(1.2, rampDuration))

        queue.async { [weak self] in
            guard let self else { return }
            guard let (saved, deviceID, id) = self.session, id == sessionID else { return }
            self.session = nil

            guard Self.isVolumeScalarWritable(deviceID: deviceID) else { return }

            let now = Self.readVolumeScalar(deviceID: deviceID) ?? saved
            Self.rampVolume(deviceID: deviceID, from: now, to: saved, duration: ramp)
        }
    }

    // MARK: - Core Audio

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr else { return nil }
        return deviceID
    }

    private static func volumeScalarAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func isVolumeScalarWritable(deviceID: AudioDeviceID) -> Bool {
        var address = volumeScalarAddress()
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var isSettable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr else { return false }
        return isSettable.boolValue
    }

    private static func readVolumeScalar(deviceID: AudioDeviceID) -> Float? {
        var address = volumeScalarAddress()
        var value: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value
    }

    private static func writeVolumeScalar(deviceID: AudioDeviceID, value: Float) {
        var address = volumeScalarAddress()
        var v = max(0, min(1, value))
        _ = AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &v)
    }

    /// Smoothstep in 0...1.
    private static func smoothstep(_ t: Double) -> Double {
        let x = max(0, min(1, t))
        return x * x * (3 - 2 * x)
    }

    private static func rampVolume(deviceID: AudioDeviceID, from: Float, to: Float, duration: TimeInterval) {
        let duration = max(0.08, duration)
        let steps = 22
        let fromD = Double(from)
        let toD = Double(to)

        for step in 1...steps {
            let t = Double(step) / Double(steps)
            let eased = smoothstep(t)
            let next = Float(fromD + (toD - fromD) * eased)
            writeVolumeScalar(deviceID: deviceID, value: next)
            usleep(useconds_t((duration / Double(steps)) * 1_000_000))
        }
        writeVolumeScalar(deviceID: deviceID, value: to)
    }
}
