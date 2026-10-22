import Foundation

struct IncomingURLContext: Identifiable, Equatable {
    let id = UUID()
    let originalURL: URL
    let sourceApplication: String?
    let receivedAt: Date
    let forceChromeIncognito: Bool
    var forceSelector: Bool = false
}
