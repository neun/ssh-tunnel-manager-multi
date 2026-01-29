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
                    .contextMenu {
                        Button {
                            tunnelManager.moveTunnelUp(tunnel)
                        } label: {
                            Label("Move Up", systemImage: "arrow.up")
                        }
                        .disabled(!canMoveUp(tunnel))

                        Button {
                            tunnelManager.moveTunnelDown(tunnel)
                        } label: {
                            Label("Move Down", systemImage: "arrow.down")
                        }
                        .disabled(!canMoveDown(tunnel))

                        Divider()

                        Button {
                            let clone = tunnelManager.cloneTunnel(tunnel)
                            selection = clone
                        } label: {
                            Label("Clone", systemImage: "doc.on.doc")
                        }

                        Divider()

                        Button(role: .destructive) {
                            if selection?.id == tunnel.id {
                                selection = nil
                            }
                            tunnelManager.deleteTunnel(tunnel)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            .onDelete(perform: deleteTunnels)
            .onMove(perform: moveTunnels)
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

    private func canMoveUp(_ tunnel: Tunnel) -> Bool {
        guard let index = tunnelManager.tunnels.firstIndex(where: { $0.id == tunnel.id }) else { return false }
        return index > 0
    }

    private func canMoveDown(_ tunnel: Tunnel) -> Bool {
        guard let index = tunnelManager.tunnels.firstIndex(where: { $0.id == tunnel.id }) else { return false }
        return index < tunnelManager.tunnels.count - 1
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

    private func moveTunnels(from source: IndexSet, to destination: Int) {
        tunnelManager.moveTunnel(from: source, to: destination)
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
