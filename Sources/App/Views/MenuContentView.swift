import SwiftUI
import Domain
import Infrastructure
#if ENABLE_SPARKLE
import Sparkle
#endif

/// The main menu content view with adaptive theme support via AppThemeProvider.
/// Uses the pluggable theme system for consistent styling across all themes.
struct MenuContentView: View {
    let monitor: QuotaMonitor
    let sessionMonitor: SessionMonitor
    let quotaAlerter: QuotaAlerter
    var onHookSettingsChanged: ((Bool) -> Void)?

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.motionPolicy) private var motion
    #if ENABLE_SPARKLE
    @Environment(\.sparkleUpdater) private var sparkleUpdater
    #endif
    @State private var isHoveringRefresh = false
    @State private var animateIn = false
    @State private var showSettings = false
    @State private var showSharePass = false
    @State private var settings = AppSettings.shared
    @State private var hasRequestedNotificationPermission = false
    @State private var pillsOverflow = false
    @State private var pillsContentWidth: CGFloat = 0
    @State private var pillsViewportWidth: CGFloat = 0

    /// The currently selected provider ID (from monitor, which is @Observable)
    private var selectedProviderId: String {
        get { monitor.selectedProviderId }
        nonmutating set { monitor.selectedProviderId = newValue }
    }

    /// The currently selected provider
    private var selectedProvider: (any AIProvider)? {
        monitor.selectedProvider
    }

    var body: some View {
        ZStack {
            // Gradient background from theme
            theme.backgroundGradient
                .ignoresSafeArea()

            // Background orbs (decorative only — skipped under Reduce Motion)
            if theme.showBackgroundOrbs, motion.allowsDecorativeMotion {
                if theme.id == "christmas" {
                    ChristmasBackgroundOrbs()
                } else {
                    backgroundOrbs
                }
            }

            // Theme overlay (e.g., snowfall for Christmas)
            theme.overlayView

            if showSettings {
                // Settings View
                SettingsContentView(showSettings: $showSettings, monitor: monitor)
            } else {
                // Main Content
                VStack(spacing: 0) {
                    // Header with branding
                    headerView
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                    // Provider Pills (hidden in overview mode)
                    if !settings.overviewModeEnabled {
                        providerPills
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                    }

                    // Session Indicator (shown when Claude Code is active)
                    if let session = sessionMonitor.activeSession {
                        SessionIndicatorView(session: session)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }

                    // Main Content Area — hugs its content, but caps at the
                    // screen height and scrolls beyond it (aggregating
                    // providers can show a dozen cards; the action bar must
                    // never be pushed off-screen).
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 12) {
                            metricsContent
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                    .frame(maxHeight: contentMaxHeight)
                    // Recreate the scroll view when the shown content
                    // changes, so a newly selected provider starts at the
                    // top instead of inheriting the previous scroll offset.
                    .id(settings.overviewModeEnabled ? "overview" : monitor.selectedProviderId)

                    // Bottom Action Bar
                    actionBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }

            // Share Pass Overlay
            if showSharePass, let claudeProvider = selectedProvider as? ClaudeProvider,
               let guestPass = claudeProvider.guestPass {
                SharePassOverlay(pass: guestPass) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showSharePass = false
                    }
                }
            }

            // Share Pass Error Overlay
            if let claudeProvider = selectedProvider as? ClaudeProvider,
               let passError = claudeProvider.passError {
                SharePassErrorOverlay(message: passError.localizedDescription) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        claudeProvider.clearPassError()
                    }
                }
            }
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onReceive(NotificationCenter.default.publisher(for: .hookSettingsChanged)) { notification in
            let enabled = notification.userInfo?["enabled"] as? Bool ?? false
            onHookSettingsChanged?(enabled)
        }
        .task {
            // Request alert permission once (after app run loop is active)
            if !hasRequestedNotificationPermission {
                hasRequestedNotificationPermission = true
                let granted = await quotaAlerter.requestPermission()
                AppLog.notifications.info("Alert permission request result: \(granted ? "granted" : "denied")")
            }

            // Show header and tabs immediately
            withAnimation(.easeOut(duration: 0.6)) {
                animateIn = true
            }
            // Then fetch data in background
            if settings.overviewModeEnabled {
                await refreshAllEnabled()
            } else {
                await refresh(providerId: selectedProviderId)
            }

            // Check for updates when menu opens (no UI unless update found)
            #if ENABLE_SPARKLE
            if sparkleUpdater?.automaticallyChecksForUpdates == true {
                sparkleUpdater?.checkForUpdatesInBackground()
            }
            #endif
        }
        .onChange(of: selectedProviderId) { _, newProviderId in
            // Refresh immediately when the user switches provider while the
            // dropdown is open. Periodic background refresh is owned by the
            // app-lifetime loop in ClaudeBarApp, which restarts itself when the
            // selected or menu-bar provider changes.
            Task {
                await refresh(providerId: newProviderId)
            }
        }
    }

    /// Upper bound for the scrollable content region — see
    /// `PopoverContentHeight` for the policy and its tests.
    private var contentMaxHeight: CGFloat {
        PopoverContentHeight.maxHeight(
            visibleScreenHeight: NSScreen.main?.visibleFrame.height ?? 800,
            overviewMode: settings.overviewModeEnabled
        )
    }

    // MARK: - Background Orbs

    private var backgroundOrbs: some View {
        GeometryReader { geo in
            ZStack {
                // Large purple orb
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                BaseTheme.purpleVibrant.opacity(colorScheme == .dark ? 0.4 : 0.15),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 120
                        )
                    )
                    .frame(width: 240, height: 240)
                    .offset(x: -60, y: -80)
                    .blur(radius: 40)

                // Pink orb
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                BaseTheme.pinkHot.opacity(colorScheme == .dark ? 0.35 : 0.12),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)
                    .offset(x: geo.size.width - 80, y: geo.size.height - 150)
                    .blur(radius: 30)
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            // Custom Provider Icon - shows AppLogo in overview mode, provider icon otherwise
            // Avoid animation on provider icon to prevent constraint update loops in MenuBarExtra
            ZStack {
                if settings.overviewModeEnabled, let logo = NSImage(named: "AppLogo") {
                    Image(nsImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 38, height: 38)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(theme.accentPrimary.opacity(0.3), lineWidth: 2)
                        )
                        .shadow(color: theme.accentPrimary.opacity(0.15), radius: 3, y: 1)
                } else {
                    ProviderIconView(providerId: selectedProviderId, size: 38)
                }

                // Christmas star sparkle overlay
                if theme.id == "christmas" {
                    Image(systemName: "sparkle")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.accentPrimary)
                        .offset(x: 14, y: -14)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("ClaudeBar")
                        .font(theme.font(.headline))
                        .foregroundStyle(theme.textPrimary)

                    // Christmas gift icon
                    if theme.id == "christmas" {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.accentPrimary)
                    }
                }

                Text(headerSubtitle)
                    .font(theme.font(.body))
                    .foregroundStyle(theme.id == "cli" ? theme.accentPrimary : theme.textSecondary)
            }

            Spacer()

            // Status Badge
            statusBadge
        }
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : -10)
    }

    private var headerSubtitle: String {
        switch theme.id {
        case "cli": return "> usage monitor"
        case "christmas": return "Happy Holidays!"
        default: return "AI Usage Monitor"
        }
    }

    /// Status of the currently selected provider
    private var selectedProviderStatus: QuotaStatus {
        guard let snapshot = selectedProvider?.snapshot else { return .healthy }
        if settings.burnRateWarningEnabled {
            return snapshot.paceAwareOverallStatus(burnRateThreshold: settings.burnRateThreshold)
        }
        return snapshot.overallStatus
    }

    /// Whether the selected provider is currently syncing
    private var isSelectedProviderSyncing: Bool {
        selectedProvider?.isSyncing ?? false
    }

    private var statusBadge: some View {
        let statusColor = theme.statusColor(for: selectedProviderStatus)

        return HStack(spacing: 6) {
            // Animated pulse dot
            PulsingStatusDot(
                color: statusColor,
                isSyncing: isSelectedProviderSyncing
            )

            Text(statusText)
                .font(theme.font(.body))
                .foregroundStyle(theme.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                .fill(theme.glassBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                        .stroke(statusColor.opacity(0.5), lineWidth: 1)
                )
        )
    }

    private var statusText: String {
        if isSelectedProviderSyncing { return "Syncing..." }
        return selectedProviderStatus.badgeText
    }

    /// Help text for settings button, includes update info if available
    private var updateAvailableHelpText: String {
        #if ENABLE_SPARKLE
        if let version = sparkleUpdater?.availableVersion, sparkleUpdater?.isUpdateAvailable == true {
            return "Update available: v\(version)"
        }
        #endif
        return "Settings"
    }

    // MARK: - Provider Pills

    /// Only show enabled providers in the pills
    private var enabledProviders: [any AIProvider] {
        monitor.enabledProviders
    }

    private var providerPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(enabledProviders, id: \.id) { provider in
                    ProviderPill(
                        providerId: provider.id,
                        providerName: provider.name,
                        isSelected: provider.id == selectedProviderId,
                        hasData: provider.snapshot != nil
                    ) {
                        // Avoid withAnimation to prevent constraint update loops in MenuBarExtra
                        selectedProviderId = provider.id
                    }
                }
            }
            .background(HorizontalScrollBooster())
            .overlay {
                GeometryReader { geo in
                    Color.clear.preference(key: PillsContentWidthKey.self, value: geo.size.width)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: PillsViewportWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(PillsContentWidthKey.self) { contentWidth in
            updatePillsOverflow(contentWidth: contentWidth)
        }
        .onPreferenceChange(PillsViewportWidthKey.self) { viewportWidth in
            updatePillsOverflow(viewportWidth: viewportWidth)
        }
        .mask {
            HStack(spacing: 0) {
                Rectangle().fill(.white)
                if pillsOverflow {
                    LinearGradient(
                        colors: [.white, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 28)
                }
            }
        }
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 10)
        .animation(.easeOut(duration: 0.5).delay(0.1), value: animateIn)
    }

    private func updatePillsOverflow(contentWidth: CGFloat? = nil, viewportWidth: CGFloat? = nil) {
        if let contentWidth { pillsContentWidth = contentWidth }
        if let viewportWidth { pillsViewportWidth = viewportWidth }
        let overflows = pillsViewportWidth > 0 && pillsContentWidth > pillsViewportWidth + 1
        if pillsOverflow != overflows {
            pillsOverflow = overflows
        }
    }

    // MARK: - Metrics Content

    @ViewBuilder
    private var metricsContent: some View {
        if settings.overviewModeEnabled {
            let providers = monitor.enabledProviders
            if providers.isEmpty {
                emptyState
            } else {
                overviewContent(providers: providers)
            }
        } else if let provider = selectedProvider, let snapshot = provider.snapshot {
            VStack(spacing: 12) {
                if let displayName = snapshot.accountEmail ?? snapshot.accountOrganization {
                    accountCard(displayName: displayName, snapshot: snapshot)
                }
                statsGrid(snapshot: snapshot)
            }
            .opacity(animateIn ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.2), value: animateIn)
        } else if selectedProvider?.isSyncing == true {
            loadingState
        } else {
            emptyState
        }
    }

    private func overviewContent(providers: [any AIProvider]) -> some View {
        // Scrolling is owned by the shared middle-region ScrollView in
        // `body`; nesting another vertical ScrollView here would break
        // height negotiation and swallow gestures.
        VStack(spacing: 12) {
            ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                if index > 0 {
                    Divider()
                        .background(theme.glassBorder)
                }
                providerSection(provider: provider)
            }
        }
        .opacity(animateIn ? 1 : 0)
        .animation(.easeOut(duration: 0.5).delay(0.2), value: animateIn)
    }

    private func providerSection(provider: any AIProvider) -> some View {
        VStack(spacing: 8) {
            providerSectionHeader(provider: provider)

            if let snapshot = provider.snapshot {
                statsGrid(snapshot: snapshot)
            } else if provider.isSyncing {
                LoadingSpinnerView()
            } else {
                compactErrorState(provider: provider)
            }
        }
    }

    private func providerSectionHeader(provider: any AIProvider) -> some View {
        HStack(spacing: 8) {
            ProviderIconView(providerId: provider.id, size: 20, showGlow: false)

            Text(provider.name)
                .font(theme.font(.controlLabel))
                .foregroundStyle(theme.textPrimary)

            Spacer()

            let status = provider.snapshot?.overallStatus ?? .healthy
            Text(provider.isSyncing ? "Syncing..." : status.badgeText)
                .badge(theme.statusColor(for: status))
        }
        .padding(.horizontal, 4)
    }

    private func compactErrorState(provider: any AIProvider) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(theme.statusWarning)

            Text(provider.lastError?.localizedDescription ?? "Unavailable")
                .font(theme.font(.body))
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 4)
    }


    private func accountCard(displayName: String, snapshot: UsageSnapshot) -> some View {
        HStack(spacing: 10) {
            // Avatar circle
            ZStack {
                Circle()
                    .fill(ProviderVisualIdentityLookup.gradient(for: selectedProviderId, scheme: colorScheme))
                    .frame(width: 32, height: 32)

                Text(String(displayName.prefix(1)).uppercased())
                    .font(theme.font(.title))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(theme.font(.body))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)

                    // Account tier badge
                    if let accountTier = snapshot.accountTier {
                        Text(accountTier.badgeText)
                            .font(theme.font(.microLabel))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(theme.accentPrimary.opacity(0.8))
                            )
                    }
                }

                Text("Updated \(snapshot.ageDescription)")
                    .font(theme.font(.microLabel))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()

            // Stale indicator
            if snapshot.isStale {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.statusWarning)
            }
        }
        .glassCard(cornerRadius: 12, padding: 10)
    }

    /// Collapsed state of quota-group sections, keyed by `QuotaGroup.id`.
    /// Ephemeral by design: reopening the popover starts fully expanded.
    @State private var collapsedQuotaGroups: Set<String> = []

    /// Sections for aggregating providers (e.g. Oh My Pi): one collapsible
    /// block per upstream account, so ten flat cards become scannable.
    @ViewBuilder
    private func quotaGroupSections(snapshot: UsageSnapshot) -> some View {
        let groups = snapshot.quotaGroups
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { groupIndex, group in
                let baseDelay = Double(groups.prefix(groupIndex).reduce(0) { $0 + $1.quotas.count }) * 0.08
                quotaGroupSection(group, baseDelay: baseDelay)
            }
        }
    }

    private func quotaGroupSection(_ group: QuotaGroup, baseDelay: Double) -> some View {
        // Note-only sections (accounts without usable quota data) have no
        // cards to collapse; the note renders inline in the header.
        let isNoteOnly = group.quotas.isEmpty
        let isCollapsed = !isNoteOnly && collapsedQuotaGroups.contains(group.id)
        let sharedReset = group.quotas.sharedResetDescription()
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    collapsedQuotaGroups = isCollapsed
                        ? collapsedQuotaGroups.subtracting([group.id])
                        : collapsedQuotaGroups.union([group.id])
                }
            } label: {
                HStack(spacing: 6) {
                    if !isNoteOnly {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(theme.textTertiary)
                    }

                    Text((group.title ?? "Other").uppercased())
                        .font(theme.font(.microLabel))
                        .foregroundStyle(theme.textSecondary)
                        .tracking(0.5)

                    Spacer(minLength: 4)

                    if case .headerInline(let note) = group.notePlacement {
                        Text(note)
                            .font(theme.font(.caption))
                            .foregroundStyle(theme.textTertiary)
                    } else if isNoteOnly {
                        Text("No usage data")
                            .font(theme.font(.caption))
                            .foregroundStyle(theme.textTertiary)
                    } else {
                        // Collapsed sections keep their headline number visible.
                        if isCollapsed, let lowest = group.lowestQuota {
                            Text("\(Int(lowest.percentRemaining))% left")
                                .font(theme.font(.microLabel))
                                .foregroundStyle(theme.textTertiary)
                        }

                        Text(group.worstStatus.badgeText)
                            .badge(theme.statusColor(for: group.worstStatus))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isNoteOnly)

            if !isNoteOnly && !isCollapsed {
                // A note attached to a quota-bearing section (the same
                // account also reported "No usage" somewhere) is shown as
                // its own row - never silently dropped.
                if case .row(let note) = group.notePlacement {
                    Text(note)
                        .font(theme.font(.caption))
                        .foregroundStyle(theme.textTertiary)
                }

                if let sharedReset {
                    sharedResetRow(sharedReset)
                }

                TwoColumnCardGrid(
                    items: Array(group.quotas.displayBuckets.enumerated()),
                    id: \.element.id
                ) { entry in
                    WrappedStatCard(
                        bucket: entry.element,
                        delay: baseDelay + Double(entry.offset) * 0.08,
                        showsReset: sharedReset == nil
                    )
                }
            }
        }
    }

    private func sharedResetRow(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.fill")
                .font(.system(size: 8))

            Text(text)
                .font(theme.font(.caption))

            Spacer(minLength: 0)
        }
        .foregroundStyle(theme.textTertiary)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func statsGrid(snapshot: UsageSnapshot) -> some View {
        VStack(spacing: 10) {
            // Grouped sections cover aggregating providers even when every
            // account lacks quota data (note-only sections must still render).
            if snapshot.hasQuotaGroups {
                quotaGroupSections(snapshot: snapshot)
            }

            if !snapshot.hasQuotaGroups, !snapshot.quotas.isEmpty {
                let sharedReset = snapshot.quotas.sharedResetDescription()
                if let sharedReset {
                    sharedResetRow(sharedReset)
                }
            }

            if !snapshot.hasQuotaGroups, !snapshot.quotas.isEmpty {
                let sharedReset = snapshot.quotas.sharedResetDescription()
                TwoColumnCardGrid(
                    items: Array(snapshot.displayBuckets.enumerated()),
                    id: \.element.id
                ) { entry in
                    WrappedStatCard(
                        bucket: entry.element,
                        delay: Double(entry.offset) * 0.08,
                        showsReset: sharedReset == nil
                    )
                }
            }

            // Show Extra usage cost card if available (Pro with Extra usage enabled)
            if let costUsage = snapshot.costUsage {
                let budget = settings.claudeApiBudgetEnabled ? settings.claudeApiBudget : nil
                CostStatCard(costUsage: costUsage, budget: budget, delay: Double(snapshot.quotas.count) * 0.08)
            }

            // Show Bedrock usage card if available
            if let bedrockUsage = snapshot.bedrockUsage {
                BedrockUsageCard(usage: bedrockUsage, delay: Double(snapshot.quotas.count) * 0.08)
            }

            // Show daily usage cards from JSONL session analysis (e.g., Claude Code)
            // Controlled via Settings toggle or ~/.claudebar/settings.json
            if settings.showDailyUsageCards, let report = snapshot.dailyUsageReport {
                let baseDelay = Double(snapshot.quotas.count + 1) * 0.08
                HStack(spacing: 10) {
                    DailyUsageCardView(metric: .cost, report: report, delay: baseDelay)
                        .frame(maxWidth: .infinity)
                    DailyUsageCardView(metric: .tokens, report: report, delay: baseDelay + 0.08)
                        .frame(maxWidth: .infinity)
                }
                if report.today.workingTime > 0 || report.previous.workingTime > 0 {
                    DailyUsageCardView(metric: .workingTime, report: report, delay: baseDelay + 0.16)
                }
            }

            // Show extension metrics cards (from extension probes)
            if let extensionMetrics = snapshot.extensionMetrics?.filter({ $0.group == nil }),
               !extensionMetrics.isEmpty {
                let metricBaseDelay = Double(snapshot.quotas.count + 2) * 0.08
                TwoColumnCardGrid(
                    items: Array(extensionMetrics.enumerated()),
                    id: \.element.label
                ) { entry in
                    ExtensionMetricCardView(metric: entry.element, delay: metricBaseDelay + Double(entry.offset) * 0.08)
                }
            }

            // Show custom web card if URL is configured for this provider
            if let urlString = settings.provider.customCardURL(forProvider: snapshot.providerId),
               let url = URL(string: urlString) {
                let cardDelay = Double(snapshot.quotas.count + 2) * 0.08
                CustomWebCardView(url: url, delay: cardDelay)
            }
        }
        .padding(.top, 4)
    }

    private var loadingState: some View {
        LoadingSpinnerView()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(theme.statusWarning.opacity(0.2))
                    .frame(width: 60, height: 60)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(theme.statusWarning)
            }

            Text("\(selectedProvider?.name ?? selectedProviderId) Unavailable")
                .font(theme.font(.title))
                .foregroundStyle(theme.textPrimary)

            // Show actual error message if available, otherwise generic message
            Text(selectedProvider?.lastError?.localizedDescription ?? "Install CLI or check configuration")
                .font(theme.font(.bodyEmphasis))
                .foregroundStyle(theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(height: 140)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            // Dashboard Button
            WrappedActionButton(
                icon: "safari.fill",
                label: "Dashboard",
                gradient: theme.accentGradient
            ) {
                if let url = selectedProvider?.dashboardURL {
                    NSWorkspace.shared.open(url)
                }
            }
            .keyboardShortcut("d")

            // Refresh Button
            let isCurrentlyRefreshing = settings.overviewModeEnabled
                ? monitor.enabledProviders.contains { $0.isSyncing }
                : selectedProvider?.isSyncing == true
            WrappedActionButton(
                icon: isCurrentlyRefreshing ? "arrow.trianglehead.2.counterclockwise.rotate.90" : "arrow.clockwise",
                label: isCurrentlyRefreshing ? "Syncing" : "Refresh",
                gradient: theme.accentGradient,
                isLoading: isCurrentlyRefreshing
            ) {
                if settings.overviewModeEnabled {
                    Task { await refreshAllEnabled() }
                } else {
                    Task { await refresh(providerId: selectedProviderId) }
                }
            }
            .keyboardShortcut("r")

            Spacer()

            // Share Button (Claude only) - icon only
            if let claudeProvider = selectedProvider as? ClaudeProvider,
               claudeProvider.supportsGuestPasses {
                let isFetchingPasses = claudeProvider.isFetchingPasses
                Button {
                    Task { await fetchAndShowPasses() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(theme.shareGradient)
                            .frame(width: 32, height: 32)

                        if isFetchingPasses {
                            ProgressView()
                                .scaleEffect(0.5)
                                .tint(.white)
                        } else {
                            Image(systemName: "gift.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("Share Claude Code")
                .accessibilityLabel("Share Claude Code")
                .keyboardShortcut("s")
            }

            // Settings Button with update indicator
            Button {
                // Avoid window resize animation glitches in MenuBarExtra.
                showSettings = true
            } label: {
                ZStack {
                    Circle()
                        .fill(theme.glassBackground)
                        .frame(width: 32, height: 32)

                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.textSecondary)

                    // Update available indicator
                    #if ENABLE_SPARKLE
                    if sparkleUpdater?.isUpdateAvailable == true {
                        UpdateBadge(accentColor: theme.accentPrimary)
                            .offset(x: 14, y: -14)
                    }
                    #endif
                }
            }
            .buttonStyle(.plain)
            .help(updateAvailableHelpText)
            .accessibilityLabel("Settings")
            .keyboardShortcut(",")

            // Quit Button
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                ZStack {
                    Circle()
                        .fill(theme.glassBackground)
                        .frame(width: 32, height: 32)

                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .help("Quit ClaudeBar")
            .accessibilityLabel("Quit ClaudeBar")
            .keyboardShortcut("q")
        }
        .opacity(animateIn ? 1 : 0)
        .animation(.easeOut(duration: 0.5).delay(0.3), value: animateIn)
    }

    // MARK: - Actions

    /// Refresh all enabled providers concurrently
    private func refreshAllEnabled() async {
        await withTaskGroup(of: Void.self) { group in
            // The `isSyncing` guard reads main-actor provider state, so evaluate
            // it here on the main actor (this closure inherits the caller's
            // isolation). Each child task then awaits `refresh()`, whose heavy
            // probe work still suspends off-main, keeping the refreshes concurrent.
            for provider in monitor.enabledProviders where !provider.isSyncing {
                group.addTask {
                    do {
                        try await provider.refresh()
                    } catch {
                        // Provider stores error in lastError
                    }
                }
            }
        }
    }

    /// Refresh a specific provider by ID
    private func refresh(providerId: String) async {
        guard let provider = monitor.provider(for: providerId) else {
            return
        }

        // Provider.isSyncing is observable - prevents duplicate refreshes
        guard !provider.isSyncing else { return }

        do {
            try await provider.refresh()
        } catch {
            // Provider stores error in lastError
        }
    }

    /// Fetch guest passes and show the share view
    private func fetchAndShowPasses() async {
        guard let claudeProvider = selectedProvider as? ClaudeProvider else {
            return
        }

        // Prevent duplicate fetches
        guard !claudeProvider.isFetchingPasses else { return }

        do {
            _ = try await claudeProvider.fetchPasses()
            withAnimation(.easeInOut(duration: 0.2)) {
                showSharePass = true
            }
        } catch {
            // Provider stores the error in passError, which the popover surfaces
            // as SharePassErrorOverlay — a failed click is never silent.
        }
    }
}

// MARK: - Provider Pill

struct ProviderPill: View {
    let providerId: String
    let providerName: String
    let isSelected: Bool
    let hasData: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: providerIcon)
                    .font(.system(size: 10, weight: .semibold))

                Text(providerName)
                    .font(theme.font(.body))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(isSelected ? (theme.id == "cli" ? theme.textPrimary : .white) : theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                            .fill(theme.accentGradient)
                            .shadow(color: theme.accentPrimary.opacity(0.3), radius: 6, y: 2)
                    } else {
                        RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                            .fill(isHovering ? theme.hoverOverlay : theme.glassBackground)
                    }

                    RoundedRectangle(cornerRadius: theme.pillCornerRadius)
                        .stroke(isSelected ? theme.accentPrimary.opacity(0.5) : theme.glassBorder, lineWidth: 1)
                }
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var providerIcon: String {
        ProviderVisualIdentityLookup.symbolIcon(for: providerId)
    }
}

// MARK: - Provider Pill Overflow

private struct PillsContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct PillsViewportWidthKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Two-Column Card Grid

/// Non-lazy two-column grid for popover cards.
///
/// The popover shows at most a few dozen lightweight cards, so laziness buys
/// nothing — and `LazyVGrid` actively hurts: lazy containers report an
/// estimated height and correct it as cells materialize, and inside the
/// popover's vertical `ScrollView` each correction rewrites the scroll offset
/// mid-gesture. Scrolling upward trembled, snapped back, and only got through
/// with an exaggerated flick. An eager grid hands the scroll view exact
/// content heights up front, so dragging stays smooth in both directions.
///
/// Layout matches the `LazyVGrid` it replaces: two equal flexible columns,
/// `spacing` between rows and columns, cells center-aligned per row, and a
/// lone card in the last row keeps column width instead of stretching.
struct TwoColumnCardGrid<Item, ID: Hashable, Cell: View>: View {
    let items: [Item]
    let id: KeyPath<Item, ID>
    var spacing: CGFloat = 10
    @ViewBuilder let cell: (Item) -> Cell

    init(
        items: [Item],
        id: KeyPath<Item, ID>,
        spacing: CGFloat = 10,
        @ViewBuilder cell: @escaping (Item) -> Cell
    ) {
        self.items = items
        self.id = id
        self.spacing = spacing
        self.cell = cell
    }

    /// Rows are keyed by their leading item so a stable card list keeps
    /// stable row identity across refreshes (no re-run of card appear
    /// animations); when the list itself changes, affected rows rebuild.
    private var rows: [(id: ID, leading: Item, trailing: Item?)] {
        stride(from: 0, to: items.count, by: 2).map { start in
            (
                id: items[start][keyPath: id],
                leading: items[start],
                trailing: start + 1 < items.count ? items[start + 1] : nil
            )
        }
    }

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(rows, id: \.id) { row in
                HStack(spacing: spacing) {
                    cell(row.leading)
                        .frame(maxWidth: .infinity)
                    if let trailing = row.trailing {
                        cell(trailing)
                            .frame(maxWidth: .infinity)
                    } else {
                        // Hold the empty slot so a lone final card keeps
                        // column width instead of stretching across the row.
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: 0)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }
}

// MARK: - Wrapped Stat Card

struct WrappedStatCard: View {
    let bucket: QuotaBucket
    let delay: Double
    var showsReset: Bool = true

    @Environment(\.appTheme) private var theme
    @Environment(\.motionPolicy) private var motion
    @State private var isHovering = false
    @State private var animateProgress = false
    @State private var settings = AppSettings.shared
    @State private var storedReset: StoredReset?
    @State private var isEditingReset = false
    @State private var draftReset = Date()

    /// Every member of a bucket carries the same value and reset, so the
    /// representative speaks for all of them on the card face.
    private var quota: UsageQuota { bucket.representative }

    /// What the card calls this limit.
    ///
    /// Named after the window when one is known, because a bucket spanning
    /// Claude Sonnet, Claude Opus and GPT-OSS has no shared model name to
    /// borrow. Falls back to the membership count, and only then to the
    /// single quota's own label.
    private var cardTitle: String {
        if let window = bucket.windowTitle { return window.uppercased() }
        if bucket.memberCount > 1 { return "\(bucket.memberCount) MODELS" }
        return (quota.compactTitle ?? quota.quotaType.displayName).uppercased()
    }

    /// Shown opposite the title when the title is a window, so the card still
    /// says how many models sit behind it.
    private var memberCaption: String? {
        guard bucket.memberCount > 1, bucket.windowTitle != nil else { return nil }
        return "\(bucket.memberCount) models"
    }

    /// What VoiceOver reads for this card. The face conveys status through a
    /// tinted number, a coloured bar and a tick mark, none of which is spoken.
    private var spokenDescription: String {
        let value: String
        if let dollarUsed = quota.formattedDollarUsed {
            value = dollarUsed
        } else if let dollarText = quota.formattedDollarRemaining {
            value = dollarText
        } else {
            value = "\(Int(quota.displayPercent(mode: effectiveDisplayMode)))%"
        }

        return QuotaAccessibility.description(
            title: cardTitle,
            value: value,
            valueCaption: valueCaption,
            statusText: effectiveDisplayMode == .pace
                ? quota.pace.displayName
                : quota.status.badgeText,
            resetText: showsReset ? resolvedReset?.description() : nil,
            memberCount: bucket.memberCount
        )
    }

    /// The full membership, revealed on hover rather than on the card face.
    private var membershipHelp: String {
        guard bucket.memberCount > 1 else { return "" }
        return bucket.members
            .map { $0.compactTitle ?? $0.quotaType.displayName }
            .joined(separator: "\n")
    }

    /// The reset to show, drawn from the provider, the user's entry, or what
    /// the app remembered — see `UsageQuota.resolvedReset`.
    private var resolvedReset: ResolvedReset? {
        quota.resolvedReset(stored: storedReset)
    }

    /// Loaded once per appearance rather than read during `body`, which runs
    /// for every card on every render.
    private func loadStoredReset() {
        storedReset = JSONResetRepository.shared.storedReset(
            providerId: quota.providerId,
            quotaKey: quota.quotaType.quotaKey
        )
    }

    /// Writes a manual reset for every member of the bucket.
    ///
    /// Buckets are a display-time construct, so the edit fans out to each
    /// member's own record. If the bucket later splits, every member keeps the
    /// reset the user set rather than losing it with the group.
    private func applyManualReset(_ date: Date) {
        let record = StoredReset(date: date, source: .manual, recordedAt: Date())
        for member in bucket.members {
            JSONResetRepository.shared.record(
                record,
                providerId: member.providerId,
                quotaKey: member.quotaType.quotaKey
            )
        }
        loadStoredReset()
    }

    private func clearManualReset() {
        for member in bucket.members {
            JSONResetRepository.shared.clear(
                providerId: member.providerId,
                quotaKey: member.quotaType.quotaKey
            )
        }
        loadStoredReset()
    }

    private var displayMode: UsageDisplayMode {
        settings.usageDisplayMode
    }

    /// Effective display mode: falls back to .used when pace is unknown
    private var effectiveDisplayMode: UsageDisplayMode {
        if displayMode == .pace && quota.pace == .unknown {
            return .used
        }
        return displayMode
    }

    private var statusColor: Color {
        theme.statusColor(for: quota.status)
    }

    private var isCappedSpend: Bool {
        quota.dollarUsed != nil && quota.dollarCap != nil
    }

    private var valueCaption: String {
        if isCappedSpend { return "Spent" }
        if quota.isDollarBased { return "Remaining" }
        return effectiveDisplayMode.displayLabel
    }

    /// The color used for the pace label/number
    private var paceColor: Color {
        quota.pace.displayColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header row with icon, type, and badge
            HStack(alignment: .top, spacing: 0) {
                // Left side: icon and type label
                HStack(spacing: Spacing.sm) {
                    Image(systemName: iconName)
                        .font(theme.font(.microLabel))
                        .foregroundStyle(statusColor)

                    Text(cardTitle)
                        .typeScale(.microLabel, theme: theme)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 4)

                // Pace and status already reach the eye through the value's
                // tint and the tick on the progress bar; a third copy as a
                // badge cost ~93pt of a 155pt card and truncated the title.
                if let memberCaption {
                    Text(memberCaption)
                        .typeScale(.microLabel, theme: theme)
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize()
                }
            }

            // Large value display with label (end-aligned)
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                if let dollarUsed = quota.formattedDollarUsed,
                   let dollarCap = quota.formattedDollarCap {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                        Text(dollarUsed)
                            .font(theme.font(.statValue))
                            .foregroundStyle(theme.textPrimary)
                            .contentTransition(.numericText())

                        Text("of \(dollarCap)")
                            .font(theme.font(.caption))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
                } else if let dollarText = quota.formattedDollarRemaining {
                    Text(dollarText)
                        .font(theme.font(.statValue))
                        .foregroundStyle(theme.textPrimary)
                        .contentTransition(.numericText())
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(Int(quota.displayPercent(mode: effectiveDisplayMode)))")
                            .font(theme.font(.statValue))
                            .foregroundStyle(effectiveDisplayMode == .pace ? paceColor : theme.textPrimary)
                            .contentTransition(.numericText())

                        Text("%")
                            .font(theme.font(.body))
                            .foregroundStyle(effectiveDisplayMode == .pace ? paceColor.opacity(0.7) : theme.textTertiary)
                    }
                }

                Text(valueCaption)
                    .font(theme.font(.caption))
                    .fixedSize()
                    .foregroundStyle(effectiveDisplayMode == .pace ? paceColor.opacity(0.8) : theme.textTertiary)

                Spacer(minLength: 0)
            }

            // Progress bar with gradient and pace tick
            VStack(spacing: 1) {
                GeometryReader { geo in
                    let progressPercent = quota.displayProgressPercent(mode: effectiveDisplayMode)
                    ZStack(alignment: .leading) {
                        // Track
                        RoundedRectangle(cornerRadius: 3)
                            .fill(theme.progressTrack)

                        // Fill (clamp width to 0-100%)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(theme.progressGradient(for: quota.percentRemaining))
                            .frame(width: animateProgress ? geo.size.width * max(0, min(100, progressPercent)) / 100 : 0)
                            .animation(
                                motion.animation(
                                    .spring(response: 0.8, dampingFraction: 0.7)
                                        .delay(motion.delay(delay + 0.2))
                                ),
                                value: animateProgress
                            )
                    }
                }
                .frame(height: 6)

                // Expected pace tick mark
                if let expectedPercent = quota.expectedProgressPercent(mode: effectiveDisplayMode) {
                    GeometryReader { geo in
                        let tickX = geo.size.width * max(0, min(100, expectedPercent)) / 100
                        Path { path in
                            path.move(to: CGPoint(x: tickX - 3, y: 4))
                            path.addLine(to: CGPoint(x: tickX + 3, y: 4))
                            path.addLine(to: CGPoint(x: tickX, y: 0))
                            path.closeSubpath()
                        }
                        .fill(theme.textTertiary)
                        .opacity(animateProgress ? 1 : 0)
                        .animation(
                            motion.animation(.easeIn(duration: 0.3).delay(motion.delay(delay + 0.5))),
                            value: animateProgress
                        )
                    }
                    .frame(height: 5)
                }
            }
            .help(quota.paceTickHelp(mode: effectiveDisplayMode) ?? "")

            // Reset info (hidden when the grid hoisted a shared countdown)
            if showsReset,
               let resetText = resolvedReset?.description() ?? quota.resetText {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "clock.fill")
                        .font(theme.font(.caption))

                    Text(resetText)
                        .font(theme.font(.caption))
                }
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)
            }
        }
        .padding(Spacing.lg)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .fill(theme.cardGradient)

                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .stroke(theme.glassBorder, lineWidth: 1)
            }
        )
        .scaleEffect(isHovering ? 1.015 : 1.0)
        .animation(motion.animation(.easeOut(duration: 0.15)), value: isHovering)
        .onHover { isHovering = $0 }
        .help(membershipHelp)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenDescription)
        .contextMenu {
            Button(storedReset?.source == .manual ? "Change reset time…" : "Set reset time…") {
                draftReset = resolvedReset?.date ?? Date().addingTimeInterval(3600)
                isEditingReset = true
            }

            if storedReset?.source == .manual {
                Button("Clear reset time", role: .destructive) {
                    clearManualReset()
                }
            }
        }
        .popover(isPresented: $isEditingReset, arrowEdge: .bottom) {
            resetEditor
        }
        .onAppear {
            animateProgress = true
            loadStoredReset()
        }
    }

    /// Manual reset entry, for providers that report usage but never say when
    /// it resets. Fill-only: a value the provider reports still wins, so this
    /// fills silence rather than overriding live data.
    private var resetEditor: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text(cardTitle)
                .font(theme.font(.bodyEmphasis))

            DatePicker(
                "Resets at",
                selection: $draftReset,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)

            if bucket.memberCount > 1 {
                Text("Applies to all \(bucket.memberCount) models in this limit.")
                    .font(theme.font(.caption))
                    .foregroundStyle(.secondary)
            }

            Text("Used only while the provider reports no reset of its own.")
                .font(theme.font(.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel") { isEditingReset = false }
                Button("Save") {
                    applyManualReset(draftReset)
                    isEditingReset = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 280)
    }

    private var iconName: String {
        let title = (quota.compactTitle ?? quota.quotaType.displayName).lowercased()
        if title.contains("build") { return "hammer.fill" }
        if title.contains("chat") { return "bubble.left.fill" }
        if title.contains("imagine") { return "sparkles" }

        switch quota.quotaType {
        case .session: return "bolt.fill"
        case .weekly: return "calendar.badge.clock"
        case .modelSpecific: return "cpu.fill"
        case .timeLimit: return "clock.fill"
        }
    }
}

// MARK: - Loading Spinner View

struct LoadingSpinnerView: View {
    @Environment(\.appTheme) private var theme
    @State private var isSpinning = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(theme.textTertiary, lineWidth: 3)
                    .frame(width: 50, height: 50)

                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(
                        theme.accentGradient,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(isSpinning ? 360 : 0))
                    .animation(
                        .linear(duration: 1).repeatForever(autoreverses: false),
                        value: isSpinning
                    )
            }

            Text("Fetching usage data...")
                .font(theme.font(.body))
                .foregroundStyle(theme.textSecondary)
        }
        .frame(height: 140)
        .frame(maxWidth: .infinity)
        .glassCard()
        .onAppear {
            isSpinning = true
        }
    }
}

// MARK: - Wrapped Action Button

struct WrappedActionButton: View {
    let icon: String
    let label: String
    let gradient: LinearGradient
    var isLoading: Bool = false
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 14, height: 14)
                        .tint(theme.textPrimary)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }

                Text(label)
                    .font(theme.font(.body))
                    .fixedSize()
            }
            .foregroundStyle(isHovering ? .white : theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    Capsule()
                        .fill(isHovering ? AnyShapeStyle(gradient) : AnyShapeStyle(theme.glassBackground))

                    Capsule()
                        .stroke(theme.glassBorder, lineWidth: 1)
                }
            )
            .shadow(color: isHovering ? theme.accentPrimary.opacity(0.3) : .clear, radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .disabled(isLoading)
    }
}

// MARK: - Visual Effect Blur (macOS) - Kept for compatibility

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Horizontal Scroll Booster

/// Converts vertical mouse wheel scroll events to horizontal scrolling.
/// Trackpads natively produce horizontal gestures, but mouse scroll wheels only
/// generate vertical deltas — this bridges the gap for horizontal ScrollViews.
///
/// Uses `NSEvent.addLocalMonitorForEvents` to intercept scroll events at the
/// app level before they reach the NSScrollView, which would otherwise ignore
/// vertical deltas in a horizontal-only scroll view.
struct HorizontalScrollBooster: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.startMonitoring()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var monitor: Any?
        weak var view: NSView?

        func startMonitoring() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self,
                      let view = self.view,
                      let scrollView = view.enclosingScrollView else {
                    return event
                }

                // Only act on events over this scroll view
                let point = scrollView.convert(event.locationInWindow, from: nil)
                guard scrollView.bounds.contains(point) else {
                    return event
                }

                // Only convert predominantly vertical scrolls
                guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else {
                    return event
                }

                guard let cgEvent = event.cgEvent?.copy() else {
                    return event
                }

                // Swap vertical → horizontal
                cgEvent.setDoubleValueField(
                    .scrollWheelEventDeltaAxis2,
                    value: cgEvent.getDoubleValueField(.scrollWheelEventDeltaAxis1)
                )
                cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: 0)

                cgEvent.setIntegerValueField(
                    .scrollWheelEventPointDeltaAxis2,
                    value: cgEvent.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
                )
                cgEvent.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 0)

                return NSEvent(cgEvent: cgEvent) ?? event
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }
}

// MARK: - Gradient Stops Extension

extension LinearGradient {
    var stops: [Gradient.Stop] {
        // Default empty - used for animation color extraction
        []
    }
}

// MARK: - Pulsing Status Dot

/// A status dot that pulses when syncing, with proper animation lifecycle management.
struct PulsingStatusDot: View {
    let color: Color
    let isSyncing: Bool

    @State private var pulsePhase: CGFloat = 0

    var body: some View {
        ZStack {
            // Solid center dot
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            // Pulsing ring (only visible when syncing)
            if isSyncing {
                Circle()
                    .stroke(color, lineWidth: 2)
                    .frame(width: 16, height: 16)
                    .scaleEffect(1 + pulsePhase * 0.5)
                    .opacity(1 - pulsePhase)
            } else {
                // Static ring when not syncing
                Circle()
                    .stroke(color, lineWidth: 2)
                    .frame(width: 16, height: 16)
                    .opacity(0.5)
            }
        }
        .onChange(of: isSyncing) { _, syncing in
            if syncing {
                startPulsing()
            } else {
                stopPulsing()
            }
        }
        .onAppear {
            if isSyncing {
                startPulsing()
            }
        }
    }

    private func startPulsing() {
        pulsePhase = 0
        withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) {
            pulsePhase = 1
        }
    }

    private func stopPulsing() {
        withAnimation(.easeOut(duration: 0.3)) {
            pulsePhase = 0
        }
    }
}

// MARK: - Update Badge

/// A polished badge indicating an update is available
struct UpdateBadge: View {
    var accentColor: Color = BaseTheme.coralAccent

    private var badgeGradient: LinearGradient {
        LinearGradient(
            colors: [accentColor, accentColor.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(badgeGradient)
                .frame(width: 18, height: 18)
                .blur(radius: 3)
                .opacity(0.5)

            // Main badge
            Circle()
                .fill(badgeGradient)
                .frame(width: 14, height: 14)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)

            // Arrow up icon
            Image(systemName: "arrow.up")
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Bedrock Usage Card

/// Displays AWS Bedrock usage with cost and per-model breakdown.
struct BedrockUsageCard: View {
    let usage: BedrockUsageSummary
    let delay: Double

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    @State private var animateIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with cost
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(ProviderVisualIdentityLookup.color(for: "bedrock", scheme: colorScheme))

                        Text("TODAY'S USAGE")
                            .font(theme.font(.microLabel))
                            .foregroundStyle(theme.textSecondary)
                            .tracking(0.5)
                    }

                    // Large cost number
                    Text(usage.formattedTotalCost)
                        .font(.system(size: 36, weight: .bold, design: theme.fontDesign))
                        .foregroundStyle(theme.textPrimary)
                        .contentTransition(.numericText())
                }

                Spacer()

                // Stats column
                VStack(alignment: .trailing, spacing: 4) {
                    StatPill(icon: "number", value: "\(usage.totalInvocations)", label: "calls")
                    StatPill(icon: "text.word.spacing", value: usage.formattedTotalTokens, label: "tokens")
                }
            }

            // Model breakdown (if multiple models)
            if usage.modelUsages.count > 0 {
                Divider()
                    .background(theme.glassBorder)

                VStack(spacing: 6) {
                    ForEach(usage.modelsBySpend.prefix(3), id: \.model.id) { modelUsage in
                        HStack {
                            Text(modelUsage.model.displayName)
                                .font(theme.font(.body))
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)

                            Spacer()

                            Text(modelUsage.formattedCost)
                                .font(theme.font(.bodyEmphasis))
                                .foregroundStyle(theme.textPrimary)
                        }
                    }

                    // Show "and X more" if more than 3 models
                    if usage.modelUsages.count > 3 {
                        Text("and \(usage.modelUsages.count - 3) more...")
                            .font(theme.font(.caption))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }

            // Budget progress (if set)
            if let budgetPercent = usage.budgetPercentUsed,
               let budgetFormatted = usage.formattedDailyBudget {
                Divider()
                    .background(theme.glassBorder)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Daily Budget")
                            .font(theme.font(.caption))
                            .foregroundStyle(theme.textSecondary)

                        Spacer()

                        Text("\(Int(min(budgetPercent, 100)))% of \(budgetFormatted)")
                            .font(theme.font(.microLabel))
                            .foregroundStyle(budgetPercent > 90 ? theme.statusCritical : theme.textPrimary)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(theme.progressTrack)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(budgetPercent > 90 ? theme.statusCritical : theme.accentPrimary)
                                .frame(width: geo.size.width * min(CGFloat(budgetPercent) / 100, 1.0))
                        }
                    }
                    .frame(height: 4)
                }
            }

            // Time period
            HStack(spacing: 3) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 8))

                Text("Since \(formattedPeriodStart)")
                    .font(theme.font(.caption))
            }
            .foregroundStyle(theme.textTertiary)
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .fill(theme.cardGradient)

                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .stroke(theme.glassBorder, lineWidth: 1)
            }
        )
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 10)
        .animation(.easeOut(duration: 0.5).delay(delay), value: animateIn)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
        .onAppear { animateIn = true }
    }

    // Cached formatter to avoid recreation overhead
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private var formattedPeriodStart: String {
        Self.timeFormatter.string(from: usage.periodStart)
    }
}

// MARK: - Stat Pill (for Bedrock card)

private struct StatPill: View {
    let icon: String
    let value: String
    let label: String

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(theme.textTertiary)

            Text(value)
                .font(theme.font(.bodyEmphasis))
                .foregroundStyle(theme.textPrimary)

            Text(label)
                .font(theme.font(.caption))
                .foregroundStyle(theme.textTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(theme.glassBackground)
        )
    }
}
