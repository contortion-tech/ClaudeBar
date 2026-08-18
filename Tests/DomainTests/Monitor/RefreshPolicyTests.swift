import Testing
import Foundation
@testable import Domain

/// Feature: Refresh Policy
///
/// The app fetched every provider every time the popover opened. For a quota
/// at 100% with hours left, that request's answer cannot be interesting, and
/// it puts a network round trip in front of every glance.
@Suite("Feature: Refresh Policy")
struct RefreshPolicyTests {

    private static let now = Date(timeIntervalSince1970: 1_000_000)

    private static func quota(resetsIn: TimeInterval?, percent: Double = 100) -> UsageQuota {
        UsageQuota(
            percentRemaining: percent,
            quotaType: .modelSpecific("gemini"),
            providerId: "antigravity",
            resetsAt: resetsIn.map { now.addingTimeInterval($0) }
        )
    }

    @Suite("Scenario: Skipping pointless fetches")
    struct Skipping {

        @Test
        func `a far-off quota fetched a minute ago is left alone`() {
            // Given — 100%, resets in nearly five hours, just fetched
            let quotas = [RefreshPolicyTests.quota(resetsIn: 4 * 3600 + 54 * 60)]

            let should = RefreshPolicy.shouldRefresh(
                lastFetchedAt: RefreshPolicyTests.now.addingTimeInterval(-60),
                quotas: quotas, hasError: false, trigger: .automatic,
                now: RefreshPolicyTests.now
            )

            // Then — opening the popover costs nothing
            #expect(should == false)
        }

        @Test
        func `a far-off quota is refetched once it goes properly stale`() {
            // Given — the same quota, half an hour later
            let quotas = [RefreshPolicyTests.quota(resetsIn: 4 * 3600)]

            let should = RefreshPolicy.shouldRefresh(
                lastFetchedAt: RefreshPolicyTests.now.addingTimeInterval(-31 * 60),
                quotas: quotas, hasError: false, trigger: .automatic,
                now: RefreshPolicyTests.now
            )

            // Then — usage can have moved without the app seeing it
            #expect(should == true)
        }
    }

    @Suite("Scenario: Fetching when it matters")
    struct Fetching {

        @Test
        func `a quota near its reset is kept fresh`() {
            // Given — resets in 10 minutes, fetched 3 minutes ago
            let quotas = [RefreshPolicyTests.quota(resetsIn: 10 * 60)]

            let should = RefreshPolicy.shouldRefresh(
                lastFetchedAt: RefreshPolicyTests.now.addingTimeInterval(-3 * 60),
                quotas: quotas, hasError: false, trigger: .automatic,
                now: RefreshPolicyTests.now
            )

            // Then — the number is about to jump and usage is likely moving
            #expect(should == true)
        }

        @Test
        func `a reset that passed since the last fetch forces a refresh`() {
            // Given — fetched an hour ago, the reset fell 10 minutes ago
            let quotas = [RefreshPolicyTests.quota(resetsIn: -10 * 60)]

            let should = RefreshPolicy.shouldRefresh(
                lastFetchedAt: RefreshPolicyTests.now.addingTimeInterval(-3600),
                quotas: quotas, hasError: false, trigger: .automatic,
                now: RefreshPolicyTests.now
            )

            // Then — the displayed numbers are known wrong, not merely old
            #expect(should == true)
        }

        @Test
        func `a provider in error is always retried`() {
            // Given — Claude failing to parse, fetched seconds ago
            let should = RefreshPolicy.shouldRefresh(
                lastFetchedAt: RefreshPolicyTests.now.addingTimeInterval(-5),
                quotas: [], hasError: true, trigger: .automatic,
                now: RefreshPolicyTests.now
            )

            // Then — a broken provider is the state most worth re-checking
            #expect(should == true)
        }

        @Test
        func `pressing refresh always fetches`() {
            let should = RefreshPolicy.shouldRefresh(
                lastFetchedAt: RefreshPolicyTests.now.addingTimeInterval(-1),
                quotas: [RefreshPolicyTests.quota(resetsIn: 4 * 3600)],
                hasError: false, trigger: .userInitiated,
                now: RefreshPolicyTests.now
            )

            #expect(should == true)
        }

        @Test
        func `a provider never fetched is fetched`() {
            let should = RefreshPolicy.shouldRefresh(
                lastFetchedAt: nil, quotas: [], hasError: false,
                trigger: .automatic, now: RefreshPolicyTests.now
            )

            #expect(should == true)
        }

        @Test
        func `a quota with no known reset still goes stale on the idle bound`() {
            // Given — Antigravity reports no reset at all
            let quotas = [RefreshPolicyTests.quota(resetsIn: nil)]

            #expect(RefreshPolicy.maxAge(for: quotas, now: RefreshPolicyTests.now) == RefreshPolicy.idleMaxAge)
        }
    }
}

// MARK: - Staleness

@Suite("Feature: Snapshot staleness")
struct SnapshotStalenessTests {

    private static let now = Date(timeIntervalSince1970: 1_000_000)

    private static func snapshot(ageSeconds: TimeInterval, resetsIn: TimeInterval?) -> UsageSnapshot {
        UsageSnapshot(
            providerId: "antigravity",
            quotas: [
                UsageQuota(
                    percentRemaining: 100,
                    quotaType: .modelSpecific("gemini"),
                    providerId: "antigravity",
                    resetsAt: resetsIn.map { Date().addingTimeInterval($0) }
                )
            ],
            capturedAt: Date().addingTimeInterval(-ageSeconds)
        )
    }

    @Test
    func `ten-minute-old data is not overdue when nothing is near resetting`() {
        // Given — the flat isStale rule would already be warning here
        let snapshot = Self.snapshot(ageSeconds: 600, resetsIn: 4 * 3600)

        #expect(snapshot.isStale == true)
        #expect(snapshot.isOverdue == false)
    }

    @Test
    func `data past the idle bound is overdue`() {
        let snapshot = Self.snapshot(ageSeconds: 31 * 60, resetsIn: 4 * 3600)

        #expect(snapshot.isOverdue == true)
    }

    @Test
    func `the bar is much lower while a reset is close`() {
        // Given — resets in 10 minutes, so the value is about to move
        let snapshot = Self.snapshot(ageSeconds: 5 * 60, resetsIn: 10 * 60)

        #expect(snapshot.isOverdue == true)
    }
}
