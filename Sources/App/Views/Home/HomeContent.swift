import Foundation

/// Where a Home card or link lands — the view turns it into a real action:
/// a page switch under the pills, the popover's own refresh, or the Settings
/// window opened on one pane. Never a dead link (HOME_PAGE_CONTRACT v1 §2).
enum HomeDestination: Equatable {
    case allPage
    case leaderboardPage
    case refreshAll
    case settings(SettingsSection)
}

/// The Home landing page's contents, decided once so the view only draws:
/// the hero's live chips, what the app contains, where to find it, what it
/// can do, and what's next (HOME_PAGE_CONTRACT v1 §2). Words and destinations
/// only — colors and the actions themselves stay the view's.
struct HomeContent: Equatable {
    struct Chip: Equatable, Identifiable {
        let id: String
        let symbol: String
        let text: String
        let kind: Kind

        /// The word's weight: the view reads it as a color.
        enum Kind: Equatable {
            case neutral
            case healthy
            case warning
            case critical
        }
    }

    struct MapCard: Equatable, Identifiable {
        let id: String
        let symbol: String
        let title: String
        let detail: String
        let destination: HomeDestination
    }

    struct Pointer: Equatable, Identifiable {
        let id: String
        let symbol: String
        let text: String
        /// Where the row opens, when it opens anything — a pointer at the
        /// popover's own fixed surfaces reads as words alone.
        let destination: HomeDestination?
    }

    struct Capability: Equatable, Identifiable {
        let id: String
        let symbol: String
        let text: String
        let actionLabel: String
        let destination: HomeDestination
    }

    struct NextItem: Equatable, Identifiable {
        let id: String
        let text: String
    }

    let chips: [Chip]
    let mapCards: [MapCard]
    let pointers: [Pointer]
    let capabilities: [Capability]
    let whatsNext: [NextItem]

    /// The hero's live chips: what the lineup holds, its health, the soonest
    /// reset, and the running version.
    static func chips(
        providerCount: Int,
        healthy: Int,
        warning: Int,
        critical: Int,
        version: String,
        nextReset: String?
    ) -> [Chip] {
        var chips: [Chip] = [
            Chip(id: "products", symbol: "square.grid.2x2.fill",
                 text: providerCount == 1 ? "1 product" : "\(providerCount) products",
                 kind: .neutral)
        ]
        if providerCount > 0 {
            if healthy > 0 {
                chips.append(Chip(id: "healthy", symbol: "checkmark.circle.fill",
                                  text: "\(healthy) ok", kind: .healthy))
            }
            if warning > 0 {
                chips.append(Chip(id: "warning", symbol: "exclamationmark.triangle.fill",
                                  text: "\(warning) low", kind: .warning))
            }
            if critical > 0 {
                chips.append(Chip(id: "critical", symbol: "xmark.circle.fill",
                                  text: "\(critical) out", kind: .critical))
            }
        }
        if let nextReset {
            chips.append(Chip(id: "reset", symbol: "clock.arrow.circlepath",
                              text: nextReset, kind: .neutral))
        }
        chips.append(Chip(id: "version", symbol: "info.circle", text: version, kind: .neutral))
        return chips
    }

    /// The Contents Map: the panel's major surfaces, each card landing on
    /// the real one. The board card leads to the board's page when it's on
    /// and to its Settings pane when it isn't — either way, somewhere real.
    static func mapCards(leaderboardOn: Bool) -> [MapCard] {
        [
            MapCard(id: "all", symbol: "square.grid.2x2.fill", title: "All providers",
                    detail: "Every product's quota on one page, led by the one that runs out first.",
                    destination: .allPage),
            MapCard(id: "leaderboard", symbol: "trophy.fill", title: "Leaderboard",
                    detail: "Your week of tokens, ranked against other ClaudeBar users.",
                    destination: leaderboardOn ? .leaderboardPage : .settings(.leaderboard)),
            MapCard(id: "providers", symbol: "powerplug.fill", title: "Providers & logins",
                    detail: "Turn a provider on and add the logins it watches.",
                    destination: .settings(.providers)),
            MapCard(id: "sync", symbol: "arrow.triangle.2.circlepath", title: "Sync & alerts",
                    detail: "How often quotas refresh, and when ClaudeBar warns you.",
                    destination: .settings(.syncAlerts)),
            MapCard(id: "notify", symbol: "bell.badge.fill", title: "Notify!",
                    detail: "Quota alerts as notifications, on this Mac and your phone.",
                    destination: .settings(.notify)),
            MapCard(id: "localapi", symbol: "server.rack", title: "Local API",
                    detail: "Serve your quotas to agents over MCP on this machine.",
                    destination: .settings(.localAPI)),
        ]
    }

    /// Where To Find It: the surfaces that aren't cards — the chrome's
    /// shortcuts, the header's countdown, the logs.
    static func pointers() -> [Pointer] {
        [
            Pointer(id: "reset", symbol: "clock.arrow.circlepath",
                    text: "Reset countdowns tick in the header, under the title.",
                    destination: nil),
            Pointer(id: "shortcuts", symbol: "command",
                    text: "⌘0 All · ⌘1–9 providers · ⌘R refresh · ⌘, settings.",
                    destination: nil),
            Pointer(id: "guestpass", symbol: "gift.fill",
                    text: "The gift button on Claude's page shares your plan as a guest pass (⌘S).",
                    destination: nil),
            Pointer(id: "dashboard", symbol: "safari.fill",
                    text: "Dashboard (⌘D) opens the selected provider's own usage page.",
                    destination: nil),
            Pointer(id: "logs", symbol: "doc.text.magnifyingglass",
                    text: "Logs and what errors mean — Settings → Logs.",
                    destination: .settings(.logs)),
        ]
    }

    /// What You Can Do: the top capabilities, each with a link that acts.
    static func capabilities() -> [Capability] {
        [
            Capability(id: "overview", symbol: "square.grid.2x2.fill",
                       text: "See every product at once",
                       actionLabel: "Open", destination: .allPage),
            Capability(id: "refresh", symbol: "arrow.clockwise",
                       text: "Refresh every quota now",
                       actionLabel: "Refresh", destination: .refreshAll),
            Capability(id: "warned", symbol: "exclamationmark.triangle.fill",
                       text: "Get warned before a quota runs out",
                       actionLabel: "Settings", destination: .settings(.syncAlerts)),
            Capability(id: "ranked", symbol: "trophy.fill",
                       text: "Join the week's token Leaderboard",
                       actionLabel: "Settings", destination: .settings(.leaderboard)),
            Capability(id: "agents", symbol: "server.rack",
                       text: "Let agents ask your quotas over MCP",
                       actionLabel: "Settings", destination: .settings(.localAPI)),
        ]
    }

    /// What's Next: what the next release carries — the [Unreleased] lines of
    /// CHANGELOG.md, told in the person's words.
    static func whatsNext() -> [NextItem] {
        [
            NextItem(id: "uberllm",
                     text: "UberLLM prepaid balance — a new provider that reads the credit your requests can still use."),
            NextItem(id: "windows-log",
                     text: "Windows log hardening — no line lost to a race, and writes that finish before a program exits."),
            NextItem(id: "windows-history",
                     text: "Faster usage-history reads on Windows for large session folders."),
        ]
    }

    /// The whole page's contents from the live facts the panel already holds.
    static func make(
        providerCount: Int,
        healthy: Int,
        warning: Int,
        critical: Int,
        version: String,
        nextReset: String?,
        leaderboardOn: Bool
    ) -> HomeContent {
        HomeContent(
            chips: chips(providerCount: providerCount, healthy: healthy, warning: warning,
                         critical: critical, version: version, nextReset: nextReset),
            mapCards: mapCards(leaderboardOn: leaderboardOn),
            pointers: pointers(),
            capabilities: capabilities(),
            whatsNext: whatsNext()
        )
    }
}
