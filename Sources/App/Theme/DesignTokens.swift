import SwiftUI

// MARK: - Type Scale

/// The app's typographic ladder.
///
/// Views name a role — `.microLabel`, `.statValue` — instead of a point size,
/// so a theme's `customFontName` reaches every label and the scale stays
/// consistent across a 179pt-wide card.
///
/// Cases are declared smallest to largest; `DesignTokensTests` enforces the
/// ordering and the 10pt floor.
enum TypeScale: CaseIterable {
    /// Uppercase card and section labels.
    case microLabel
    /// Secondary metadata — reset countdowns, timestamps, footnotes.
    case caption
    /// Standard body text.
    case body
    /// Body text carrying emphasis.
    case bodyEmphasis
    /// Button and control labels.
    case controlLabel
    /// Section and card titles.
    case title
    /// The app title and other display text.
    case headline
    /// The large number a card is built around.
    case statValue

    var size: CGFloat {
        switch self {
        case .microLabel: 10
        case .caption: 11
        case .body: 12
        case .bodyEmphasis: 12
        case .controlLabel: 13
        case .title: 15
        case .headline: 18
        case .statValue: 26
        }
    }

    var weight: Font.Weight {
        switch self {
        case .microLabel: .semibold
        case .caption: .medium
        case .body: .medium
        case .bodyEmphasis: .semibold
        case .controlLabel: .bold
        case .title: .bold
        case .headline: .bold
        case .statValue: .bold
        }
    }

    /// Extra letter spacing, used to keep uppercase labels legible.
    var tracking: CGFloat {
        switch self {
        case .microLabel: 0.3
        default: 0
        }
    }
}

// MARK: - Spacing Scale

/// The app's spacing ladder.
///
/// Deliberately not a strict 4pt grid — `sm` (6) and `lg` (12) are load-bearing
/// in this dense popover, and rounding them to 4/8 visibly loosens the layout.
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 24

    /// The ladder in ascending order, for tests and iteration.
    static let allSteps: [CGFloat] = [xxs, xs, sm, md, lg, xl, xxl]
}

// MARK: - Theme Integration

extension AppThemeProvider {
    /// Resolves a scale step against this theme, honouring `customFontName`.
    func font(_ scale: TypeScale) -> Font {
        font(size: scale.size, weight: scale.weight)
    }
}

extension View {
    /// Applies a scale step, including its tracking.
    func typeScale(_ scale: TypeScale, theme: any AppThemeProvider) -> some View {
        font(theme.font(scale))
            .tracking(scale.tracking)
    }
}
