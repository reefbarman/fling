import Foundation

struct ChromeProfileOverride: Codable, Identifiable, Equatable {
    var id: String { profileDirectory }
    var profileDirectory: String
    var displayName: String
    var hidden: Bool
}
