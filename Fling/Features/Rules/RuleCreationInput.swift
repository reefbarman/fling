import Foundation

struct RuleCreationInput: Identifiable {
    enum RuleKind: String, CaseIterable, Identifiable {
        case domain
        case urlRegex

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .domain:
                return "Domain Rule"
            case .urlRegex:
                return "URL Regex Rule"
            }
        }
    }

    var existingRuleID: String?
    var id: String {
        existingRuleID ?? "draft-rule"
    }
    var name: String
    var kind: RuleKind
    var targetID: String
    var domain: String
    var matchSubdomains: Bool
    var regexPattern: String
    var isEnabled: Bool

    init(url: URL, defaultTargetID: String?) {
        self.existingRuleID = nil
        self.name = ""
        self.kind = .domain
        self.targetID = defaultTargetID ?? ""
        self.domain = Self.hostWithPort(of: url)
        self.matchSubdomains = true
        self.regexPattern = NSRegularExpression.escapedPattern(for: url.absoluteString)
        self.isEnabled = true
    }

    /// An empty draft for adding a rule from Settings, with no pre-filled match.
    static func blank(defaultTargetID: String?) -> RuleCreationInput {
        var input = RuleCreationInput(
            url: URL(string: "https://example.com")!, defaultTargetID: defaultTargetID)
        input.domain = ""
        input.regexPattern = ""
        return input
    }

    /// `localhost:3000` when the URL has an explicit port, otherwise just the host.
    static func hostWithPort(of url: URL) -> String {
        guard let host = url.host(percentEncoded: false) else { return "" }
        let formattedHost = host.contains(":") ? "[\(host)]" : host
        guard let port = url.port else { return formattedHost }
        return "\(formattedHost):\(port)"
    }

    init(rule: Rule) {
        switch rule {
        case .domain(let domainRule):
            self.existingRuleID = domainRule.id
            self.name = domainRule.name ?? ""
            self.kind = .domain
            self.targetID = domainRule.targetId
            self.domain = domainRule.domain
            self.matchSubdomains = domainRule.matchSubdomains
            self.regexPattern = ""
            self.isEnabled = domainRule.enabled

        case .urlRegex(let regexRule):
            self.existingRuleID = regexRule.id
            self.name = regexRule.name ?? ""
            self.kind = .urlRegex
            self.targetID = regexRule.targetId
            self.domain = ""
            self.matchSubdomains = true
            self.regexPattern = regexRule.pattern
            self.isEnabled = regexRule.enabled
        }
    }

    func makeRule() throws -> Rule {
        guard !targetID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RuleCreationError.missingTarget
        }

        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedName = normalizedName.isEmpty ? nil : normalizedName

        switch kind {
        case .domain:
            let normalizedDomain = Self.normalizeDomain(domain)
            guard !normalizedDomain.isEmpty, !normalizedDomain.hasPrefix("/") else {
                throw RuleCreationError.invalidDomain
            }

            return .domain(
                DomainRule(
                    id: existingRuleID
                        ?? "domain-\(normalizedDomain)-\(UUID().uuidString.lowercased())",
                    name: storedName,
                    domain: normalizedDomain,
                    matchSubdomains: matchSubdomains,
                    targetId: targetID,
                    enabled: isEnabled
                )
            )

        case .urlRegex:
            let normalizedPattern = regexPattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedPattern.isEmpty else {
                throw RuleCreationError.invalidRegex
            }
            _ = try NSRegularExpression(pattern: normalizedPattern)

            return .urlRegex(
                URLRegexRule(
                    id: existingRuleID ?? "regex-\(UUID().uuidString.lowercased())",
                    name: storedName,
                    pattern: normalizedPattern,
                    targetId: targetID,
                    enabled: isEnabled
                )
            )
        }
    }

    /// Accepts `github.com/reefbarman` as well as a pasted `https://github.com/reefbarman/?tab=repos`,
    /// storing `github.com/reefbarman`.
    static func normalizeDomain(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let schemeRange = value.range(of: "://") {
            value = String(value[schemeRange.upperBound...])
        }
        if let cut = value.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            value = String(value[..<cut])
        }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }
}

enum RuleCreationError: LocalizedError {
    case invalidDomain
    case invalidRegex
    case missingTarget

    var errorDescription: String? {
        switch self {
        case .invalidDomain:
            return "Enter a valid domain."
        case .invalidRegex:
            return "Enter a valid regular expression."
        case .missingTarget:
            return "Choose a target browser or profile."
        }
    }
}
