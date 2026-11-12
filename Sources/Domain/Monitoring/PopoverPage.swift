import Foundation

/// What the popover shows under its pills: *Home*, *All*, the *Leaderboard*,
/// or one provider — which one is `QuotaMonitor.selectedProviderId`.
public enum PopoverPage: Equatable, Sendable {
    /// The landing (HOME_PAGE_CONTRACT v1): what the app contains, where to
    /// find it, what it can do, what's next. Always offered.
    case home
    case all
    case leaderboard
    case provider

    /// The page that can be shown: All needs two providers, the Leaderboard
    /// needs to be on; Home is always there; otherwise the provider.
    public func shown(allOffered: Bool, leaderboardOn: Bool) -> PopoverPage {
        switch self {
        case .home: .home
        case .all: allOffered ? .all : .provider
        case .leaderboard: leaderboardOn ? .leaderboard : .provider
        case .provider: .provider
        }
    }
}
