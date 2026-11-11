import Foundation
import Observation

/// One reset alert a destination hears (MJ-103): a login's quota window is
/// about to turn, or just turned. Dedup is the decider's job — a destination
/// only words it.
public struct QuotaResetAlert: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable {
        /// Within the hour.
        case within60Minutes
        /// Within ten minutes.
        case within10Minutes
        /// The window just turned.
        case resetNow
    }

    public let login: String
    public let providerId: String
    public let kind: Kind
    /// The reset instant the alert speaks about — part of the dedup identity.
    public let resetsAt: Date
    /// The formatted countdown at the moment it was decided.
    public let countdownText: String

    public init(login: String, providerId: String, kind: Kind, resetsAt: Date, countdownText: String) {
        self.login = login
        self.providerId = providerId
        self.kind = kind
        self.resetsAt = resetsAt
        self.countdownText = countdownText
    }

    public var id: String {
        "\(login)|\(providerId)|\(kind.rawValue)|\(Int(resetsAt.timeIntervalSince1970))"
    }
}

/// A live countdown for the popover HUD (MJ-103): what the person's quota
/// windows are doing to their clocks between refreshes.
public struct QuotaResetCountdown: Sendable, Equatable, Identifiable {
    public let id: String
    public let login: String
    public let providerId: String
    public let resetsAt: Date
    /// The countdown at the refresh that produced it.
    public let countdownText: String

    public init(id: String, login: String, providerId: String, resetsAt: Date, countdownText: String) {
        self.id = id
        self.login = login
        self.providerId = providerId
        self.resetsAt = resetsAt
        self.countdownText = countdownText
    }
}

/// Where reset alerts go. Beside `AlertDestination` — reset alerts are their
/// own axis (a window turning, not a share falling), so a destination words
/// them separately rather than force-fitting the percent-alert copy.
public protocol QuotaResetAnnouncing: Sendable {
    func announce(_ alert: QuotaResetAlert) async
}

/// *Reset alerts* (MJ-103): after each refresh, tells once per window that a
/// login's quota resets within the hour, within ten minutes, or just turned.
/// Dedup is per (login, provider, reset instant, kind) in memory — the same
/// philosophy as `QuotaAlerts`: after a relaunch, an imminent reset is told
/// once more. A quota whose source says no reset instant gets the provider's
/// fixed daily reset when one is declared — the estate's ZCode 300M GLM
/// quota refreshes at 16:00 Europe/Oslo every day.
@MainActor
@Observable
public final class QuotaResetAlertScheduler {
    /// A provider whose windows turn at a fixed wall-clock time every day.
    public struct FixedDailyReset: Sendable, Equatable {
        public let providerId: String
        public let hour: Int
        public let minute: Int
        public let timeZone: TimeZone

        public init(providerId: String, hour: Int, minute: Int, timeZone: TimeZone) {
            self.providerId = providerId
            self.hour = hour
            self.minute = minute
            self.timeZone = timeZone
        }
    }

    /// The estate's ZCode 300M GLM quota: 16:00 Europe/Oslo, daily.
    public static let zcodeDailyReset = FixedDailyReset(
        providerId: "zai", hour: 16, minute: 0, timeZone: TimeZone(identifier: "Europe/Oslo") ?? .current
    )

    /// Thresholds, newest first. A threshold announces once per window; the
    /// next one fires as the clock keeps falling.
    nonisolated public static let thresholds: [(kind: QuotaResetAlert.Kind, seconds: TimeInterval)] = [
        (kind: .within60Minutes, seconds: 3_600),
        (kind: .within10Minutes, seconds: 600),
        (kind: .resetNow, seconds: 0)
    ]

    private let destination: any QuotaResetAnnouncing
    private let now: () -> Date
    private let fixedDailyResets: [FixedDailyReset]
    /// Alert identities already announced, keyed by `QuotaResetAlert.id`.
    private var told: Set<String> = []
    /// The live countdowns from the last refresh, for the HUD.
    public private(set) var countdowns: [QuotaResetCountdown] = []

    public init(
        destination: any QuotaResetAnnouncing,
        fixedDailyResets: [FixedDailyReset] = [QuotaResetAlertScheduler.zcodeDailyReset],
        now: @escaping () -> Date = Date.init
    ) {
        self.destination = destination
        self.fixedDailyResets = fixedDailyResets
        self.now = now
    }

    /// Decides from one refresh of one login. Announces each newly crossed
    /// threshold once, then publishes the login's countdowns for the HUD.
    public func review(login: String, providerId: String, quotas: [UsageQuota]) async {
        let current = now()
        var fresh: [QuotaResetCountdown] = []

        for quota in quotas {
            let reset = quota.resetsAt ?? fixedReset(for: providerId, after: current)
            guard let reset else { continue }
            let text = QuotaCountdownFormatter.countdown(until: reset, now: current)
            let id = "\(login)|\(providerId)|\(Int(reset.timeIntervalSince1970))"
            fresh.append(QuotaResetCountdown(
                id: id, login: login, providerId: providerId, resetsAt: reset, countdownText: text
            ))

            let seconds = reset.timeIntervalSince(current)
            for threshold in Self.thresholds where seconds <= threshold.seconds {
                let alert = QuotaResetAlert(
                    login: login, providerId: providerId, kind: threshold.kind,
                    resetsAt: reset, countdownText: text
                )
                if told.insert(alert.id).inserted {
                    await destination.announce(alert)
                }
            }
        }

        merge(countdowns: fresh)
        prune()
    }

    /// A quota with no reported reset instant and a matching provider gets
    /// the next fixed daily reset.
    private func fixedReset(for providerId: String, after now: Date) -> Date? {
        let rule = fixedDailyResets.first { $0.providerId == providerId }
        guard let rule else { return nil }
        return QuotaCountdownFormatter.nextDailyReset(
            after: now, hour: rule.hour, minute: rule.minute, timeZone: rule.timeZone
        )
    }

    /// Keeps this login's countdowns fresh in the HUD, leaving other logins'
    /// entries untouched until their next refresh.
    private func merge(countdowns fresh: [QuotaResetCountdown]) {
        var merged = countdowns.filter { entry in !fresh.contains(where: { $0.id == entry.id }) }
        merged.append(contentsOf: fresh)
        merged.sort { $0.resetsAt < $1.resetsAt }
        countdowns = merged
    }

    /// Drops told alerts and countdowns whose windows turned over an hour ago
    /// — the next cycle's reset is a different identity and re-arms itself.
    private func prune() {
        let current = now()
        countdowns.removeAll { current.timeIntervalSince($0.resetsAt) > 3_600 }
        if told.isEmpty { return }
        told = told.filter { identity in
            guard let epoch = identity.split(separator: "|").last.flatMap({ Double($0) }) else { return false }
            return current.timeIntervalSince(Date(timeIntervalSince1970: epoch)) <= 3_600
        }
    }
}
