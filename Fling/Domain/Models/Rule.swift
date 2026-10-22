import Foundation

enum Rule: Codable, Identifiable, Equatable {
    case domain(DomainRule)
    case urlRegex(URLRegexRule)

    enum CodingKeys: String, CodingKey {
        case type
    }

    enum RuleType: String, Codable {
        case domain
        case urlRegex
    }

    var id: String {
        switch self {
        case .domain(let rule):
            return rule.id
        case .urlRegex(let rule):
            return rule.id
        }
    }

    var name: String? {
        switch self {
        case .domain(let rule):
            return rule.name
        case .urlRegex(let rule):
            return rule.name
        }
    }

    var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }

        switch self {
        case .domain(let rule):
            return rule.domain
        case .urlRegex(let rule):
            return rule.pattern
        }
    }

    var targetId: String {
        switch self {
        case .domain(let rule):
            return rule.targetId
        case .urlRegex(let rule):
            return rule.targetId
        }
    }

    var isEnabled: Bool {
        switch self {
        case .domain(let rule):
            return rule.enabled
        case .urlRegex(let rule):
            return rule.enabled
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(RuleType.self, forKey: .type)

        switch type {
        case .domain:
            self = .domain(try DomainRule(from: decoder))
        case .urlRegex:
            self = .urlRegex(try URLRegexRule(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .domain(let rule):
            try rule.encode(to: encoder)
        case .urlRegex(let rule):
            try rule.encode(to: encoder)
        }
    }
}

struct DomainRule: Codable, Identifiable, Equatable {
    enum CodingKeys: String, CodingKey {
        case type
        case id
        case name
        case domain
        case matchSubdomains
        case targetId
        case enabled
    }

    var id: String
    var name: String?
    var domain: String
    var matchSubdomains: Bool
    var targetId: String
    var enabled: Bool

    init(
        id: String,
        name: String? = nil,
        domain: String,
        matchSubdomains: Bool,
        targetId: String,
        enabled: Bool
    ) {
        self.id = id
        self.name = name
        self.domain = domain
        self.matchSubdomains = matchSubdomains
        self.targetId = targetId
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(Rule.RuleType.self, forKey: .type)
        guard type == .domain else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Expected domain rule type"
            )
        }

        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        domain = try container.decode(String.self, forKey: .domain)
        matchSubdomains = try container.decode(Bool.self, forKey: .matchSubdomains)
        targetId = try container.decode(String.self, forKey: .targetId)
        enabled = try container.decode(Bool.self, forKey: .enabled)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Rule.RuleType.domain, forKey: .type)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(domain, forKey: .domain)
        try container.encode(matchSubdomains, forKey: .matchSubdomains)
        try container.encode(targetId, forKey: .targetId)
        try container.encode(enabled, forKey: .enabled)
    }
}

extension DomainRule {
    /// Whether this rule matches a URL. The rule's `domain` may carry a port
    /// (`localhost:8080`), in which case only that port matches; without a port, any port does.
    /// It may also carry a path (`github.com/reefbarman`), in which case only URLs under that
    /// path match, compared per path segment and case-insensitively.
    func matches(_ url: URL) -> Bool {
        guard let host = url.host(percentEncoded: false)?.lowercased() else { return false }

        let (authority, rulePath) = Self.splitAuthorityAndPath(domain.lowercased())
        let (ruleHost, rulePort) = Self.splitHostAndPort(authority)
        if let rulePort, rulePort != Self.effectivePort(of: url) {
            return false
        }

        let isExactMatch = host == ruleHost
        let isSubdomainMatch = matchSubdomains && host.hasSuffix(".\(ruleHost)")
        guard isExactMatch || isSubdomainMatch else { return false }

        guard let rulePath else { return true }
        let urlPath = url.path(percentEncoded: false).lowercased()
        return urlPath == rulePath || urlPath.hasPrefix(rulePath + "/")
    }

    /// The path this rule is limited to (`/reefbarman`), or nil for a whole-domain rule.
    var pathPrefix: String? {
        Self.splitAuthorityAndPath(domain.lowercased()).path
    }

    /// Higher is more specific. A rule limited to a deeper path beats a broader rule for the
    /// same URL, regardless of list order.
    var specificity: Int {
        pathPrefix?.count ?? 0
    }

    /// Splits `github.com/reefbarman/` into (`github.com`, `/reefbarman`). Trailing slashes are
    /// ignored, and a bare `/` means no path restriction.
    static func splitAuthorityAndPath(_ value: String) -> (authority: String, path: String?) {
        guard let slash = value.firstIndex(of: "/") else { return (value, nil) }
        let authority = String(value[..<slash])
        var path = String(value[slash...])
        while path.hasSuffix("/") { path.removeLast() }
        return (authority, path.isEmpty ? nil : path)
    }

    /// Splits `host:port` (or `[ipv6]:port`). Anything that isn't a trailing numeric port is
    /// treated as part of the host.
    static func splitHostAndPort(_ value: String) -> (host: String, port: Int?) {
        var host = value
        var port: Int?

        if let colon = value.lastIndex(of: ":"),
            let parsed = Int(value[value.index(after: colon)...]),
            value.hasPrefix("[") ? value[..<colon].hasSuffix("]") : !value[..<colon].contains(":")
        {
            host = String(value[..<colon])
            port = parsed
        }
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        return (host, port)
    }

    private static func effectivePort(of url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "http": return 80
        case "https": return 443
        default: return nil
        }
    }
}

struct URLRegexRule: Codable, Identifiable, Equatable {
    enum CodingKeys: String, CodingKey {
        case type
        case id
        case name
        case pattern
        case targetId
        case enabled
    }

    var id: String
    var name: String?
    var pattern: String
    var targetId: String
    var enabled: Bool

    init(id: String, name: String? = nil, pattern: String, targetId: String, enabled: Bool) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.targetId = targetId
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(Rule.RuleType.self, forKey: .type)
        guard type == .urlRegex else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Expected urlRegex rule type"
            )
        }

        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        pattern = try container.decode(String.self, forKey: .pattern)
        targetId = try container.decode(String.self, forKey: .targetId)
        enabled = try container.decode(Bool.self, forKey: .enabled)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Rule.RuleType.urlRegex, forKey: .type)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(pattern, forKey: .pattern)
        try container.encode(targetId, forKey: .targetId)
        try container.encode(enabled, forKey: .enabled)
    }
}
