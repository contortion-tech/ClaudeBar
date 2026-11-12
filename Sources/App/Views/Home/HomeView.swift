import SwiftUI
import Domain

/// The Home landing page (HOME_PAGE_CONTRACT v1 §2): what the panel contains,
/// where to find it, what it can do, and what's next — the page the popover
/// lands on, reached from the pills' Home pill. It draws what `HomeContent`
/// decided and turns every card's destination into a real action. It is the
/// scroll region's content: the panel's own scroll view does the scrolling.
struct HomeView: View {
    let monitor: QuotaMonitor
    let leaderboard: AppLeaderboard
    let goAll: () -> Void
    let goLeaderboard: () -> Void
    let refreshAllNow: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.openWindow) private var openWindow
    @Environment(QuotaResetAlertScheduler.self) private var quotaResetScheduler

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            hero
            section("CONTENTS MAP") { mapGrid }
            section("WHERE TO FIND IT") { pointerList }
            section("WHAT YOU CAN DO") { capabilityList }
            section("WHAT'S NEXT") { whatsNextList }
        }
    }

    // MARK: - Hero (brand plate from theme tokens; the panel has no plate asset)

    /// The brand plate and its live chips. ClaudeBar ships no masthead plate
    /// asset, so the plate is the theme's own accent pair — the same gradient
    /// and on-accent ink the selected pill wears — and the text is SwiftUI,
    /// never baked pixels. The chips tick with the popover's frame clock.
    private var hero: some View {
        WindowFrameTicker(interval: 30) { now in
            VStack(alignment: .leading, spacing: 8) {
                heroPlate
                HomeChipRail(chips: chips(now: now))
            }
        }
    }

    private func chips(now: Date) -> [HomeContent.Chip] {
        HomeContent.chips(
            providerCount: monitor.tabs.count,
            healthy: overview.healthy,
            warning: overview.warning,
            critical: overview.critical,
            version: VersionTicker.text(info: Bundle.main.infoDictionary ?? [:]),
            nextReset: nextResetLine(now: now)
        )
    }

    private var heroPlate: some View {
        HStack(spacing: 12) {
            if let logo = NSImage(named: "AppLogo") {
                Image(nsImage: logo)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("ClaudeBar")
                    .popoverDisplayFont(18)
                    .foregroundStyle(theme.textOnAccent)
                Text("Every AI coding quota in your menu bar.")
                    .popoverFont(11, weight: .medium)
                    .foregroundStyle(theme.textOnAccent.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                .fill(theme.accentGradient)
                .themeShadow(theme)
        )
    }

    /// The soonest window across the whole lineup — the header's countdown
    /// line, read the same way the chrome footer reads it.
    private func nextResetLine(now: Date) -> String? {
        MenuContentView.resetLine(countdowns: quotaResetScheduler.countdowns, providerId: nil, now: now)
    }

    private var overview: Overview { Overview(monitor) }

    // MARK: - Contents Map

    private var mapGrid: some View {
        TwoColumnCardGrid(items: HomeContent.mapCards(leaderboardOn: leaderboard.membership.isOn),
                          id: \.id) { card in
            mapCard(card)
        }
    }

    private func mapCard(_ card: HomeContent.MapCard) -> some View {
        Button {
            perform(card.destination)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: card.symbol)
                        .popoverFont(11, weight: .semibold)
                        .foregroundStyle(theme.accentPrimary)
                    Text(card.title)
                        .popoverFont(12, weight: .semibold)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                }
                Text(card.detail)
                    .popoverFont(10)
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .fill(theme.cardGradient)
                        .themeShadow(theme, scale: 0.5)
                    RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                        .stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth)
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(card.title)
    }

    // MARK: - Where To Find It

    private var pointerList: some View {
        VStack(spacing: 6) {
            ForEach(HomeContent.pointers()) { pointer in
                pointerRow(pointer)
            }
        }
    }

    @ViewBuilder
    private func pointerRow(_ pointer: HomeContent.Pointer) -> some View {
        let row = HStack(spacing: 8) {
            Image(systemName: pointer.symbol)
                .popoverFont(10)
                .foregroundStyle(theme.textTertiary)
                .frame(width: 14)
            Text(pointer.text)
                .popoverFont(11)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if pointer.destination != nil {
                Image(systemName: "chevron.right")
                    .popoverFont(8, weight: .semibold)
                    .foregroundStyle(theme.accentPrimary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.glassBackground.opacity(0.4))
        )
        .contentShape(Rectangle())

        if let destination = pointer.destination {
            Button {
                perform(destination)
            } label: {
                row
            }
            .buttonStyle(.plain)
            .help(pointer.text)
        } else {
            row
        }
    }

    // MARK: - What You Can Do

    private var capabilityList: some View {
        VStack(spacing: 6) {
            ForEach(HomeContent.capabilities()) { capability in
                capabilityRow(capability)
            }
        }
    }

    private func capabilityRow(_ capability: HomeContent.Capability) -> some View {
        Button {
            perform(capability.destination)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: capability.symbol)
                    .popoverFont(10)
                    .foregroundStyle(theme.accentPrimary)
                    .frame(width: 14)
                Text(capability.text)
                    .popoverFont(11)
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(capability.actionLabel)
                    .popoverFont(11, weight: .semibold)
                    .foregroundStyle(theme.accentPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.glassBackground.opacity(0.4))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(capability.text)
    }

    // MARK: - What's Next

    private var whatsNextList: some View {
        VStack(spacing: 6) {
            ForEach(HomeContent.whatsNext()) { item in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(theme.accentPrimary.opacity(0.6))
                        .frame(width: 4, height: 4)
                        .padding(.top, 5)
                    Text(item.text)
                        .popoverFont(11)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Sections & destinations

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .popoverFont(9, weight: .semibold)
                .foregroundStyle(theme.textSecondary)
                .tracking(0.5)
            content()
        }
    }

    private func perform(_ destination: HomeDestination) {
        switch destination {
        case .allPage: goAll()
        case .leaderboardPage: goLeaderboard()
        case .refreshAll: refreshAllNow()
        case .settings(let pane):
            SettingsRoute.shared.open(pane)
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Hero chips

/// The hero's chips, one pill each. A chip's kind is the word's weight: the
/// theme answers with the status color, so light and dark both hold.
private struct HomeChipRail: View {
    let chips: [HomeContent.Chip]

    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(chips) { chip in
                    HStack(spacing: 4) {
                        Image(systemName: chip.symbol)
                            .popoverFont(8, weight: .semibold)
                            .foregroundStyle(color(of: chip.kind))
                        Text(chip.text)
                            .popoverFont(9, weight: .medium)
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(theme.glassBackground.opacity(0.4))
                    )
                    .overlay(
                        Capsule().stroke(theme.glassBorder, lineWidth: theme.cardBorderWidth)
                    )
                    .accessibilityLabel(chip.text)
                }
            }
        }
    }

    private func color(of kind: HomeContent.Chip.Kind) -> Color {
        switch kind {
        case .neutral: theme.textTertiary
        case .healthy: theme.statusHealthy
        case .warning: theme.statusWarning
        case .critical: theme.statusColor(for: .critical)
        }
    }
}
