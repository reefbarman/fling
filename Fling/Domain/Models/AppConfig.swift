import Foundation

struct AppConfig: Codable, Equatable {
    struct Preferences: Codable, Equatable {
        var launchAtLogin: Bool
    }

    var version: Int
    var preferences: Preferences
    var targets: [BrowserTarget]
    var rules: [Rule]
    var chromeProfileOverrides: [ChromeProfileOverride]

    static let empty = AppConfig(
        version: 1,
        preferences: Preferences(launchAtLogin: false),
        targets: [],
        rules: [],
        chromeProfileOverrides: []
    )
}
