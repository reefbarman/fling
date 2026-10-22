import AppKit
import Foundation

struct BrowserTarget: Codable, Identifiable, Equatable {
    struct ChromeProfile: Codable, Equatable {
        var profileDirectory: String
        var profileName: String
    }

    let id: String
    var displayName: String
    var bundleIdentifier: String
    var applicationName: String
    var profile: ChromeProfile?
    var isEnabled: Bool

    var supportsProfiles: Bool {
        ChromiumSupport.supportsProfiles(bundleIdentifier: bundleIdentifier)
    }

    var subtitle: String {
        if let profile {
            return profile.profileName
        }
        if displayName == applicationName {
            return ""
        }
        return applicationName
    }

    private static let iconCache = NSCache<NSString, NSImage>()

    var icon: NSImage? {
        let key = bundleIdentifier as NSString
        if let cached = Self.iconCache.object(forKey: key) {
            return cached
        }
        guard let appURL = BrowserLauncher.applicationURL(forBundleIdentifier: bundleIdentifier)
        else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        Self.iconCache.setObject(icon, forKey: key)
        return icon
    }
}
