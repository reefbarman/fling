import AppKit
import Foundation

@MainActor
final class MenuBarController: NSObject {
    private let coordinator: AppCoordinator
    private let settingsWindowController: SettingsWindowController?
    private let launchAtLoginManager: LaunchAtLoginManager
    private let statusItem: NSStatusItem
    private var launchAtLoginItem: NSMenuItem?

    init(
        coordinator: AppCoordinator,
        settingsWindowController: SettingsWindowController?,
        launchAtLoginManager: LaunchAtLoginManager? = nil
    ) {
        self.coordinator = coordinator
        self.settingsWindowController = settingsWindowController
        self.launchAtLoginManager = launchAtLoginManager ?? LaunchAtLoginManager()
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configure()
    }

    private func configure() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "link", accessibilityDescription: "Fling")
            button.imagePosition = .imageOnly
            button.toolTip = "Fling"
        }

        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(
            title: "Open Settings",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.image = menuIcon("gearshape")
        menu.addItem(settingsItem)

        let reloadItem = NSMenuItem(
            title: "Reload Config",
            action: #selector(reloadConfig),
            keyEquivalent: "r"
        )
        reloadItem.target = self
        reloadItem.image = menuIcon("arrow.clockwise")
        menu.addItem(reloadItem)

        let launchAtLoginEnabled = launchAtLoginManager.isEnabled()
        let launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.image = menuIcon(
            launchAtLoginEnabled ? "checkmark.circle.fill" : "xmark.circle")
        menu.addItem(launchAtLoginItem)
        self.launchAtLoginItem = launchAtLoginItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Fling", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = menuIcon("power")
        menu.addItem(quitItem)

        menu.delegate = self
        statusItem.menu = menu
    }

    private func menuIcon(_ systemName: String) -> NSImage? {
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)
        image?.size = NSSize(width: 14, height: 14)
        return image
    }

    @objc private func openSettings() {
        NSApp.setActivationPolicy(.regular)
        settingsWindowController?.show()
    }

    @objc private func reloadConfig() {
        coordinator.reloadConfig()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let newValue = !launchAtLoginManager.isEnabled()

        do {
            try coordinator.persistLaunchAtLoginPreference(newValue)
            try launchAtLoginManager.setEnabled(newValue)
            rebuildMenu()
        } catch {
            coordinator.setError("Failed to update launch at login: \(error.localizedDescription)")
            rebuildMenu()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension MenuBarController: NSMenuDelegate {
    /// Launch at login can also be toggled from Settings, so re-read it each time the menu opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        launchAtLoginItem?.image = menuIcon(
            launchAtLoginManager.isEnabled() ? "checkmark.circle.fill" : "xmark.circle")
    }
}
