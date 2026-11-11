import Foundation

/// Deterministic quota-reset countdown formatting (MJ-103). Pure integer math
/// on an injected instant pair — no ambient clock, so rollover and DST are
/// unit-testable. House wording follows `UsageQuota.compactResetTime` /
/// `resetTimestampDescription` ("2d 5h 30m", "soon").
public enum QuotaCountdownFormatter {
    /// The whole duration from `now` until `resetsAt`, clamped at zero:
    /// "2d 5h 30m", "5h 30m", "30m", "soon" (under a minute).
    public static func countdown(until resetsAt: Date, now: Date) -> String {
        duration(seconds: resetsAt.timeIntervalSince(now))
    }

    /// The shared duration wording, exposed for callers that compute their
    /// own interval (e.g. a live ticker re-rendering one known reset).
    public static func duration(seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let totalMinutes = totalSeconds / 60
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        var parts: [String] = []
        if days > 0 { parts.append("\(days)d") }
        if hours > 0 { parts.append("\(hours)h") }
        if minutes > 0 { parts.append("\(minutes)m") }

        if parts.isEmpty { return "soon" }
        return parts.joined(separator: " ")
    }

    /// The next wall-clock reset at `hour`:`minute` in `timeZone`, strictly
    /// after `now`. Calendar arithmetic in the target zone, so a DST shift
    /// moves the wall-clock hour, never the interval (16:00 stays 16:00).
    public static func nextDailyReset(
        after now: Date,
        hour: Int,
        minute: Int,
        timeZone: TimeZone,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Date {
        var local = calendar
        local.timeZone = timeZone
        var components = local.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0

        let todayAtReset = local.date(from: components) ?? now
        if todayAtReset > now { return todayAtReset }
        return local.date(byAdding: .day, value: 1, to: todayAtReset) ?? todayAtReset
    }
}
