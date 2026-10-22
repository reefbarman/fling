import AppKit
import Foundation

enum ChromiumSupport {
    static let bundleIdentifiers: Set<String> = [
        "com.google.Chrome",
        "com.brave.Browser",
        "com.microsoft.edgemac",
    ]

    static func supportsProfiles(bundleIdentifier: String) -> Bool {
        bundleIdentifiers.contains(bundleIdentifier)
    }

    static func localStatePath(bundleIdentifier: String) -> String? {
        switch bundleIdentifier {
        case "com.google.Chrome":
            return "~/Library/Application Support/Google Chrome/Local State"
        case "com.brave.Browser":
            return "~/Library/Application Support/BraveSoftware/Brave-Browser/Local State"
        case "com.microsoft.edgemac":
            return "~/Library/Application Support/Microsoft Edge/Local State"
        default:
            return nil
        }
    }
}

struct InstalledBrowserApp: Identifiable, Equatable {
    let id: String
    let bundleIdentifier: String
    let name: String
    let appURL: URL
    let icon: NSImage

    var supportsChromeProfiles: Bool {
        ChromiumSupport.supportsProfiles(bundleIdentifier: bundleIdentifier)
    }
}

struct DiscoveredChromeProfile: Identifiable, Equatable {
    let id: String
    let profileDirectory: String
    let profileName: String
}

struct BrowserDiscovery {
    func installedBrowsers() -> [InstalledBrowserApp] {
        let knownBundleIdentifiers = [
            "com.apple.Safari",
            "com.google.Chrome",
            "company.thebrowser.Browser",
            "org.mozilla.firefox",
            "com.brave.Browser",
            "com.microsoft.edgemac",
        ]

        return knownBundleIdentifiers.compactMap { bundleIdentifier in
            guard
                let appURL = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: bundleIdentifier)
            else { return nil }

            let bundle = Bundle(url: appURL)
            let name =
                bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? appURL.deletingPathExtension().lastPathComponent

            return InstalledBrowserApp(
                id: bundleIdentifier,
                bundleIdentifier: bundleIdentifier,
                name: name,
                appURL: appURL,
                icon: NSWorkspace.shared.icon(forFile: appURL.path)
            )
        }
    }

    func chromeProfiles(
        bundleIdentifier: String = "com.google.Chrome",
        overrides: [ChromeProfileOverride]
    ) -> [DiscoveredChromeProfile] {
        let discovered = readLocalStateProfiles(bundleIdentifier: bundleIdentifier)
        let overrideMap = Dictionary(
            uniqueKeysWithValues: overrides.map { ($0.profileDirectory, $0) })

        let merged = discovered.compactMap { profile -> DiscoveredChromeProfile? in
            if let override = overrideMap[profile.profileDirectory], override.hidden {
                return nil
            }

            return DiscoveredChromeProfile(
                id: profile.profileDirectory,
                profileDirectory: profile.profileDirectory,
                profileName: overrideMap[profile.profileDirectory]?.displayName
                    ?? profile.profileName
            )
        }

        let manualOnly = overrides.compactMap { override -> DiscoveredChromeProfile? in
            guard !override.hidden else { return nil }
            guard !merged.contains(where: { $0.profileDirectory == override.profileDirectory })
            else {
                return nil
            }

            return DiscoveredChromeProfile(
                id: override.profileDirectory,
                profileDirectory: override.profileDirectory,
                profileName: override.displayName
            )
        }

        return (merged + manualOnly).sorted {
            $0.profileName.localizedCaseInsensitiveCompare($1.profileName) == .orderedAscending
        }
    }

    private func readLocalStateProfiles(bundleIdentifier: String) -> [DiscoveredChromeProfile] {
        guard let path = ChromiumSupport.localStatePath(bundleIdentifier: bundleIdentifier) else {
            return []
        }

        let expandedPath = NSString(string: path).expandingTildeInPath
        let fileURL = URL(fileURLWithPath: expandedPath)

        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        guard
            let profile = json["profile"] as? [String: Any],
            let infoCache = profile["info_cache"] as? [String: Any]
        else { return [] }

        return infoCache.compactMap { key, value in
            guard let dictionary = value as? [String: Any] else { return nil }
            let name = dictionary["name"] as? String ?? key
            return DiscoveredChromeProfile(id: key, profileDirectory: key, profileName: name)
        }
    }
}
