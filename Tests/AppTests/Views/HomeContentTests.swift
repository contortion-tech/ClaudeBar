import Foundation
import Testing
@testable import ClaudeBar

/// The Home landing page's contents (HOME_PAGE_CONTRACT v1): the five
/// sections in order, the hero's live chips, and every card landing
/// somewhere real.
@Suite
struct HomeContentTests {
    private func make(
        providerCount: Int = 3,
        healthy: Int = 3,
        warning: Int = 0,
        critical: Int = 0,
        version: String = "v0.5.26 · B52",
        nextReset: String? = nil,
        leaderboardOn: Bool = false
    ) -> HomeContent {
        HomeContent.make(
            providerCount: providerCount, healthy: healthy, warning: warning,
            critical: critical, version: version, nextReset: nextReset,
            leaderboardOn: leaderboardOn
        )
    }

    // MARK: - The contract's sections

    @Test func `should offer every section the landing contract asks for`() {
        let content = make()
        #expect(!content.chips.isEmpty)
        #expect(!content.mapCards.isEmpty)
        #expect(!content.pointers.isEmpty)
        #expect((3...6).contains(content.capabilities.count))
        #expect((2...4).contains(content.whatsNext.count))
    }

    @Test func `should keep the Contents Map at a card per major surface`() {
        let content = make()
        #expect(content.mapCards.count == 6)
        #expect(content.mapCards.allSatisfy { !$0.detail.isEmpty })
    }

    // MARK: - Real destinations, never dead links

    @Test func `should lead the Contents Map with the All page`() {
        let content = make()
        #expect(content.mapCards.first?.destination == .allPage)
    }

    @Test func `should route the board card to its page while the Leaderboard is on`() {
        let content = make(leaderboardOn: true)
        let board = content.mapCards.first { $0.id == "leaderboard" }
        #expect(board?.destination == .leaderboardPage)
    }

    @Test func `should route the board card to Settings while the Leaderboard is off`() {
        let content = make(leaderboardOn: false)
        let board = content.mapCards.first { $0.id == "leaderboard" }
        #expect(board?.destination == .settings(.leaderboard))
    }

    @Test func `should point every map card and capability at a real destination`() {
        let content = make()
        #expect(content.mapCards.allSatisfy { !$0.detail.isEmpty && !$0.title.isEmpty })
        #expect(content.capabilities.allSatisfy { !$0.actionLabel.isEmpty })
        #expect(content.capabilities.contains { $0.destination == .refreshAll })
        // The one pointer that can open something opens Settings' Logs pane;
        // the rest describe the popover's own fixed surfaces.
        #expect(content.pointers.contains { $0.destination == .settings(.logs) })
    }

    // MARK: - The hero's live chips

    @Test func `should count the products and their health on the chips`() {
        let chips = make(providerCount: 3, healthy: 2, warning: 1, critical: 0).chips
        #expect(chips.contains { $0.text == "3 products" })
        #expect(chips.contains { $0.text == "2 ok" && $0.kind == .healthy })
        #expect(chips.contains { $0.text == "1 low" && $0.kind == .warning })
        #expect(!chips.contains { $0.kind == .critical })
    }

    @Test func `should say the soonest reset on a chip when a window is watched`() {
        let chips = make(nextReset: "Resets in 2h 4m").chips
        #expect(chips.contains { $0.text == "Resets in 2h 4m" })
    }

    @Test func `should show no health words on the chips before the lineup holds any`() {
        let chips = make(providerCount: 0, healthy: 0, warning: 0, critical: 0).chips
        #expect(chips.contains { $0.text == "0 products" })
        #expect(!chips.contains { $0.kind == .healthy })
        #expect(!chips.contains { $0.kind == .warning })
        #expect(!chips.contains { $0.kind == .critical })
    }

    @Test func `should always carry the version on a chip`() {
        let chips = make(version: "v9.9.9 · B1").chips
        #expect(chips.contains { $0.text == "v9.9.9 · B1" })
    }
}
