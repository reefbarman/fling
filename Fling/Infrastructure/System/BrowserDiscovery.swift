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

    /// Candidate user data folders, most likely first. Chrome uses `Google/Chrome`; the
    /// `Google Chrome` spelling is kept as a fallback.
    private static func userDataDirectoryPaths(bundleIdentifier: String) -> [String] {
        switch bundleIdentifier {
        case "com.google.Chrome":
            return [
                "~/Library/Application Support/Google/Chrome",
                "~/Library/Application Support/Google Chrome",
            ]
        case "com.brave.Browser":
            return ["~/Library/Application Support/BraveSoftware/Brave-Browser"]
        case "com.microsoft.edgemac":
            return ["~/Library/Application Support/Microsoft Edge"]
        default:
            return []
        }
    }

    /// The browser's user data folder (the one holding `Local State`), if it exists.
    static func userDataDirectory(bundleIdentifier: String) -> URL? {
        userDataDirectoryPaths(bundleIdentifier: bundleIdentifier)
            .map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
            .first {
                FileManager.default.fileExists(
                    atPath: $0.appendingPathComponent("Local State").path)
            }
    }

    static func localStatePath(bundleIdentifier: String) -> String? {
        userDataDirectory(bundleIdentifier: bundleIdentifier)?
            .appendingPathComponent("Local State").path
    }

    /// The account picture the browser shows for a profile, when the profile is signed in.
    static func profilePicture(bundleIdentifier: String, profileDirectory: String) -> NSImage? {
        guard !profileDirectory.isEmpty,
            let userData = userDataDirectory(bundleIdentifier: bundleIdentifier)
        else {
            return nil
        }
        let profileURL = userData.appendingPathComponent(profileDirectory, isDirectory: true)
        let candidates = [
            "Google Profile Picture.png", "Edge Profile Picture.png", "Brave Profile Picture.png",
        ]
        for name in candidates {
            if let image = NSImage(contentsOf: profileURL.appendingPathComponent(name)) {
                return image
            }
        }
        return nil
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

        let fileURL = URL(fileURLWithPath: path)

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
