import Foundation

// MARK: - Stored Reset

/// Where a remembered reset came from.
public enum ResetSource: String, Sendable, Codable, Equatable {
    /// A value a provider reported at some point.
    case probe
    /// A value the user entered by hand for a provider that reports none.
    case manual
}

/// A reset time the app is holding on to between refreshes, so a provider that
/// goes quiet doesn't blank the countdown and force it to be re-derived.
public struct StoredReset: Sendable, Equatable, Codable {
    public let date: Date
    public let source: ResetSource
    public let recordedAt: Date

    public init(date: Date, source: ResetSource, recordedAt: Date) {
        self.date = date
        self.source = source
        self.recordedAt = recordedAt
    }
}

/// A reset time the UI can show, and whether the app worked it out rather than
/// being told it.
public struct ResolvedReset: Sendable, Equatable {
    public let date: Date
    /// True when the date came from rolling a window forward. The UI marks
    /// these so an inferred countdown can't be mistaken for a reported one.
    public let isExtrapolated: Bool

    public init(date: Date, isExtrapolated: Bool) {
        self.date = date
        self.isExtrapolated = isExtrapolated
    }
}

// MARK: - Resolution

public extension UsageQuota {

    /// The length of this quota's window, when it is actually known.
    ///
    /// Deliberately narrower than `quotaType.duration`, which guesses seven
    /// days for model-specific quotas. Rolling a five-hour Antigravity bucket
    /// forward by that guess would produce a confidently wrong countdown, so
    /// an unknown window stays unknown.
    var knownWindow: TimeInterval? {
        if let windowDuration { return windowDuration }
        switch quotaType {
        case .session: return QuotaDuration.hours(5).seconds
        case .weekly: return QuotaDuration.days(7).seconds
        case .modelSpecific, .timeLimit: return nil
        }
    }

    /// How many windows a remembered *provider* value may be rolled forward
    /// before the app stops claiming to know. A manual entry is exempt: it is
    /// the user's standing answer for a provider that never reports, so
    /// expiring it would defeat the reason it exists.
    private static var extrapolationLimit: Int { 3 }

    /// The reset to display, drawn from the best source available.
    ///
    /// Precedence is: what the provider just reported, then what the user
    /// entered, then what the app remembered. A remembered or entered value
    /// whose moment has passed rolls forward by the window when one is known.
    func resolvedReset(stored: StoredReset?, now: Date = Date()) -> ResolvedReset? {
        // A fresh reading is never second-guessed.
        if let resetsAt {
            return ResolvedReset(date: resetsAt, isExtrapolated: false)
        }

        guard let stored else { return nil }

        // Still ahead of us — show it as given.
        if stored.date > now {
            return ResolvedReset(date: stored.date, isExtrapolated: false)
        }

        // Passed. Rolling forward needs a real window.
        guard let window = knownWindow, window > 0 else { return nil }

        let elapsed = now.timeIntervalSince(stored.date)
        let periods = Int(floor(elapsed / window)) + 1

        if stored.source == .probe, periods > Self.extrapolationLimit {
            return nil
        }

        return ResolvedReset(
            date: stored.date.addingTimeInterval(Double(periods) * window),
            isExtrapolated: true
        )
    }
}

// MARK: - Display

public extension ResolvedReset {

    /// Countdown text for the card's reset line, matching
    /// `UsageQuota.resetTimestampDescription`'s wording.
    ///
    /// Extrapolated values are prefixed with "~" so an inferred countdown
    /// reads differently from one the provider actually reported. The marker
    /// is textual rather than a colour or icon, so it survives every theme and
    /// doesn't add another colour-only signal.
    func description(now: Date = Date()) -> String {
        let remaining = max(0, date.timeIntervalSince(now))
        let totalMinutes = Int(remaining / 60)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        var parts: [String] = []
        if days > 0 { parts.append("\(days)d") }
        if hours > 0 { parts.append("\(hours)h") }
        if minutes > 0 { parts.append("\(minutes)m") }

        let marker = isExtrapolated ? "~" : ""
        if parts.isEmpty { return "\(marker)Resets soon" }
        return "\(marker)Resets in \(parts.joined(separator: " "))"
    }
}
