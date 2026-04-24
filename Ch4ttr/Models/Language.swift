import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case hebrew = "he"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .hebrew: return "Hebrew (עברית)"
        }
    }
}

