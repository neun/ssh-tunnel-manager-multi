import SwiftUI
import ServiceManagement

struct ContentView: View {
    @Environment(TunnelManager.self) private var tunnelManager
    @State private var selectedTunnel: Tunnel?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                TunnelListView(selection: $selectedTunnel)

                Divider()

                // Action bar for selected tunnel
                if let tunnel = selectedTunnel {
                    HStack(spacing: 12) {
                        Button {
                            tunnelManager.moveTunnelUp(tunnel)
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .disabled(!canMoveUp(tunnel))
                        .help("Move Up")

                        Button {
                            tunnelManager.moveTunnelDown(tunnel)
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .disabled(!canMoveDown(tunnel))
                        .help("Move Down")

                        Divider()
                            .frame(height: 16)

                        Button {
                            let clone = tunnelManager.cloneTunnel(tunnel)
                            selectedTunnel = clone
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .help("Clone")

                        Spacer()

                        Button(role: .destructive) {
                            selectedTunnel = nil
                            tunnelManager.deleteTunnel(tunnel)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help("Delete")
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    Divider()
                }

                HStack {
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .onChange(of: launchAtLogin) { _, newValue in
                            do {
                                if newValue {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                print("Failed to update login item: \(error)")
                                launchAtLogin = !newValue
                            }
                        }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 350)
        } detail: {
            if let tunnel = selectedTunnel,
               tunnelManager.tunnels.contains(where: { $0.id == tunnel.id }) {
                TunnelDetailView(tunnel: tunnel)
            } else {
                ContentUnavailableView {
                    Label("No Tunnel Selected", systemImage: "point.3.connected.trianglepath.dotted")
                } description: {
                    Text("Select a tunnel from the sidebar or create a new one.")
                } actions: {
                    Button("Add Tunnel") {
                        tunnelManager.addTunnel()
                        if let newTunnel = tunnelManager.tunnels.last {
                            selectedTunnel = newTunnel
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .onChange(of: tunnelManager.tunnels) { _, newTunnels in
            // Update selection if current tunnel was modified
            if let selected = selectedTunnel,
               let updated = newTunnels.first(where: { $0.id == selected.id }) {
                selectedTunnel = updated
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
}

#Preview {
    ContentView()
        .environment(TunnelManager())
}
