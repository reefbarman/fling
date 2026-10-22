import Foundation

enum RouteDecision: Equatable {
    case open(target: BrowserTarget, url: URL, matchedRuleID: String?)
    case openInChromeIncognito(url: URL)
    case presentSelector(url: URL)

    var url: URL {
        switch self {
        case .open(_, let url, _), .openInChromeIncognito(let url), .presentSelector(let url):
            return url
        }
    }
}
