import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var coordinator: AppCoordinator? {
        didSet {
            guard let coordinator else { return }
            Task { @MainActor in
                coordinator.markInterfaceReady()
                if settingsWindowController == nil {
                    settingsWindowController = SettingsWindowController(coordinator: coordinator)
                }
                if selectorWindowController == nil {
                    // Built eagerly so the first unmatched URL doesn't pay panel setup cost.
                    selectorWindowController = SelectorWindowController(coordinator: coordinator)
                }
                if menuBarController == nil {
                    menuBarController = MenuBarController(
                        coordinator: coordinator,
                        settingsWindowController: settingsWindowController
                    )
                } else {
                    menuBarController?.rebuildMenu()
                }
                flushBufferedURLsIfPossible()
                // Dev aid: `open Fling.app --args -FlingOpenSettingsOnLaunch YES`
                if UserDefaults.standard.bool(forKey: "FlingOpenSettingsOnLaunch") {
                    settingsWindowController?.show()
                }
            }
        }
    }

    private var bufferedURLs: [(url: URL, sourceApplication: String?)] = []
    private var menuBarController: MenuBarController?
    private var settingsWindowController: SettingsWindowController?
    private var selectorWindowController: SelectorWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = AppCoordinator.shared
        NSApp.setActivationPolicy(.accessory)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let sourceApplication = Self.senderApplicationName()
        bufferedURLs.append(contentsOf: urls.map { ($0, sourceApplication) })
        flushBufferedURLsIfPossible()
    }

    @MainActor
    private func flushBufferedURLsIfPossible() {
        guard let coordinator, !bufferedURLs.isEmpty else { return }

        let requests = bufferedURLs
        bufferedURLs.removeAll()

        for request in requests {
            coordinator.receive(url: request.url, sourceApplication: request.sourceApplication)
        }
    }

    /// Best-effort name of the app that asked to open the URL, read from the Apple Event
    /// currently being handled. Only regular (Dock) apps are reported, which filters out
    /// system helpers that sometimes relay the event.
    private static func senderApplicationName() -> String? {
        guard
            let event = NSAppleEventManager.shared().currentAppleEvent,
            let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?
                .int32Value,
            pid > 0,
            let app = NSRunningApplication(processIdentifier: pid),
            app.activationPolicy == .regular
        else { return nil }
        return app.localizedName
    }
}
