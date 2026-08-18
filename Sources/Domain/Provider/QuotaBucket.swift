import Foundation

/// A set of quotas that share one underlying limit.
///
/// Providers that expose usage per model — Antigravity reports a row for every
/// model it offers — usually back several of those rows with a single bucket:
/// spending one model's allowance spends them all. Those rows are identical in
/// value and reset time, so rendering one card per row prints the same fact a
/// dozen times.
///
/// A bucket is a *display-time* construct. It is computed on each render and
/// never stored, so a bucket that splits (some models diverge) simply renders
/// as two cards next time, with each member keeping its own identity and any
/// stored reset. Nothing needs reconciling.
public struct QuotaBucket: Sendable, Equatable, Identifiable {

    /// The quotas sharing this limit, in the order the snapshot listed them.
    /// Never empty.
    public let members: [UsageQuota]

    public init(members: [UsageQuota]) {
        precondition(!members.isEmpty, "A bucket always has at least one member")
        self.members = members
    }

    /// The member whose values the card face shows. Every member carries the
    /// same value and reset by construction, so the first one speaks for all.
    public var representative: UsageQuota { members[0] }

    /// Stable across refreshes as long as membership is stable; membership
    /// changes are exactly when a card should be treated as new.
    public var id: String {
        members.map(\.quotaType.quotaKey).sorted().joined(separator: "+")
    }

    public var memberCount: Int { members.count }

    /// The length of this bucket's window, when it is actually known.
    ///
    /// Deliberately does not fall back to `QuotaType.duration`: that guesses
    /// seven days for model-specific quotas, which would describe a five-hour
    /// Antigravity bucket as weekly. An unknown window stays unknown.
    public var window: TimeInterval? { representative.knownWindow }

    /// Short name for the window, e.g. "5h" or "7d". nil when the window is
    /// unknown — the UI then names the bucket by its membership instead.
    public var windowTitle: String? {
        guard let window else { return nil }
        let hours = Int((window / 3600).rounded())
        if hours >= 24, hours % 24 == 0 { return "\(hours / 24)d" }
        return "\(hours)h"
    }
}

// MARK: - Bucketing

extension UsageSnapshot {

    /// This snapshot's quotas collapsed into one entry per underlying limit.
    public var displayBuckets: [QuotaBucket] {
        quotas.displayBuckets
    }
}

extension Array where Element == UsageQuota {

    /// Quotas collapsed into one entry per underlying limit.
    ///
    /// Two quotas share a bucket when they belong to the same account section,
    /// carry the same remaining value, and reset at the same moment — all
    /// within a tolerance, because separate API rows for one bucket arrive
    /// with timestamps seconds apart and percentages that differ in the noise.
    ///
    /// A quota with no reset time never joins a bucket: not knowing when
    /// something resets is not evidence that it shares a limit.
    public var displayBuckets: [QuotaBucket] {
        /// Timestamps for one bucket can differ by a few seconds across rows.
        let resetTolerance: TimeInterval = 60
        /// Percentages for one bucket can differ in float noise.
        let percentTolerance = 0.5

        var buckets: [[UsageQuota]] = []

        for quota in self {
            guard let reset = quota.resetsAt else {
                buckets.append([quota])
                continue
            }

            let match = buckets.firstIndex { bucket in
                guard let leader = bucket.first, let leaderReset = leader.resetsAt else { return false }
                guard leader.group == quota.group else { return false }
                guard leader.isDollarBased == quota.isDollarBased else { return false }
                guard abs(leaderReset.timeIntervalSince(reset)) <= resetTolerance else { return false }
                return abs(leader.percentRemaining - quota.percentRemaining) <= percentTolerance
            }

            if let match {
                buckets[match].append(quota)
            } else {
                buckets.append([quota])
            }
        }

        return buckets.map(QuotaBucket.init(members:))
    }
}
