import Foundation

final class ProfilesStore {
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> ProfilesState {
        let url = profilesURL()

        if let data = try? Data(contentsOf: url),
           let decoded = try? decoder.decode(ProfilesState.self, from: data),
           decoded.users.isEmpty == false,
           decoded.users.contains(where: { $0.id == decoded.selectedUserId }) {
            return decoded
        }

        // Migration path from the old single-user `config.json`.
        let legacy = SettingsStore().load()
        let user = UserProfile(name: "Me", settings: legacy, dictionary: [])
        let state = ProfilesState(selectedUserId: user.id, users: [user])
        save(state)
        return state
    }

    func save(_ state: ProfilesState) {
        let url = profilesURL()
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(state)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Non-fatal
        }
    }

    private func profilesURL() -> URL {
        let base = AppDirectories.appSupportDirectory(appIdentifier: "com.typr.app")
        return base.appendingPathComponent("profiles.json")
    }
}

