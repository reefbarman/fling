import AppKit
import Combine
import Foundation
import os

@MainActor
final class AppCoordinator: ObservableObject {
    static let shared = AppCoordinator.bootstrap()
    @Published private(set) var config: AppConfig
    @Published private(set) var pendingRequests: [IncomingURLContext] = []
    @Published private(set) var lastResolvedRequest: RouteDecision?
    @Published private(set) var activeSelectorContext: IncomingURLContext?
    @Published private(set) var lastErrorMessage: String?

    private let configStore: ConfigStore
    private let routingEngine: RoutingEngine
    private let browserLauncher: BrowserLauncher
    private var interfaceReady = false
    private let logger = Logger(subsystem: "com.tristan.fling", category: "routing")

    init(
        configStore: ConfigStore,
        config: AppConfig,
        routingEngine: RoutingEngine = RoutingEngine(),
        browserLauncher: BrowserLauncher = BrowserLauncher()
    ) {
        self.configStore = configStore
        self.config = config
        self.routingEngine = routingEngine
        self.browserLauncher = browserLauncher
    }

    static func bootstrap() -> AppCoordinator {
        let store = ConfigStore()

        do {
            let config = try store.seededConfigIfNeeded()
            return AppCoordinator(configStore: store, config: config)
        } catch {
            let fallback = AppConfig.empty
            return AppCoordinator(configStore: store, config: fallback)
        }
    }

    func markInterfaceReady() {
        interfaceReady = true
        drainQueueIfPossible()
    }

    func reloadConfig() {
        do {
            config = try configStore.seededConfigIfNeeded()
            lastErrorMessage = nil
            drainQueueIfPossible()
        } catch {
            lastErrorMessage = "Failed to load config: \(error.localizedDescription)"
        }
    }

    /// `~/Library/Application Support/Fling/config.json`, abbreviated for display.
    var configFileDisplayPath: String {
        guard let url = try? configStore.configFileURL() else { return "Unavailable" }
        return (url.path as NSString).abbreviatingWithTildeInPath
    }

    func revealConfigInFinder() {
        do {
            let url = try configStore.configFileURL()
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            lastErrorMessage = "Failed to reveal config: \(error.localizedDescription)"
        }
    }

    func receive(
        url: URL,
        sourceApplication: String?,
        forceChromeIncognito: Bool = NSEvent.modifierFlags.contains(.option),
        forceSelector: Bool = NSEvent.modifierFlags.contains(.shift)
    ) {
        let request = IncomingURLContext(
            originalURL: url,
            sourceApplication: sourceApplication,
            receivedAt: Date(),
            forceChromeIncognito: forceChromeIncognito,
            forceSelector: forceSelector
        )
        pendingRequests.append(request)
        drainQueueIfPossible()
    }

    func routeTestURLString(_ value: String) {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme)
        else {
            lastErrorMessage = "Enter a valid http or https URL."
            return
        }

        receive(url: url, sourceApplication: "manual-test")
    }

    func clearLastError() {
        lastErrorMessage = nil
    }

    func setError(_ message: String) {
        lastErrorMessage = message
    }

    func persistLaunchAtLoginPreference(_ enabled: Bool) throws {
        var updatedConfig = config
        updatedConfig.preferences.launchAtLogin = enabled
        try configStore.save(updatedConfig)
        config = updatedConfig
    }

    func clearLastDecision() {
        lastResolvedRequest = nil
    }

    func openSelectorTarget(_ target: BrowserTarget) {
        guard let request = activeSelectorContext else { return }
        activeSelectorContext = nil
        open(request.originalURL, in: target, matchedRuleID: nil, fallbackRequest: request)
    }

    func copyActiveSelectorURL() {
        guard let url = activeSelectorContext?.originalURL else { return }
        copyToPasteboard(url)
    }

    func openActiveSelectorURLInChromeIncognito() {
        guard let request = activeSelectorContext else { return }
        activeSelectorContext = nil

        do {
            try browserLauncher.openInChromeIncognito(request.originalURL)
            lastResolvedRequest = .openInChromeIncognito(url: request.originalURL)
            drainQueueIfPossible()
        } catch {
            activeSelectorContext = request
            lastErrorMessage = "Failed to open in Chrome Incognito: \(error.localizedDescription)"
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func cancelActiveSelector() {
        guard let request = activeSelectorContext else { return }
        copyToPasteboard(request.originalURL)
        activeSelectorContext = nil
        lastErrorMessage =
            "Selector dismissed. The URL was copied to the clipboard so it is not lost."
        drainQueueIfPossible()
    }

    func saveRuleAndOpen(_ input: RuleCreationInput) {
        guard let request = activeSelectorContext else { return }
        guard let target = config.targets.first(where: { $0.id == input.targetID }) else {
            lastErrorMessage = "Selected target no longer exists."
            return
        }

        do {
            let rule = try input.makeRule()
            var updatedConfig = config

            if let existingRuleID = input.existingRuleID,
                let existingIndex = updatedConfig.rules.firstIndex(where: {
                    $0.id == existingRuleID
                })
            {
                updatedConfig.rules[existingIndex] = rule
            } else {
                updatedConfig.rules.insert(rule, at: 0)
            }

            try configStore.save(updatedConfig)
            config = updatedConfig
            activeSelectorContext = nil
            open(request.originalURL, in: target, matchedRuleID: rule.id, fallbackRequest: request)
        } catch {
            lastErrorMessage = "Failed to save rule: \(error.localizedDescription)"
        }
    }

    func saveRule(_ input: RuleCreationInput) {
        do {
            let rule = try input.makeRule()
            var updatedConfig = config

            if let existingRuleID = input.existingRuleID,
                let existingIndex = updatedConfig.rules.firstIndex(where: {
                    $0.id == existingRuleID
                })
            {
                updatedConfig.rules[existingIndex] = rule
            } else {
                updatedConfig.rules.insert(rule, at: 0)
            }

            try configStore.save(updatedConfig)
            config = updatedConfig
        } catch {
            lastErrorMessage = "Failed to save rule: \(error.localizedDescription)"
        }
    }

    func deleteRule(id: String) {
        do {
            var updatedConfig = config
            updatedConfig.rules.removeAll { $0.id == id }
            try configStore.save(updatedConfig)
            config = updatedConfig
        } catch {
            lastErrorMessage = "Failed to delete rule: \(error.localizedDescription)"
        }
    }

    func deleteRules(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        do {
            var updatedConfig = config
            updatedConfig.rules.removeAll { ids.contains($0.id) }
            try configStore.save(updatedConfig)
            config = updatedConfig
        } catch {
            lastErrorMessage = "Failed to delete rules: \(error.localizedDescription)"
        }
    }

    func moveRules(fromOffsets source: IndexSet, toOffset destination: Int) {
        do {
            var updatedConfig = config
            updatedConfig.rules.move(fromOffsets: source, toOffset: destination)
            try configStore.save(updatedConfig)
            config = updatedConfig
        } catch {
            lastErrorMessage = "Failed to reorder rules: \(error.localizedDescription)"
        }
    }

    func moveTargets(fromOffsets source: IndexSet, toOffset destination: Int) {
        do {
            var updatedConfig = config
            updatedConfig.targets.move(fromOffsets: source, toOffset: destination)
            try configStore.save(updatedConfig)
            config = updatedConfig
        } catch {
            lastErrorMessage = "Failed to reorder targets: \(error.localizedDescription)"
        }
    }

    /// What would happen to this URL right now, without opening anything.
    func previewRoute(for url: URL) -> RouteDecision {
        routingEngine.route(url: url, using: config)
    }

    func saveTarget(_ target: BrowserTarget) {
        do {
            var updatedConfig = config
            updatedConfig.targets.append(target)
            try configStore.save(updatedConfig)
            config = updatedConfig
            pruneUnusedTargetIcons()
        } catch {
            lastErrorMessage = "Failed to save target: \(error.localizedDescription)"
        }
    }

    func updateTarget(_ target: BrowserTarget) {
        do {
            var updatedConfig = config
            guard let index = updatedConfig.targets.firstIndex(where: { $0.id == target.id }) else {
                return
            }
            updatedConfig.targets[index] = target
            try configStore.save(updatedConfig)
            config = updatedConfig
            pruneUnusedTargetIcons()
        } catch {
            lastErrorMessage = "Failed to update target: \(error.localizedDescription)"
        }
    }

    func deleteTarget(id: String) {
        do {
            var updatedConfig = config
            updatedConfig.targets.removeAll { $0.id == id }
            updatedConfig.rules.removeAll { $0.targetId == id }
            try configStore.save(updatedConfig)
            config = updatedConfig
            pruneUnusedTargetIcons()
        } catch {
            lastErrorMessage = "Failed to delete target: \(error.localizedDescription)"
        }
    }

    /// Custom icons are only written when a target is saved, so anything unreferenced after a
    /// save (replaced, reset or deleted) can go.
    private func pruneUnusedTargetIcons() {
        TargetIconStore.removeUnreferenced(
            keeping: Set(config.targets.compactMap(\.customIconFileName)))
    }

    private func drainQueueIfPossible() {
        guard interfaceReady else { return }
        guard activeSelectorContext == nil else { return }
        guard !pendingRequests.isEmpty else { return }

        let next = pendingRequests.removeFirst()

        if next.forceChromeIncognito {
            do {
                try browserLauncher.openInChromeIncognito(next.originalURL)
                lastResolvedRequest = .openInChromeIncognito(url: next.originalURL)
                logTiming("Dispatched to Chrome Incognito", for: next)
                drainQueueIfPossible()
            } catch {
                activeSelectorContext = next
                lastErrorMessage =
                    "Failed to open in Chrome Incognito: \(error.localizedDescription)"
                NSApp.activate(ignoringOtherApps: true)
            }
            return
        }

        // Shift held at intake: skip rules and let the user pick for this click only.
        if next.forceSelector {
            lastResolvedRequest = .presentSelector(url: next.originalURL)
            lastErrorMessage = nil
            activeSelectorContext = next
            logTiming("Presented selector (Shift override)", for: next)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let decision = routingEngine.route(url: next.originalURL, using: config)
        lastResolvedRequest = decision

        switch decision {
        case .open(let target, let url, let matchedRuleID):
            open(url, in: target, matchedRuleID: matchedRuleID, fallbackRequest: next)
        case .openInChromeIncognito:
            assertionFailure("RoutingEngine should not emit .openInChromeIncognito")
            activeSelectorContext = next
            NSApp.activate(ignoringOtherApps: true)
        case .presentSelector:
            lastErrorMessage = nil
            activeSelectorContext = next
            logTiming("Presented selector", for: next)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    var canOpenInChromeIncognito: Bool {
        browserLauncher.isGoogleChromeInstalled()
    }

    var isActiveSelectorContextForceIncognito: Bool {
        activeSelectorContext?.forceChromeIncognito == true
    }

    var isActiveSelectorContextIncognitoUnavailable: Bool {
        isActiveSelectorContextForceIncognito && !canOpenInChromeIncognito
    }

    private func open(
        _ url: URL,
        in target: BrowserTarget,
        matchedRuleID: String?,
        fallbackRequest: IncomingURLContext
    ) {
        do {
            try browserLauncher.open(url, in: target)
            lastResolvedRequest = .open(target: target, url: url, matchedRuleID: matchedRuleID)
            logTiming("Dispatched to \(target.displayName)", for: fallbackRequest)
            drainQueueIfPossible()
        } catch {
            activeSelectorContext = fallbackRequest
            lastErrorMessage = "Failed to open \(target.displayName): \(error.localizedDescription)"
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Time from URL intake to hand-off. For selector picks this includes the time spent
    /// choosing. Inspect with: /usr/bin/log stream --predicate 'subsystem == "com.tristan.fling"'
    private func logTiming(_ event: String, for request: IncomingURLContext) {
        let elapsed = Date().timeIntervalSince(request.receivedAt) * 1000
        logger.notice(
            "\(event, privacy: .public) \(request.originalURL.host ?? "?", privacy: .public) after \(elapsed, format: .fixed(precision: 1), privacy: .public) ms"
        )
    }

    private func copyToPasteboard(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
    }
}
