import Testing
import SwiftUI
@testable import ClaudeBar

/// Feature: Design Tokens
///
/// The app renders every label through a shared typographic scale rather than
/// ad-hoc point sizes, so themes stay internally consistent and no text drops
/// below the legibility floor.
@Suite("Feature: Design Tokens")
struct DesignTokensTests {

    @Suite("Scenario: Typographic scale")
    struct TypographicScale {

        @Test
        func `no step falls below the 10pt legibility floor`() {
            // Given — the whole scale
            let sizes = TypeScale.allCases.map(\.size)

            // Then — nothing is smaller than the floor macOS text stays
            // readable at inside a 179pt-wide card.
            #expect(sizes.min() ?? 0 >= 10)
        }

        @Test
        func `steps are ordered from smallest to largest`() {
            // Given — the scale in declaration order
            let sizes = TypeScale.allCases.map(\.size)

            // Then — each step is at least as large as the one before it,
            // so the enum reads as a ladder.
            #expect(zip(sizes, sizes.dropFirst()).allSatisfy { $0 <= $1 })
        }

        @Test
        func `each step is visually distinct from every other`() {
            // Given — size and weight together define a step
            let pairs = TypeScale.allCases.map { "\($0.size)-\($0.weight)" }

            // Then — no two steps collapse into the same rendered style
            #expect(Set(pairs).count == TypeScale.allCases.count)
        }

        @Test
        func `the scale stays small enough to be memorable`() {
            // Then — a scale nobody can hold in their head gets ignored;
            // the pre-token codebase had 16 competing sizes.
            #expect(TypeScale.allCases.count <= 10)
        }
    }

    @Suite("Scenario: Spacing scale")
    struct SpacingScale {

        @Test
        func `steps are positive and strictly ascending`() {
            // Given — the spacing ladder
            let steps = Spacing.allSteps

            // Then — every step is a real, increasing gap
            #expect(steps.allSatisfy { $0 > 0 })
            #expect(zip(steps, steps.dropFirst()).allSatisfy { $0 < $1 })
        }
    }
}
