import Foundation
import Monitoring
import Quotas

/// Follows every refresh of `monitor` (MJ-103): the login, as the lineup
/// names it, and its quotas as the person sees them — the same seam
/// `QuotaAlerts.follow` uses.
@MainActor
extension QuotaResetAlertScheduler {
    public func follow(_ monitor: QuotaMonitor) {
        monitor.onRefreshed { [weak monitor] login in
            guard let monitor else { return }
            await self.review(
                login: monitor.lineupName(of: login),
                providerId: login.providerId,
                quotas: monitor.usage(of: login)?.quotas ?? []
            )
        }
    }
}
