import Testing
import SwiftUI
@testable import ClaudeBar

/// Feature: Accessibility
///
/// Quota cards encode their meaning visually — a tinted number, a coloured bar,
/// a tick mark. None of that reaches VoiceOver, and the pace badge that used to
/// spell it out in words is gone.
@Suite("Feature: Accessibility")
struct AccessibilityTests {

    @Suite("Scenario: Reduce Motion")
    struct ReduceMotion {

        @Test
        func `animations are dropped when motion is reduced`() {
            let policy = MotionPolicy(reduceMotion: true)

            #expect(policy.animation(.easeIn) == nil)
        }

        @Test
        func `animations are kept by default`() {
            let policy = MotionPolicy(reduceMotion: false)

            #expect(policy.animation(.easeIn) != nil)
        }

        @Test
        func `the card stagger collapses so cards appear together`() {
            // Given — the eighth card in a grid, normally 0.56s behind the first
            let policy = MotionPolicy(reduceMotion: true)

            #expect(policy.delay(0.56) == 0)
        }

        @Test
        func `the stagger is preserved by default`() {
            #expect(MotionPolicy(reduceMotion: false).delay(0.56) == 0.56)
        }

        @Test
        func `decorative motion stops when motion is reduced`() {
            // Orbs, snowfall and the pulsing sync ring convey nothing
            #expect(MotionPolicy(reduceMotion: true).allowsDecorativeMotion == false)
            #expect(MotionPolicy(reduceMotion: false).allowsDecorativeMotion == true)
        }
    }

    @Suite("Scenario: Spoken quota cards")
    struct SpokenCards {

        @Test
        func `a card reads as limit, value, status, then reset`() {
            let spoken = QuotaAccessibility.description(
                title: "5H",
                value: "47%",
                valueCaption: "Remaining",
                statusText: "Healthy",
                resetText: "Resets in 4h 54m",
                memberCount: 1
            )

            #expect(spoken == "5H, 47% remaining, healthy, resets in 4h 54m")
        }

        @Test
        func `a shared limit says how many models it covers`() {
            // Given — the collapsed Antigravity bucket
            let spoken = QuotaAccessibility.description(
                title: "5H",
                value: "100%",
                valueCaption: "Remaining",
                statusText: "Room to spare",
                resetText: "Resets in 4h 54m",
                memberCount: 8
            )

            // Then — the count is spoken, since the member list is hover-only
            #expect(spoken.hasSuffix("8 models share this limit"))
        }

        @Test
        func `an inferred countdown is spoken as estimated rather than tilde`() {
            // Given — a rolled-forward reset, marked "~" on screen
            let spoken = QuotaAccessibility.description(
                title: "5H",
                value: "47%",
                valueCaption: "Remaining",
                statusText: "Healthy",
                resetText: "~Resets in 4h 54m",
                memberCount: 1
            )

            // Then — "~" would be read as punctuation or skipped entirely
            #expect(spoken.contains("estimated resets in 4h 54m"))
            #expect(!spoken.contains("~"))
        }

        @Test
        func `a card with no known reset simply omits it`() {
            let spoken = QuotaAccessibility.description(
                title: "8 MODELS",
                value: "100%",
                valueCaption: "Remaining",
                statusText: "Healthy",
                resetText: nil,
                memberCount: 8
            )

            #expect(spoken == "8 MODELS, 100% remaining, healthy, 8 models share this limit")
        }
    }
}
