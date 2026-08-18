import Foundation

/// What prompted a possible refresh.
public enum RefreshTrigger: Sendable, Equatable {
    /// The user pressed Refresh, or switched to a provider deliberately.
    case userInitiated
    /// The popover opened, or the background loop ticked.
    case automatic
}

/// Decides whether a provider actually needs fetching.
///
/// The app used to fetch on every popover open. For a quota sitting at 100%
/// with five hours left that is a request whose answer cannot be interesting,
/// and it makes the app's reliability depend on a network round trip every
/// time it is looked at.
///
/// The policy is deliberately not "refresh only when a window rolls over": a
/// quota's value moves when the tool is *used*, which the app cannot observe.
/// So a staleness bound still applies — it just gets much longer when nothing
/// is close to resetting.
public enum RefreshPolicy {

    /// A quota resetting within this window counts as active: its value is
    /// about to jump, and usage is likely being spent against it right now.
    public static let activeWindow: TimeInterval = 30 * 60

    /// How stale data may get while a reset is close.
    public static let activeMaxAge: TimeInterval = 2 * 60

    /// How stale data may get when nothing is near resetting.
    public static let idleMaxAge: TimeInterval = 30 * 60

    /// Whether this provider should be fetched.
    ///
    /// - Parameters:
    ///   - lastFetchedAt: when the provider last returned a snapshot, nil if never.
    ///   - quotas: the quotas from that snapshot.
    ///   - hasError: whether the provider's last attempt failed.
    ///   - trigger: what prompted the check.
    public static func shouldRefresh(
        lastFetchedAt: Date?,
        quotas: [UsageQuota],
        hasError: Bool,
        trigger: RefreshTrigger,
        now: Date = Date()
    ) -> Bool {
        // An explicit ask is always honoured.
        if trigger == .userInitiated { return true }

        // A broken provider is exactly the state worth re-checking, and
        // failing providers are rare enough that retrying them is cheap.
        if hasError { return true }

        // Nothing to serve yet.
        guard let lastFetchedAt else { return true }

        // A reset fell between the last fetch and now, so the numbers on
        // screen are known to be wrong rather than merely old.
        if quotas.contains(where: { quota in
            guard let resetsAt = quota.resetsAt else { return false }
            return resetsAt > lastFetchedAt && resetsAt <= now
        }) {
            return true
        }

        let age = now.timeIntervalSince(lastFetchedAt)
        return age >= maxAge(for: quotas, now: now)
    }

    /// The staleness bound for this snapshot — short while a reset is near,
    /// long when every window is comfortably far off.
    public static func maxAge(for quotas: [UsageQuota], now: Date = Date()) -> TimeInterval {
        let nearReset = quotas.contains { quota in
            guard let resetsAt = quota.resetsAt else { return false }
            let remaining = resetsAt.timeIntervalSince(now)
            return remaining >= 0 && remaining <= activeWindow
        }
        return nearReset ? activeMaxAge : idleMaxAge
    }
}
