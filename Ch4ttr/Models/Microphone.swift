import AVFoundation
import Foundation

struct Microphone: Equatable, Sendable {
    var name: String
    var isDefault: Bool

    var displayName: String {
        isDefault ? "\(name) (default)" : name
    }
}

final class MicrophoneProvider {
    func listMicrophones(preferredName: String) -> [Microphone] {
        let devices = AVCaptureDevice.devices(for: .audio)
        let defaultDevice = AVCaptureDevice.default(for: .audio)

        let defaultName = defaultDevice?.localizedName ?? "default"

        var mics: [Microphone] = []
        mics.append(Microphone(name: "default", isDefault: true))

        for d in devices {
            let name = d.localizedName
            mics.append(Microphone(name: name, isDefault: name == defaultName))
        }

        // Stable order: preferred first, then default, then alphabetic.
        return mics
            .uniqued(by: \.name)
            .sorted { a, b in
                if a.name == preferredName { return true }
                if b.name == preferredName { return false }
                if a.name == "default" { return true }
                if b.name == "default" { return false }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }
}

private extension Array {
    func uniqued<T: Hashable>(by key: (Element) -> T) -> [Element] {
        var seen = Set<T>()
        var out: [Element] = []
        out.reserveCapacity(count)
        for e in self {
            let k = key(e)
            if seen.insert(k).inserted {
                out.append(e)
            }
        }
        return out
    }
}

