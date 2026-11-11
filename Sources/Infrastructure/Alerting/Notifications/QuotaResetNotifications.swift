import Domain
import Foundation
import Quotas

/// This Mac's reset notifications (MJ-103) — a destination for
/// `QuotaResetAlert`s, in the words the person reads: *Claude · work resets
/// in 23m.* Whether to tell is the scheduler's; this only words it.
public final class QuotaResetNotifications: QuotaResetAnnouncing, @unchecked Sendable {
    private let alertSender: AlertSender

    public init() {
        self.alertSender = SystemAlertSender()
    }

    init(alertSender: AlertSender) {
        self.alertSender = alertSender
    }

    public func announce(_ alert: QuotaResetAlert) async {
        let (title, body) = Self.words(for: alert)
        do {
            try await alertSender.send(title: title, body: body, categoryIdentifier: Self.quotaResetCategory)
        } catch {
            AppLog.notifications.error("Failed to send a reset alert: \(error.localizedDescription)")
        }
    }

    static let quotaResetCategory = "QUOTA_RESET"

    private static func words(for alert: QuotaResetAlert) -> (String, String) {
        switch alert.kind {
        case .within60Minutes:
            ("\(alert.login) resets within the hour", "Quota window turns in \(alert.countdownText).")
        case .within10Minutes:
            ("\(alert.login) resets in \(alert.countdownText)", "Save long work — the window is nearly over.")
        case .resetNow:
            ("\(alert.login) quota reset", "The window just turned — fresh quota is live.")
        }
    }
}
