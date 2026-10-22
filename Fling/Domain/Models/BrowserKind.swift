import Foundation

enum BrowserKind: String, Codable, CaseIterable, Identifiable {
    case safari
    case chrome

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .safari:
            return "Safari"
        case .chrome:
            return "Google Chrome"
        }
    }
}
