import AppKit
import Foundation

struct BrowserTarget: Codable, Identifiable, Equatable {
    struct ChromeProfile: Codable, Equatable {
        var profileDirectory: String
        var profileName: String
    }

    /// Where an enabled target appears in the browser picker.
    enum PickerPlacement: String, CaseIterable, Identifiable {
        case main
        case more
        case hidden

        var id: String { rawValue }

        var title: String {
            switch self {
            case .main: return "Main"
            case .more: return "Under More"
            case .hidden: return "Hidden"
            }
        }
    }

    let id: String
    var displayName: String
    var bundleIdentifier: String
    var applicationName: String
    var profile: ChromeProfile?
    var isEnabled: Bool
    /// Enabled targets that only show after expanding "More" in the picker.
    var showsUnderMore: Bool = false
    /// PNG in `TargetIconStore`'s directory that replaces the browser icon.
    var customIconFileName: String?

    var supportsProfiles: Bool {
        ChromiumSupport.supportsProfiles(bundleIdentifier: bundleIdentifier)
    }

    var pickerPlacement: PickerPlacement {
        get {
            guard isEnabled else { return .hidden }
            return showsUnderMore ? .more : .main
        }
        set {
            isEnabled = newValue != .hidden
            showsUnderMore = newValue == .more
        }
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

    /// The custom icon when one is set, otherwise the browser's app icon.
    var icon: NSImage? {
        customIcon ?? appIcon
    }

    var customIcon: NSImage? {
        guard let customIconFileName else { return nil }
        return TargetIconStore.image(named: customIconFileName)
    }

    var appIcon: NSImage? {
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

extension BrowserTarget {
    private enum CodingKeys: String, CodingKey {
        case id, displayName, bundleIdentifier, applicationName, profile, isEnabled
        case showsUnderMore, customIconFileName
    }

    /// Custom decoding so configs written before the newer fields existed still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        applicationName = try container.decode(String.self, forKey: .applicationName)
        profile = try container.decodeIfPresent(ChromeProfile.self, forKey: .profile)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        showsUnderMore =
            try container.decodeIfPresent(Bool.self, forKey: .showsUnderMore) ?? false
        customIconFileName = try container.decodeIfPresent(
            String.self, forKey: .customIconFileName)
    }
}
