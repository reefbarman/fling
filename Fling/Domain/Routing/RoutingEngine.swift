import Foundation

struct RoutingEngine {
    /// Rules are checked in list order and the first match wins, except that a domain rule
    /// limited to a path (`github.com/reefbarman`) beats any less specific match. Among rules
    /// of equal specificity, the earlier one wins.
    func route(url: URL, using config: AppConfig) -> RouteDecision {
        guard url.host(percentEncoded: false) != nil else {
            return .presentSelector(url: url)
        }

        let absoluteURL = url.absoluteString
        var best: (decision: RouteDecision, specificity: Int)?

        for rule in config.rules {
            guard rule.isEnabled else { continue }

            let specificity: Int
            switch rule {
            case .urlRegex(let regexRule):
                guard let regex = try? NSRegularExpression(pattern: regexRule.pattern) else {
                    continue
                }
                let range = NSRange(absoluteURL.startIndex..<absoluteURL.endIndex, in: absoluteURL)
                guard regex.firstMatch(in: absoluteURL, range: range) != nil else { continue }
                specificity = 0

            case .domain(let domainRule):
                guard domainRule.matches(url) else { continue }
                specificity = domainRule.specificity
            }

            guard best == nil || specificity > best!.specificity else { continue }
            guard let target = config.targets.first(where: { $0.id == rule.targetId }) else {
                continue
            }
            best = (.open(target: target, url: url, matchedRuleID: rule.id), specificity)
        }

        return best?.decision ?? .presentSelector(url: url)
    }
}
