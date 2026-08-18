import Testing
import Foundation
@testable import Domain

/// Feature: Overview cap
///
/// Overview mode shows every provider at once. A provider reporting nine
/// buckets crowds out the others, so each provider yields at most a couple of
/// cards — chosen by which ones actually need attention.
@Suite("Feature: Overview cap")
struct QuotaBucketCapTests {

    private static func bucket(percent: Double, model: String = "m") -> QuotaBucket {
        QuotaBucket(members: [
            UsageQuota(
                percentRemaining: percent,
                quotaType: .modelSpecific(model),
                providerId: "antigravity",
                resetsAt: Date()
            )
        ])
    }

    @Test
    func `the cap keeps the quotas closest to running out`() {
        // Given — the Antigravity shape: mostly full, one nearly spent
        let buckets = [
            QuotaBucketCapTests.bucket(percent: 100, model: "a"),
            QuotaBucketCapTests.bucket(percent: 100, model: "b"),
            QuotaBucketCapTests.bucket(percent: 11, model: "c"),
        ]

        // When
        let (shown, hidden) = buckets.capped(to: 2)

        // Then — the 11% survives; taking the first two would have dropped it
        #expect(shown.first?.representative.percentRemaining == 11)
        #expect(shown.count == 2)
        #expect(hidden == 1)
    }

    @Test
    func `nothing is hidden when the provider fits`() {
        let buckets = [QuotaBucketCapTests.bucket(percent: 50)]

        let (shown, hidden) = buckets.capped(to: 2)

        #expect(shown.count == 1)
        #expect(hidden == 0)
    }

    @Test
    func `equally healthy buckets keep their original order`() {
        // Given — no reason to prefer one over another
        let buckets = [
            QuotaBucketCapTests.bucket(percent: 100, model: "first"),
            QuotaBucketCapTests.bucket(percent: 100, model: "second"),
            QuotaBucketCapTests.bucket(percent: 100, model: "third"),
        ]

        // When
        let (shown, _) = buckets.capped(to: 2)

        // Then — ties must not shuffle between refreshes
        #expect(shown.map(\.representative.quotaType.displayName) == ["First", "Second"])
    }

    @Test
    func `an over-quota bucket outranks a merely low one`() {
        // Given — negative remaining means already over the limit
        let buckets = [
            QuotaBucketCapTests.bucket(percent: 5, model: "low"),
            QuotaBucketCapTests.bucket(percent: -3, model: "over"),
            QuotaBucketCapTests.bucket(percent: 100, model: "fine"),
        ]

        let (shown, hidden) = buckets.capped(to: 1)

        #expect(shown.first?.representative.percentRemaining == -3)
        #expect(hidden == 2)
    }
}
