import Foundation

/// Remembers reset times between refreshes, so a provider that stops reporting
/// one doesn't blank the countdown and force it to be re-derived every time.
///
/// Keyed by provider and `QuotaType.quotaKey` — the identity the app already
/// persists menu-bar quota selections against. Buckets are a display-time
/// construct and deliberately have no presence here: a bucket that splits
/// leaves each member holding its own record.
public protocol ResetRepository: Sendable {

    /// The remembered reset for a quota, if any.
    func storedReset(providerId: String, quotaKey: String) -> StoredReset?

    /// Records a reset, replacing any existing record for that quota.
    func record(_ reset: StoredReset, providerId: String, quotaKey: String)

    /// Forgets a quota's reset — used when the user clears a manual entry.
    func clear(providerId: String, quotaKey: String)
}
