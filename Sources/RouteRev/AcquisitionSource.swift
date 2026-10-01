import Foundation

/// Answers to "How did you hear about us?". Raw values follow RouteRev's campaign naming
/// convention (the `utm_source` list), so survey answers and campaign links land in the same channels.
public enum AcquisitionSource: String, CaseIterable, Sendable {
    case appStoreSearch = "app_store_search"
    case google
    case x
    case reddit
    case instagram
    case tiktok
    case youtube
    case producthunt
    case newsletter
    case friend
    case other

    /// English label for a survey option.
    public var label: String {
        switch self {
        case .appStoreSearch: return "Searching the App Store"
        case .google: return "Google"
        case .x: return "X (Twitter)"
        case .reddit: return "Reddit"
        case .instagram: return "Instagram"
        case .tiktok: return "TikTok"
        case .youtube: return "YouTube"
        case .producthunt: return "Product Hunt"
        case .newsletter: return "A newsletter"
        case .friend: return "A friend or colleague"
        case .other: return "Somewhere else"
        }
    }
}
