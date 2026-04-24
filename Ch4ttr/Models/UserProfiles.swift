import Foundation

struct DictionaryEntry: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var phrase: String
    var replacement: String
    var isEnabled: Bool
    var replacementStrength: Double

    init(
        id: UUID = UUID(),
        phrase: String,
        replacement: String,
        isEnabled: Bool = true,
        replacementStrength: Double = 0.65
    ) {
        self.id = id
        self.phrase = phrase
        self.replacement = replacement
        self.isEnabled = isEnabled
        self.replacementStrength = min(max(replacementStrength, 0), 1)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case phrase
        case replacement
        case isEnabled
        case replacementStrength
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            phrase: try container.decode(String.self, forKey: .phrase),
            replacement: try container.decode(String.self, forKey: .replacement),
            isEnabled: try container.decode(Bool.self, forKey: .isEnabled),
            replacementStrength: try container.decodeIfPresent(Double.self, forKey: .replacementStrength) ?? 0.65
        )
    }
}

struct UserProfile: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var settings: AppSettings
    var dictionary: [DictionaryEntry]

    init(id: UUID = UUID(), name: String, settings: AppSettings, dictionary: [DictionaryEntry] = []) {
        self.id = id
        self.name = name
        self.settings = settings
        self.dictionary = dictionary
    }
}

struct ProfilesState: Codable, Equatable, Sendable {
    var selectedUserId: UUID
    var users: [UserProfile]
}
