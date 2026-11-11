import Foundation
import Testing
@testable import Quotas

/// MJ-103 coverage for the deduplicated reset-alert scheduler — a recording
/// destination, a fixed clock, no real notifications.
@MainActor
final class ResetAlertRecorder {
    var alerts: [QuotaResetAlert] = []
    func add(_ alert: QuotaResetAlert) { alerts.append(alert) }
}

@Suite
struct QuotaResetAlertSchedulerTests {
    /// Records every alert in order.
    private final class RecordingDestination: QuotaResetAnnouncing, @unchecked Sendable {
        let recorder = ResetAlertRecorder()
        func announce(_ alert: QuotaResetAlert) async {
            await recorder.add(alert)
        }
    }

    private func quota(resetsAt: Date?, percent: Double = 50) -> UsageQuota {
        UsageQuota(percentRemaining: percent, quotaType: .session, providerId: "claude", resetsAt: resetsAt)
    }

    private func oslo(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @MainActor
    @Test func thresholdCrossedOncePerWindow() async {
        let destination = RecordingDestination()
        var now = oslo(2026, 11, 12, 15, 30)
        let reset = oslo(2026, 11, 12, 16, 0)
        let scheduler = QuotaResetAlertScheduler(destination: destination, now: { now })

        await scheduler.review(login: "Claude", providerId: "claude", quotas: [quota(resetsAt: reset)])
        await scheduler.review(login: "Claude", providerId: "claude", quotas: [quota(resetsAt: reset)])
        #expect(destination.recorder.alerts.count == 1)
        #expect(destination.recorder.alerts[0].kind == .within60Minutes)

        now = oslo(2026, 11, 12, 15, 55)
        await scheduler.review(login: "Claude", providerId: "claude", quotas: [quota(resetsAt: reset)])
        #expect(destination.recorder.alerts.count == 2)
        #expect(destination.recorder.alerts[1].kind == .within10Minutes)

        now = oslo(2026, 11, 12, 16, 0)
        await scheduler.review(login: "Claude", providerId: "claude", quotas: [quota(resetsAt: reset)])
        #expect(destination.recorder.alerts.count == 3)
        #expect(destination.recorder.alerts[2].kind == .resetNow)
    }

    @MainActor
    @Test func newWindowRearmsThresholds() async {
        let destination = RecordingDestination()
        var now = oslo(2026, 11, 12, 15, 30)
        let scheduler = QuotaResetAlertScheduler(destination: destination, now: { now })

        let firstWindow = oslo(2026, 11, 12, 16, 0)
        await scheduler.review(login: "Claude", providerId: "claude", quotas: [quota(resetsAt: firstWindow)])
        #expect(destination.recorder.alerts.count == 1)

        let nextWindow = oslo(2026, 11, 13, 16, 0)
        now = oslo(2026, 11, 13, 15, 30)
        await scheduler.review(login: "Claude", providerId: "claude", quotas: [quota(resetsAt: nextWindow)])

        #expect(destination.recorder.alerts.count == 2)
        #expect(destination.recorder.alerts.allSatisfy { $0.kind == .within60Minutes })
    }

    @MainActor
    @Test func fixedDailyResetAppliesWhenSourceGivesNone() async {
        let destination = RecordingDestination()
        var now = oslo(2026, 11, 12, 15, 30)
        let scheduler = QuotaResetAlertScheduler(
            destination: destination,
            fixedDailyResets: [QuotaResetAlertScheduler.zcodeDailyReset],
            now: { now }
        )

        #expect(destination.recorder.alerts.isEmpty)
        await scheduler.review(login: "Z.ai", providerId: "zai", quotas: [quota(resetsAt: nil)])
        #expect(destination.recorder.alerts.count == 1)
        #expect(destination.recorder.alerts[0].kind == .within60Minutes)
        #expect(destination.recorder.alerts[0].resetsAt == oslo(2026, 11, 12, 16, 0))

        now = oslo(2026, 11, 13, 15, 30)
        await scheduler.review(login: "Z.ai", providerId: "zai", quotas: [quota(resetsAt: nil)])
        #expect(destination.recorder.alerts.count == 2)
        #expect(destination.recorder.alerts[1].resetsAt == oslo(2026, 11, 13, 16, 0))
    }

    @MainActor
    @Test func fixedDailyResetDoesNotTouchOtherProviders() async {
        let destination = RecordingDestination()
        let now = oslo(2026, 11, 12, 15, 30)
        let scheduler = QuotaResetAlertScheduler(destination: destination, now: { now })

        await scheduler.review(login: "Claude", providerId: "claude", quotas: [quota(resetsAt: nil)])
        #expect(destination.recorder.alerts.isEmpty)
        #expect(scheduler.countdowns.isEmpty)
    }

    @MainActor
    @Test func countdownsArePublishedForTheHud() async {
        let destination = RecordingDestination()
        let now = oslo(2026, 11, 12, 15, 30)
        let scheduler = QuotaResetAlertScheduler(destination: destination, now: { now })

        let reset = oslo(2026, 11, 12, 18, 0)
        await scheduler.review(login: "Gemini", providerId: "gemini", quotas: [quota(resetsAt: reset)])
        #expect(scheduler.countdowns.count == 1)
        #expect(scheduler.countdowns[0].providerId == "gemini")
        #expect(scheduler.countdowns[0].countdownText == "2h 30m")
    }

    @MainActor
    @Test func otherLoginsCountdownsSurviveARefresh() async {
        let destination = RecordingDestination()
        var now = oslo(2026, 11, 12, 15, 30)
        let scheduler = QuotaResetAlertScheduler(destination: destination, now: { now })

        let claudeReset = oslo(2026, 11, 12, 18, 0)
        await scheduler.review(login: "Claude", providerId: "claude", quotas: [quota(resetsAt: claudeReset)])

        let geminiReset = oslo(2026, 11, 12, 17, 0)
        await scheduler.review(login: "Gemini", providerId: "gemini", quotas: [quota(resetsAt: geminiReset)])
        #expect(scheduler.countdowns.count == 2)
        #expect(scheduler.countdowns[0].providerId == "gemini")

        now = oslo(2026, 11, 12, 15, 45)
        await scheduler.review(login: "Claude", providerId: "claude", quotas: [quota(resetsAt: claudeReset)])
        #expect(scheduler.countdowns.count == 2)
        #expect(scheduler.countdowns[0].providerId == "gemini")
    }

    @MainActor
    @Test func zeroQuotasClearsNothingAndAnnouncesNothing() async {
        let destination = RecordingDestination()
        let now = oslo(2026, 11, 12, 15, 30)
        let scheduler = QuotaResetAlertScheduler(destination: destination, now: { now })

        await scheduler.review(login: "Claude", providerId: "claude", quotas: [])
        #expect(destination.recorder.alerts.isEmpty)
        #expect(scheduler.countdowns.isEmpty)
    }

    @MainActor
    @Test func alertIdentityDistinguishesWindowsAndKinds() {
        let early = QuotaResetAlert(login: "Claude", providerId: "claude", kind: .within60Minutes,
                                    resetsAt: oslo(2026, 11, 12, 16, 0), countdownText: "30m")
        let otherWindow = QuotaResetAlert(login: "Claude", providerId: "claude", kind: .within60Minutes,
                                          resetsAt: oslo(2026, 11, 13, 16, 0), countdownText: "30m")
        let otherKind = QuotaResetAlert(login: "Claude", providerId: "claude", kind: .within10Minutes,
                                        resetsAt: oslo(2026, 11, 12, 16, 0), countdownText: "10m")
        #expect(early.id != otherWindow.id)
        #expect(early.id != otherKind.id)
    }
}
