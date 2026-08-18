import Testing
import Foundation
@testable import Domain

/// Feature: Quota Buckets
///
/// Providers like Antigravity report one quota per model, but several models
/// usually share a single underlying limit — consuming one consumes them all.
/// The snapshot collapses those into buckets so the UI draws one card per real
/// limit instead of one per model.
@Suite("Feature: Quota Buckets")
struct QuotaBucketTests {

    private static func quota(
        _ model: String,
        percent: Double,
        resetsAt: Date?,
        group: String? = nil,
        windowDuration: TimeInterval? = nil
    ) -> UsageQuota {
        UsageQuota(
            percentRemaining: percent,
            quotaType: .modelSpecific(model),
            providerId: "antigravity",
            resetsAt: resetsAt,
            windowDuration: windowDuration,
            group: group
        )
    }

    @Suite("Scenario: Models sharing one limit")
    struct SharedLimit {

        @Test
        func `models with the same value and reset collapse into one bucket`() {
            // Given — eight models all at 100%, all resetting at the same moment
            let reset = Date(timeIntervalSince1970: 1_000_000)
            let quotas = ["gemini-pro", "gemini-flash", "gemini-nano"].map {
                QuotaBucketTests.quota($0, percent: 100, resetsAt: reset)
            }
            let snapshot = UsageSnapshot(providerId: "antigravity", quotas: quotas, capturedAt: Date())

            // Then — one card's worth of content, with every model retained
            #expect(snapshot.displayBuckets.count == 1)
            #expect(snapshot.displayBuckets[0].members.count == 3)
        }

        @Test
        func `models on different limits stay in separate buckets`() {
            // Given — the two real buckets from a live Antigravity snapshot
            let soon = Date(timeIntervalSince1970: 1_000_000)
            let later = Date(timeIntervalSince1970: 2_000_000)
            let quotas = [
                QuotaBucketTests.quota("gemini-pro", percent: 100, resetsAt: soon),
                QuotaBucketTests.quota("gemini-flash", percent: 100, resetsAt: soon),
                QuotaBucketTests.quota("claude-sonnet", percent: 11, resetsAt: later),
                QuotaBucketTests.quota("gpt-oss", percent: 11, resetsAt: later),
            ]
            let snapshot = UsageSnapshot(providerId: "antigravity", quotas: quotas, capturedAt: Date())

            // Then — twelve-into-two, the collapse this feature exists for
            #expect(snapshot.displayBuckets.count == 2)
            #expect(snapshot.displayBuckets.map(\.members.count) == [2, 2])
        }

        @Test
        func `near-identical resets and values still collapse`() {
            // Given — timestamps seconds apart and percentages a hair apart,
            // as separate API rows for one bucket realistically are
            let base = Date(timeIntervalSince1970: 1_000_000)
            let quotas = [
                QuotaBucketTests.quota("a", percent: 100, resetsAt: base),
                QuotaBucketTests.quota("b", percent: 99.8, resetsAt: base.addingTimeInterval(20)),
            ]
            let snapshot = UsageSnapshot(providerId: "antigravity", quotas: quotas, capturedAt: Date())

            // Then — tolerance absorbs the jitter
            #expect(snapshot.displayBuckets.count == 1)
        }

        @Test
        func `quotas from different account sections never merge`() {
            // Given — same numbers, but two upstream accounts
            let reset = Date(timeIntervalSince1970: 1_000_000)
            let quotas = [
                QuotaBucketTests.quota("a", percent: 50, resetsAt: reset, group: "Claude"),
                QuotaBucketTests.quota("b", percent: 50, resetsAt: reset, group: "Claude · work"),
            ]
            let snapshot = UsageSnapshot(providerId: "omp", quotas: quotas, capturedAt: Date())

            // Then — merging across accounts would misreport whose quota it is
            #expect(snapshot.displayBuckets.count == 2)
        }

        @Test
        func `a quota with no reset never merges with one that has a reset`() {
            // Given — same percentage, but only one knows when it resets
            let quotas = [
                QuotaBucketTests.quota("a", percent: 100, resetsAt: Date(timeIntervalSince1970: 1_000_000)),
                QuotaBucketTests.quota("b", percent: 100, resetsAt: nil),
            ]
            let snapshot = UsageSnapshot(providerId: "antigravity", quotas: quotas, capturedAt: Date())

            // Then — an unknown reset is not evidence of a shared limit
            #expect(snapshot.displayBuckets.count == 2)
        }

        @Test
        func `buckets keep the order their quotas first appeared`() {
            // Given — the low bucket listed first
            let soon = Date(timeIntervalSince1970: 1_000_000)
            let later = Date(timeIntervalSince1970: 2_000_000)
            let quotas = [
                QuotaBucketTests.quota("claude", percent: 11, resetsAt: later),
                QuotaBucketTests.quota("gemini", percent: 100, resetsAt: soon),
            ]
            let snapshot = UsageSnapshot(providerId: "antigravity", quotas: quotas, capturedAt: Date())

            // Then — cards don't reshuffle between refreshes
            #expect(snapshot.displayBuckets[0].representative.percentRemaining == 11)
        }
    }

    @Suite("Scenario: Naming a bucket")
    struct Naming {

        @Test
        func `a bucket with a reported window is named after that window`() {
            // Given — a provider that reports its window length
            let quota = QuotaBucketTests.quota(
                "grok", percent: 50,
                resetsAt: Date(),
                windowDuration: 5 * 3600
            )
            let snapshot = UsageSnapshot(providerId: "grok", quotas: [quota], capturedAt: Date())

            // Then — the card names the limit, not the model
            #expect(snapshot.displayBuckets[0].windowTitle == "5h")
        }

        @Test
        func `a model bucket with no reported window is not named weekly`() {
            // Given — Antigravity: model-specific quotas, no window reported.
            // QuotaType.duration guesses 7 days for these, which would label a
            // 5-hour bucket "Weekly".
            let quota = QuotaBucketTests.quota("gemini", percent: 100, resetsAt: Date())
            let snapshot = UsageSnapshot(providerId: "antigravity", quotas: [quota], capturedAt: Date())

            // Then — no window claim at all rather than a wrong one
            #expect(snapshot.displayBuckets[0].windowTitle == nil)
        }

        @Test
        func `session and weekly quotas are named from their type`() {
            // Given — quota types whose window is part of their definition
            let session = UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")
            let weekly = UsageQuota(percentRemaining: 50, quotaType: .weekly, providerId: "claude")
            let snapshot = UsageSnapshot(providerId: "claude", quotas: [session, weekly], capturedAt: Date())

            // Then — these windows are known without the probe reporting them
            #expect(snapshot.displayBuckets[0].windowTitle == "5h")
            #expect(snapshot.displayBuckets[1].windowTitle == "7d")
        }
    }
}
