import SwiftUI
import Domain

// MARK: - Motion Policy

/// Whether and how the popover animates.
///
/// The popover replays its entrance every time it opens — a staggered card
/// reveal, a spring on each progress bar, a pulsing sync dot, drifting
/// background orbs. That is fine as a first impression and wearing several
/// times a day, and for anyone who has asked the system to reduce motion it is
/// exactly what they turned off.
struct MotionPolicy: Equatable {
    let reduceMotion: Bool

    /// The animation to use, or nil to apply the change instantly.
    func animation(_ base: Animation) -> Animation? {
        reduceMotion ? nil : base
    }

    /// Stagger delay, collapsed to zero when motion is reduced so cards
    /// appear together rather than rippling in.
    func delay(_ base: Double) -> Double {
        reduceMotion ? 0 : base
    }

    /// Whether a purely decorative, continuous effect should run at all —
    /// drifting orbs, snowfall, the pulsing ring on the sync dot.
    var allowsDecorativeMotion: Bool { !reduceMotion }
}

extension EnvironmentValues {
    /// Motion policy derived from the system's Reduce Motion setting.
    var motionPolicy: MotionPolicy {
        MotionPolicy(reduceMotion: accessibilityReduceMotion)
    }
}

// MARK: - Quota Accessibility

/// Spoken descriptions for quota cards.
///
/// A card carries its meaning in a tinted number, a coloured bar and a tick
/// mark, none of which VoiceOver can convey. Dropping the pace badge removed
/// the last text that spelled the situation out, so the spoken string has to
/// carry it instead.
enum QuotaAccessibility {

    /// One sentence describing a card, in the order a person reads it:
    /// what limit, how much is left, how it's doing, when it resets.
    static func description(
        title: String,
        value: String,
        valueCaption: String,
        statusText: String,
        resetText: String?,
        memberCount: Int
    ) -> String {
        var parts: [String] = [title]

        parts.append("\(value) \(valueCaption.lowercased())")
        parts.append(statusText.lowercased())

        if let resetText {
            // "~Resets in 4h 54m" — the tilde is a visual marker and would be
            // read as punctuation, so it becomes a word.
            let spoken = resetText.hasPrefix("~")
                ? "estimated \(resetText.dropFirst().lowercased())"
                : resetText.lowercased()
            parts.append(spoken)
        }

        if memberCount > 1 {
            parts.append("\(memberCount) models share this limit")
        }

        return parts.joined(separator: ", ")
    }
}
