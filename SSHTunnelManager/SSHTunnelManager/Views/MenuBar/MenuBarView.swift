import SwiftUI

@MainActor
struct MenuBarView: View {
    @Environment(TunnelManager.self) private var tunnelManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if tunnelManager.tunnels.isEmpty {
                Text("No tunnels configured")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ForEach(tunnelManager.tunnels) { tunnel in
                    TunnelMenuItem(tunnel: tunnel)
                }
            }

            Divider()
                .padding(.vertical, 4)

            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                HStack {
                    Image(systemName: "gear")
                    Text("Settings...")
                    Spacer()
                    Text("⌘,")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Image(systemName: "power")
                    Text("Quit")
                    Spacer()
                    Text("⌘Q")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .frame(minWidth: 280, maxWidth: 400)
        .fixedSize(horizontal: true, vertical: false)
    }
}

@MainActor
struct TunnelMenuItem: View {
    let tunnel: Tunnel
    @Environment(TunnelManager.self) private var tunnelManager

    private var status: ConnectionStatus {
        tunnelManager.status(for: tunnel)
    }

    private var isOn: Bool {
        status == .connected || status == .connecting
    }

    private var statusColor: Color {
        switch status {
        case .disconnected: return .secondary
        case .connecting: return .orange
        case .connected: return .green
        }
    }

    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(tunnel.name)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Text(":\(tunnel.localPort)")
                .foregroundStyle(.secondary)

            Toggle("", isOn: Binding(
                get: { isOn },
                set: { _ in tunnelManager.toggle(tunnel: tunnel) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

#Preview {
    MenuBarView()
        .environment(TunnelManager())
}
