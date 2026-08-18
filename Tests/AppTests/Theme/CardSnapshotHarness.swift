import Testing
import SwiftUI
import AppKit
import Foundation
@testable import ClaudeBar
@testable import Domain

/// Renders quota cards to PNG so the card face can be inspected directly.
///
/// ClaudeBar is an `LSUIElement` menu-bar agent, so it never appears in the
/// screen-control app registry and its popover cannot be screenshotted from
/// outside. Rendering the view itself is the only way to see what the layout
/// actually does at the real card width.
@Suite("Harness: Card snapshots", .enabled(if: ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] != nil))
@MainActor
struct CardSnapshotHarness {

    /// 400pt popover − 32pt padding − 10pt gutter, halved.
    private static let cardWidth: CGFloat = 179

    private static func write(_ view: some View, named name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { return }
        let renderer = ImageRenderer(
            content: view
                .frame(width: cardWidth)
                .padding(12)
                .background(DarkTheme().backgroundGradient)
        )
        renderer.scale = 3
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private static func quota(
        _ model: String, percent: Double, resetsIn: TimeInterval?, window: TimeInterval? = nil
    ) -> UsageQuota {
        UsageQuota(
            percentRemaining: percent,
            quotaType: .modelSpecific(model),
            providerId: "antigravity",
            resetsAt: resetsIn.map { Date().addingTimeInterval($0) },
            windowDuration: window
        )
    }

    @Test
    func `render the real Antigravity buckets`() {
        // The eight-model 100% bucket from the live snapshot
        let gemini = ["gemini-3-pro", "gemini-3-flash", "gemini-2-pro", "gemini-2-flash",
                      "gemini-nano", "gemini-ultra", "gemini-lite", "gemini-exp"]
            .map { Self.quota($0, percent: 100, resetsIn: 4 * 3600 + 54 * 60) }

        Self.write(
            WrappedStatCard(bucket: QuotaBucket(members: gemini), delay: 0),
            named: "01-bucket-8-models-no-window"
        )

        // The same bucket when the window IS known — the "5H" title case
        let windowed = gemini.map {
            UsageQuota(percentRemaining: $0.percentRemaining, quotaType: $0.quotaType,
                       providerId: $0.providerId, resetsAt: $0.resetsAt, windowDuration: 5 * 3600)
        }
        Self.write(
            WrappedStatCard(bucket: QuotaBucket(members: windowed), delay: 0),
            named: "02-bucket-8-models-5h-window"
        )

        // The low bucket: Claude Sonnet + Opus + GPT-OSS at 11%
        let low = ["claude-sonnet", "claude-opus", "gpt-oss"]
            .map { Self.quota($0, percent: 11, resetsIn: 4 * 24 * 3600 + 22 * 3600, window: 7 * 24 * 3600) }
        Self.write(
            WrappedStatCard(bucket: QuotaBucket(members: low), delay: 0),
            named: "03-bucket-3-models-low"
        )

        // A single quota with a long label — the truncation case
        let long = UsageQuota(
            percentRemaining: 47, quotaType: .timeLimit("Weekly (all models)"),
            providerId: "claude", resetsAt: Date().addingTimeInterval(3 * 3600)
        )
        Self.write(
            WrappedStatCard(bucket: QuotaBucket(members: [long]), delay: 0),
            named: "04-single-long-label"
        )

        // A plain session quota
        let session = UsageQuota(
            percentRemaining: 47, quotaType: .session, providerId: "claude",
            resetsAt: Date().addingTimeInterval(4 * 3600 + 54 * 60)
        )
        Self.write(
            WrappedStatCard(bucket: QuotaBucket(members: [session]), delay: 0),
            named: "05-single-session"
        )

        #expect(Bool(true))
    }
}
