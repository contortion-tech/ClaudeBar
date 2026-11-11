import Foundation
import Testing
@testable import Quotas

/// MJ-103 coverage for the deterministic reset countdown formatter — fixed
/// instants and injected zones only, no ambient clock.
@Suite
struct QuotaCountdownFormatterTests {
    private let zone = TimeZone(identifier: "Europe/Oslo")!

    private func oslo(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: countdown

    @Test func countdownComposesAllUnits() {
        let now = oslo(2026, 11, 12, 10, 0)
        let reset = oslo(2026, 11, 14, 15, 30)
        #expect(QuotaCountdownFormatter.countdown(until: reset, now: now) == "2d 5h 30m")
    }

    @Test func countdownDropsEmptyUnits() {
        let now = oslo(2026, 11, 12, 10, 0)
        #expect(QuotaCountdownFormatter.countdown(until: now.addingTimeInterval(5 * 3600 + 59 * 60), now: now) == "5h 59m")
        #expect(QuotaCountdownFormatter.countdown(until: now.addingTimeInterval(30 * 60), now: now) == "30m")
    }

    @Test func countdownUnderAMinuteIsSoon() {
        let now = oslo(2026, 11, 12, 10, 0)
        #expect(QuotaCountdownFormatter.countdown(until: now.addingTimeInterval(30), now: now) == "soon")
    }

    @Test func countdownClampsPastResetsAtZero() {
        let now = oslo(2026, 11, 12, 10, 0)
        #expect(QuotaCountdownFormatter.countdown(until: now.addingTimeInterval(-3600), now: now) == "soon")
    }

    // MARK: nextDailyReset

    @Test func nextDailyResetLaterSameDay() {
        let now = oslo(2026, 11, 12, 10, 0)
        let reset = QuotaCountdownFormatter.nextDailyReset(after: now, hour: 16, minute: 0, timeZone: zone)
        #expect(reset == oslo(2026, 11, 12, 16, 0))
    }

    @Test func nextDailyResetRollsToTomorrowAfterTheHour() {
        let now = oslo(2026, 11, 12, 16, 1)
        let reset = QuotaCountdownFormatter.nextDailyReset(after: now, hour: 16, minute: 0, timeZone: zone)
        #expect(reset == oslo(2026, 11, 13, 16, 0))
    }

    @Test func nextDailyResetAtExactlyTheHourRollsToTomorrow() {
        let now = oslo(2026, 11, 12, 16, 0)
        let reset = QuotaCountdownFormatter.nextDailyReset(after: now, hour: 16, minute: 0, timeZone: zone)
        #expect(reset == oslo(2026, 11, 13, 16, 0))
    }

    @Test func nextDailyResetIsStrictlyAfterNowAcrossMidnight() {
        let now = oslo(2026, 11, 12, 23, 30)
        let reset = QuotaCountdownFormatter.nextDailyReset(after: now, hour: 16, minute: 0, timeZone: zone)
        #expect(reset == oslo(2026, 11, 13, 16, 0))
    }

    @Test func nextDailyResetSurvivesDstShift() {
        // Europe/Oslo: CEST (+2) before late October, CET (+1) after. Across
        // the shift the wall clock 16:00 stays 16:00 — the interval changes.
        let beforeShift = oslo(2026, 10, 24, 10, 0)
        let resetBefore = QuotaCountdownFormatter.nextDailyReset(after: beforeShift, hour: 16, minute: 0, timeZone: zone)
        #expect(resetBefore == oslo(2026, 10, 24, 16, 0))

        let afterShift = oslo(2026, 11, 12, 10, 0)
        let resetAfter = QuotaCountdownFormatter.nextDailyReset(after: afterShift, hour: 16, minute: 0, timeZone: zone)
        #expect(resetAfter == oslo(2026, 11, 12, 16, 0))
    }

    @Test func nextDailyResetsAreAlwaysStrictlyIncreasing() {
        var cursor = oslo(2026, 11, 12, 10, 0)
        var resets: [Date] = []
        for _ in 0..<5 {
            cursor = QuotaCountdownFormatter.nextDailyReset(after: cursor, hour: 16, minute: 0, timeZone: zone)
            resets.append(cursor)
        }
        #expect(zip(resets, resets.dropFirst()).allSatisfy { $0.0 < $0.1 })
    }
}
