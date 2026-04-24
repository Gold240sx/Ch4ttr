import Foundation

final class SettingsStore {
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> AppSettings {
        let url = configURL()
        guard let data = try? Data(contentsOf: url) else { return .defaultValue }
        return (try? decoder.decode(AppSettings.self, from: data)) ?? .defaultValue
    }

    func save(_ settings: AppSettings) {
        let url = configURL()
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(settings)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Intentionally non-fatal: settings persistence shouldn't crash the app.
        }
    }

    private func configURL() -> URL {
        let base = AppDirectories.appSupportDirectory(appIdentifier: "com.typr.app")
        return base.appendingPathComponent("config.json")
    }
}

enum AppDirectories {
    static func appSupportDirectory(appIdentifier: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(appIdentifier, isDirectory: true)
    }
}

