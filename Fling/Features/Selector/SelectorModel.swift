import AppKit
import Combine

/// Per-presentation state for the selector panel: which target is highlighted, whether the
/// choice should be remembered as a rule, and keyboard handling.
@MainActor
final class SelectorModel: ObservableObject {
    let coordinator: AppCoordinator

    @Published var highlightedIndex = 0
    @Published var remembersChoice = false
    @Published var rememberedDomain = ""
    @Published var isShowingRuleCreation = false
    @Published private(set) var isMoreExpanded = false
    @Published private(set) var domainCandidates: [String] = []

    private var preparedContextID: UUID?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    /// Every target that can be picked, including the ones under More.
    var targets: [BrowserTarget] {
        coordinator.config.targets.filter(\.isEnabled)
    }

    /// Targets shown straight away. If everything is under More, show it all rather than an
    /// empty picker.
    var mainTargets: [BrowserTarget] {
        let main = targets.filter { !$0.showsUnderMore }
        return main.isEmpty ? targets : main
    }

    var moreTargets: [BrowserTarget] {
        mainTargets.count == targets.count ? [] : targets.filter(\.showsUnderMore)
    }

    /// Targets currently on screen, in keyboard/number-shortcut order.
    var visibleTargets: [BrowserTarget] {
        isMoreExpanded ? mainTargets + moreTargets : mainTargets
    }

    var highlightedTarget: BrowserTarget? {
        let visible = visibleTargets
        return visible.indices.contains(highlightedIndex) ? visible[highlightedIndex] : nil
    }

    func toggleMore() {
        guard !moreTargets.isEmpty else { return }
        isMoreExpanded.toggle()
        if isMoreExpanded {
            highlightedIndex = mainTargets.count
        } else if highlightedIndex >= mainTargets.count {
            highlightedIndex = 0
        }
    }

    func prepare(for context: IncomingURLContext) {
        guard context.id != preparedContextID else { return }
        preparedContextID = context.id
        highlightedIndex = 0
        remembersChoice = false
        isShowingRuleCreation = false
        isMoreExpanded = false
        domainCandidates = Self.domainCandidates(for: context.originalURL)
        rememberedDomain = domainCandidates.first ?? ""
    }

    func open(_ target: BrowserTarget) {
        guard let url = coordinator.activeSelectorContext?.originalURL else { return }

        if remembersChoice, !rememberedDomain.isEmpty {
            var input = RuleCreationInput(url: url, defaultTargetID: target.id)
            input.domain = rememberedDomain
            input.matchSubdomains = true
            coordinator.saveRuleAndOpen(input)
        } else {
            coordinator.openSelectorTarget(target)
        }
    }

    func openInIncognito() {
        guard coordinator.canOpenInChromeIncognito else { return }
        coordinator.openActiveSelectorURLInChromeIncognito()
    }

    func dismiss() {
        coordinator.cancelActiveSelector()
    }

    /// Returns true when the event was handled and should not propagate.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard !isShowingRuleCreation else { return false }

        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if modifiers == .command {
            guard characters == "c" else { return false }
            coordinator.copyActiveSelectorURL()
            return true
        }
        guard modifiers.isEmpty else { return false }

        switch event.keyCode {
        case 123, 126:  // left, up
            moveHighlight(by: -1)
        case 124, 125:  // right, down
            moveHighlight(by: 1)
        case 36, 76:  // return, keypad enter
            if let target = highlightedTarget { open(target) }
        case 53:  // escape
            dismiss()
        default:
            let visible = visibleTargets
            if let digit = Int(characters), (1...9).contains(digit), digit <= visible.count {
                open(visible[digit - 1])
            } else if characters == "m", !moreTargets.isEmpty {
                toggleMore()
            } else if characters == "r", !rememberedDomain.isEmpty {
                remembersChoice.toggle()
            } else if characters == "i" {
                openInIncognito()
            } else {
                return false
            }
        }
        return true
    }

    private func moveHighlight(by delta: Int) {
        let count = visibleTargets.count
        guard count > 0 else { return }
        highlightedIndex = (highlightedIndex + delta + count) % count
    }

    /// Candidate domains for a "remember" rule, most specific first, e.g.
    /// `docs.github.com` → [`docs.github.com`, `github.com`] and
    /// `localhost:3000` → [`localhost:3000`, `localhost`]. A leading `www.` is dropped.
    static func domainCandidates(for url: URL) -> [String] {
        guard let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else {
            return []
        }
        let hostCandidates = Self.hostCandidates(for: host)
        guard url.port != nil else { return hostCandidates }
        return [RuleCreationInput.hostWithPort(of: url).lowercased()] + hostCandidates
    }

    private static func hostCandidates(for host: String) -> [String] {
        var labels = host.split(separator: ".").map(String.init)
        let isIPAddress = host.contains(":") || labels.allSatisfy { Int($0) != nil }
        if isIPAddress || labels.count <= 2 {
            return [host]
        }
        if labels.first == "www" {
            labels.removeFirst()
        }
        return (0...(labels.count - 2)).map { labels[$0...].joined(separator: ".") }
    }
}
