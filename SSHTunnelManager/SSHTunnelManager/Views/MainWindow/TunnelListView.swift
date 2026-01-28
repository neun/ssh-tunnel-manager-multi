import SwiftUI

@MainActor
struct TunnelListView: View {
    @Environment(TunnelManager.self) private var tunnelManager
    @Binding var selection: Tunnel?

    var body: some View {
        List(selection: $selection) {
            ForEach(tunnelManager.tunnels) { tunnel in
                TunnelRow(tunnel: tunnel)
                    .tag(tunnel)
            }
            .onDelete(perform: deleteTunnels)
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    tunnelManager.addTunnel()
                    // Select the newly added tunnel
                    if let newTunnel = tunnelManager.tunnels.last {
                        selection = newTunnel
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add new tunnel")
            }
        }
    }

    private func deleteTunnels(at offsets: IndexSet) {
        for index in offsets {
            let tunnel = tunnelManager.tunnels[index]
            if selection?.id == tunnel.id {
                selection = nil
            }
            tunnelManager.deleteTunnel(tunnel)
        }
    }
}

@MainActor
struct TunnelRow: View {
    let tunnel: Tunnel
    @Environment(TunnelManager.self) private var tunnelManager

    var body: some View {
        HStack(spacing: 8) {
            StatusIndicator(status: tunnelManager.status(for: tunnel), size: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(tunnel.name)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(":\(tunnel.localPort) → :\(tunnel.remotePort)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    TunnelListView(selection: .constant(nil))
        .environment(TunnelManager())
        .frame(width: 250)
}
