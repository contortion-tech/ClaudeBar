import SwiftUI
import Domain
import Infrastructure

/// Cursor provider configuration card for SettingsView.
struct CursorConfigCard: View {
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
            // Check availability asynchronously
            let probe = CursorUsageProbe()
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

                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.accentPrimary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Cursor Configuration")
                    .font(theme.font(.title))
                    .foregroundStyle(theme.textPrimary)

                Text("Cursor IDE Pro/Team limits")
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
                    Image(systemName: "internaldrive")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.accentPrimary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Local State Parsing")
                            .font(theme.font(.microLabel))
                            .foregroundStyle(theme.textPrimary)

                        Text("Reads JWT token locally from Cursor's state.vscdb SQLite file.")
                            .font(theme.font(.caption))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(isAvailable ? theme.statusHealthy : theme.statusWarning)

                Text(isAvailable ? "Cursor authentication database found" : "Cursor database not found or missing auth")
                    .font(theme.font(.microLabel))
                    .foregroundStyle(isAvailable ? theme.statusHealthy : theme.statusWarning)
            }

            if !isAvailable {
                Text("Ensure you are logged into your Cursor IDE.")
                    .font(theme.font(.caption))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }
}
