import AppKit
import Foundation

struct BrowserLauncher {
    private static let chromeBundleIdentifier = "com.google.Chrome"
    private static let chromeApplicationName = "Google Chrome"

    enum LaunchError: LocalizedError {
        case missingApplication(String)
        case missingChromeProfile
        case missingExecutablePath(String)
        case processFailure(String)

        var errorDescription: String? {
            switch self {
            case .missingApplication(let name):
                return "\(name) is not installed."
            case .missingChromeProfile:
                return "No browser profile directory is configured for this target."
            case .missingExecutablePath(let name):
                return "Could not find the executable for \(name)."
            case .processFailure(let message):
                return message
            }
        }
    }

    /// LaunchServices lookups are cheap but not free; cache them since they sit on the hot
    /// path of every dispatched URL. Entries are re-validated in case the app moved.
    private static let applicationURLCache = NSCache<NSString, NSURL>()

    static func applicationURL(forBundleIdentifier bundleIdentifier: String) -> URL? {
        let key = bundleIdentifier as NSString
        if let cached = applicationURLCache.object(forKey: key) as URL?,
            FileManager.default.fileExists(atPath: cached.path)
        {
            return cached
        }

        guard
            let appURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier)
        else {
            applicationURLCache.removeObject(forKey: key)
            return nil
        }
        applicationURLCache.setObject(appURL as NSURL, forKey: key)
        return appURL
    }

    func open(_ url: URL, in target: BrowserTarget) throws {
        guard let appURL = Self.applicationURL(forBundleIdentifier: target.bundleIdentifier)
        else {
            throw LaunchError.missingApplication(target.applicationName)
        }

        if let profile = target.profile, target.supportsProfiles {
            try openProfiledChromium(url, target: target, appURL: appURL, profile: profile)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
    }

    func isGoogleChromeInstalled() -> Bool {
        Self.applicationURL(forBundleIdentifier: Self.chromeBundleIdentifier) != nil
    }

    func openInChromeIncognito(_ url: URL) throws {
        guard let appURL = Self.applicationURL(forBundleIdentifier: Self.chromeBundleIdentifier)
        else {
            throw LaunchError.missingApplication(Self.chromeApplicationName)
        }

        try openChromium(url, appURL: appURL, arguments: ["--incognito", url.absoluteString])
    }

    private func openProfiledChromium(
        _ url: URL,
        target: BrowserTarget,
        appURL: URL,
        profile: BrowserTarget.ChromeProfile
    ) throws {
        try openChromium(
            url,
            appURL: appURL,
            arguments: ["--profile-directory=\(profile.profileDirectory)", url.absoluteString],
            applicationName: target.applicationName
        )
    }

    private func openChromium(
        _ url: URL,
        appURL: URL,
        arguments: [String],
        applicationName: String = Self.chromeApplicationName
    ) throws {
        guard let executableURL = Bundle(url: appURL)?.executableURL else {
            throw LaunchError.missingExecutablePath(applicationName)
        }

        // When the browser is already running, this short-lived process just hands the URL
        // to the existing instance via Chromium's process singleton and exits.
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw LaunchError.processFailure(
                "\(applicationName) launch failed: \(error.localizedDescription)")
        }
    }
}
