import Testing
import Foundation
@testable import Domain

/// Feature: Reset Resolution
///
/// Some providers report usage but never say when it resets, so the countdown
/// blanks out and the app re-derives it from scratch on every refresh. Resolution
/// gives a quota a reset from the best source available: what the provider just
/// said, what the user entered, or what the app remembered.
@Suite("Feature: Reset Resolution")
struct ResetResolutionTests {

    private static let now = Date(timeIntervalSince1970: 1_000_000)

    private static func quota(
        resetsAt: Date?,
        windowDuration: TimeInterval? = nil,
        type: QuotaType = .modelSpecific("gemini")
    ) -> UsageQuota {
        UsageQuota(
            percentRemaining: 50,
            quotaType: type,
            providerId: "antigravity",
            resetsAt: resetsAt,
            windowDuration: windowDuration
        )
    }

    @Suite("Scenario: Precedence")
    struct Precedence {

        @Test
        func `a fresh provider value wins over anything stored`() {
            // Given — the provider reports a reset, and we also hold a stored one
            let live = ResetResolutionTests.now.addingTimeInterval(3600)
            let quota = ResetResolutionTests.quota(resetsAt: live, windowDuration: 5 * 3600)
            let stored = StoredReset(
                date: ResetResolutionTests.now.addingTimeInterval(7200),
                source: .manual,
                recordedAt: ResetResolutionTests.now
            )

            // When
            let resolved = quota.resolvedReset(stored: stored, now: ResetResolutionTests.now)

            // Then — live data is never second-guessed
            #expect(resolved?.date == live)
            #expect(resolved?.isExtrapolated == false)
        }

        @Test
        func `a manual entry fills in when the provider reports nothing`() {
            // Given — Antigravity's actual behaviour: usage, no reset
            let quota = ResetResolutionTests.quota(resetsAt: nil)
            let anchor = ResetResolutionTests.now.addingTimeInterval(3600)
            let stored = StoredReset(date: anchor, source: .manual, recordedAt: ResetResolutionTests.now)

            // When
            let resolved = quota.resolvedReset(stored: stored, now: ResetResolutionTests.now)

            // Then — the user's own value is shown as given, not as a guess
            #expect(resolved?.date == anchor)
            #expect(resolved?.isExtrapolated == false)
        }

        @Test
        func `a remembered value survives a refresh that reports nothing`() {
            // Given — the provider reported a reset earlier but not this time
            let quota = ResetResolutionTests.quota(resetsAt: nil)
            let remembered = ResetResolutionTests.now.addingTimeInterval(1800)
            let stored = StoredReset(date: remembered, source: .probe, recordedAt: ResetResolutionTests.now)

            // When
            let resolved = quota.resolvedReset(stored: stored, now: ResetResolutionTests.now)

            // Then — the countdown keeps running instead of blanking
            #expect(resolved?.date == remembered)
            #expect(resolved?.isExtrapolated == false)
        }

        @Test
        func `nothing anywhere resolves to nothing`() {
            let quota = ResetResolutionTests.quota(resetsAt: nil)

            #expect(quota.resolvedReset(stored: nil, now: ResetResolutionTests.now) == nil)
        }
    }

    @Suite("Scenario: Rolling a window forward")
    struct RollForward {

        @Test
        func `an elapsed reset rolls to the next window and is marked inferred`() {
            // Given — a 5h window whose stored reset passed an hour ago
            let quota = ResetResolutionTests.quota(resetsAt: nil, windowDuration: 5 * 3600)
            let past = ResetResolutionTests.now.addingTimeInterval(-3600)
            let stored = StoredReset(date: past, source: .probe, recordedAt: past)

            // When
            let resolved = quota.resolvedReset(stored: stored, now: ResetResolutionTests.now)

            // Then — one window on from the anchor, flagged as computed
            #expect(resolved?.date == past.addingTimeInterval(5 * 3600))
            #expect(resolved?.isExtrapolated == true)
        }

        @Test
        func `a reset several windows back rolls to the next future one`() {
            // Given — two and a bit windows have elapsed
            let quota = ResetResolutionTests.quota(resetsAt: nil, windowDuration: 3600)
            let past = ResetResolutionTests.now.addingTimeInterval(-2.5 * 3600)
            let stored = StoredReset(date: past, source: .probe, recordedAt: past)

            // When
            let resolved = quota.resolvedReset(stored: stored, now: ResetResolutionTests.now)

            // Then — lands in the future, not on an already-passed window
            #expect((resolved?.date ?? .distantPast) > ResetResolutionTests.now)
        }

        @Test
        func `a remembered value stops being extrapolated after three windows`() {
            // Given — the provider has been unreachable for over three windows
            let quota = ResetResolutionTests.quota(resetsAt: nil, windowDuration: 3600)
            let past = ResetResolutionTests.now.addingTimeInterval(-4 * 3600)
            let stored = StoredReset(date: past, source: .probe, recordedAt: past)

            // When
            let resolved = quota.resolvedReset(stored: stored, now: ResetResolutionTests.now)

            // Then — the app admits it doesn't know rather than inventing a countdown
            #expect(resolved == nil)
        }

        @Test
        func `a manual entry keeps rolling past the three-window cap`() {
            // Given — a standing user entry, long after it was set. The cap
            // guards against stale *provider* data; a manual anchor is the
            // user's answer for a provider that never reports at all, so
            // expiring it would defeat the feature.
            let quota = ResetResolutionTests.quota(resetsAt: nil, windowDuration: 3600)
            let past = ResetResolutionTests.now.addingTimeInterval(-10 * 3600)
            let stored = StoredReset(date: past, source: .manual, recordedAt: past)

            // When
            let resolved = quota.resolvedReset(stored: stored, now: ResetResolutionTests.now)

            // Then — still counting down
            #expect((resolved?.date ?? .distantPast) > ResetResolutionTests.now)
            #expect(resolved?.isExtrapolated == true)
        }

        @Test
        func `an elapsed reset with no known window resolves to nothing`() {
            // Given — Antigravity again: no window reported, and QuotaType
            // guesses seven days for model quotas, which we refuse to use
            let quota = ResetResolutionTests.quota(resetsAt: nil)
            let past = ResetResolutionTests.now.addingTimeInterval(-3600)
            let stored = StoredReset(date: past, source: .probe, recordedAt: past)

            // When
            let resolved = quota.resolvedReset(stored: stored, now: ResetResolutionTests.now)

            // Then — rolling by a guessed period would produce a confident lie
            #expect(resolved == nil)
        }

        @Test
        func `a session quota rolls by its type's window without the probe reporting one`() {
            // Given — .session means five hours by definition
            let quota = ResetResolutionTests.quota(resetsAt: nil, type: .session)
            let past = ResetResolutionTests.now.addingTimeInterval(-3600)
            let stored = StoredReset(date: past, source: .probe, recordedAt: past)

            // When
            let resolved = quota.resolvedReset(stored: stored, now: ResetResolutionTests.now)

            // Then
            #expect(resolved?.date == past.addingTimeInterval(5 * 3600))
        }
    }
}

// MARK: - Display

@Suite("Feature: Reset Display")
struct ResetDisplayTests {

    private static let now = Date(timeIntervalSince1970: 1_000_000)

    @Test
    func `a reported countdown reads plainly`() {
        let resolved = ResolvedReset(date: Self.now.addingTimeInterval(4 * 3600 + 54 * 60), isExtrapolated: false)

        #expect(resolved.description(now: Self.now) == "Resets in 4h 54m")
    }

    @Test
    func `an inferred countdown is marked with a tilde`() {
        // Given — a value the app rolled forward rather than received
        let resolved = ResolvedReset(date: Self.now.addingTimeInterval(4 * 3600 + 54 * 60), isExtrapolated: true)

        // Then — readable as inferred without relying on colour
        #expect(resolved.description(now: Self.now) == "~Resets in 4h 54m")
    }

    @Test
    func `a reset already due reads as soon rather than negative`() {
        let resolved = ResolvedReset(date: Self.now.addingTimeInterval(-60), isExtrapolated: false)

        #expect(resolved.description(now: Self.now) == "Resets soon")
    }
}
