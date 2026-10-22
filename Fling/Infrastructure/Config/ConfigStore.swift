import Foundation

struct ConfigStore {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
        self.fileManager = fileManager
    }

    func configFileURL() throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let directory = appSupport.appendingPathComponent("Fling", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        return directory.appendingPathComponent("config.json")
    }

    func loadOrCreateDefaultConfig() throws -> AppConfig {
        let url = try configFileURL()

        guard fileManager.fileExists(atPath: url.path) else {
            try save(AppConfig.empty)
            return AppConfig.empty
        }

        let data = try Data(contentsOf: url)
        return try decoder.decode(AppConfig.self, from: data)
    }

    func seededConfigIfNeeded(using discovery: BrowserDiscovery = BrowserDiscovery()) throws
        -> AppConfig
    {
        let loaded = try loadOrCreateDefaultConfig()
        guard loaded.targets.isEmpty else { return loaded }

        var seeded = loaded
        seeded.targets = seedTargets(using: discovery)
        try save(seeded)
        return seeded
    }

    func save(_ config: AppConfig) throws {
        let url = try configFileURL()
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }

    private func seedTargets(using discovery: BrowserDiscovery) -> [BrowserTarget] {
        var targets: [BrowserTarget] = []

        if let safari = discovery.installedBrowsers().first(where: {
            $0.bundleIdentifier == "com.apple.Safari"
        }) {
            targets.append(
                BrowserTarget(
                    id: "safari",
                    displayName: safari.name,
                    bundleIdentifier: safari.bundleIdentifier,
                    applicationName: safari.name,
                    profile: nil,
                    isEnabled: true
                )
            )
        }

        let chromeProfiles = discovery.chromeProfiles(overrides: [])
        if !chromeProfiles.isEmpty {
            for profile in chromeProfiles {
                targets.append(
                    BrowserTarget(
                        id:
                            "chrome-\(profile.profileDirectory.lowercased().replacingOccurrences(of: " ", with: "-"))",
                        displayName: profile.profileName,
                        bundleIdentifier: "com.google.Chrome",
                        applicationName: "Google Chrome",
                        profile: BrowserTarget.ChromeProfile(
                            profileDirectory: profile.profileDirectory,
                            profileName: profile.profileName
                        ),
                        isEnabled: true
                    )
                )
            }
        } else if let chrome = discovery.installedBrowsers().first(where: {
            $0.bundleIdentifier == "com.google.Chrome"
        }) {
            targets.append(
                BrowserTarget(
                    id: "chrome",
                    displayName: chrome.name,
                    bundleIdentifier: chrome.bundleIdentifier,
                    applicationName: chrome.name,
                    profile: nil,
                    isEnabled: true
                )
            )
        }

        return targets
    }
}
