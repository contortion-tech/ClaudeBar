import SwiftUI
import Domain
import Infrastructure

/// Antigravity provider configuration card for SettingsView.
struct AntigravityConfigCard: View {
    let monitor: QuotaMonitor

    @State private var settings = AppSettings.shared
    @Environment(\.appTheme) private var theme

    @State private var isExpanded: Bool = false
    @State private var isAvailable: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Divider()
                .background(theme.glassBorder)
                .padding(.vertical, 12)

            configForm
        } label: {
            configHeader
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    theme.glassBorder, theme.glassBorder.opacity(0.5)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .task {
            // Check availability asynchronously since it requires checking processes
            let probe = AntigravityUsageProbe()
            isAvailable = await probe.isAvailable()
        }
    }

    private var configHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [theme.accentPrimary.opacity(0.2), theme.accentSecondary.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)

                Image(systemName: "wand.and.stars")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.accentPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Antigravity Configuration")
                    .font(theme.font(.title))
                    .foregroundStyle(theme.textPrimary)

                Text("Local Language Server Quota")
                    .font(theme.font(.caption))
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer()
        }
    }

    private var configForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.accentPrimary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Local Process Probing")
                            .font(theme.font(.microLabel))
                            .foregroundStyle(theme.textPrimary)

                        Text("Automatically discovers and connects to the Antigravity local language server process.")
                            .font(theme.font(.caption))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(isAvailable ? theme.statusHealthy : theme.statusWarning)

                Text(isAvailable ? "Language server found running" : "Language server not detected")
                    .font(theme.font(.microLabel))
                    .foregroundStyle(isAvailable ? theme.statusHealthy : theme.statusWarning)
            }

            if !isAvailable {
                Text("Ensure Antigravity is running in your IDE or terminal to track usage.")
                    .font(theme.font(.caption))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }
}
