import SwiftUI

@MainActor
struct TunnelDetailView: View {
    let tunnel: Tunnel
    @Environment(TunnelManager.self) private var tunnelManager
    @FocusState private var focusedField: Field?

    @State private var editedTunnel: Tunnel
    @State private var hasChanges = false

    enum Field: Hashable {
        case name, host, port, identityFile, localHost, localPort, remoteHost, remotePort, alias
    }

    init(tunnel: Tunnel) {
        self.tunnel = tunnel
        self._editedTunnel = State(initialValue: tunnel)
    }

    private var status: ConnectionStatus {
        tunnelManager.status(for: tunnel)
    }

    private var statusText: String {
        switch status {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        }
    }

    private var statusColor: Color {
        switch status {
        case .disconnected: return .secondary
        case .connecting: return .yellow
        case .connected: return .green
        }
    }

    var body: some View {
        Form {
            // Status section at top
            Section {
                HStack {
                    StatusIndicator(status: status)
                    Text(statusText)
                        .foregroundStyle(statusColor)

                    Spacer()

                    Button(status != .disconnected ? "Disconnect" : "Connect") {
                        tunnelManager.toggle(tunnel: tunnel)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(status != .disconnected ? .red : .green)
                }

                UsageRow(label: "SSH", value: sshCommand(for: editedTunnel))
            } header: {
                Text("Status")
            }

            Section {
                TextField("Name", text: $editedTunnel.name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .name)
            } header: {
                Text("General")
            }

            Section {
                Picker("Mode", selection: $editedTunnel.useAlias) {
                    Text("Host").tag(false)
                    Text("SSH Alias").tag(true)
                }
                .pickerStyle(.segmented)

                if editedTunnel.useAlias {
                    LabeledContent("Alias") {
                        TextField("my-server", text: $editedTunnel.host)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .focused($focusedField, equals: .alias)
                    }

                    Text("Uses ~/.ssh/config alias (no -i flag needed)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    LabeledContent("Host") {
                        HStack(spacing: 4) {
                            TextField("user@server.com", text: $editedTunnel.host)
                                .textFieldStyle(.roundedBorder)
                                .labelsHidden()
                                .focused($focusedField, equals: .host)
                            Text(":")
                                .foregroundStyle(.secondary)
                            TextField("", value: $editedTunnel.port, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                                .labelsHidden()
                                .focused($focusedField, equals: .port)
                        }
                    }

                    TextField("Identity File (optional)", text: Binding(
                        get: { editedTunnel.identityFile ?? "" },
                        set: { editedTunnel.identityFile = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .identityFile)

                    Text("e.g., ~/.ssh/id_rsa")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("SSH Connection")
            }

            Section {
                LabeledContent("Local") {
                    HStack(spacing: 4) {
                        TextField("Host", text: $editedTunnel.localHost)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .focused($focusedField, equals: .localHost)
                        Text(":")
                            .foregroundStyle(.secondary)
                        TextField("", value: $editedTunnel.localPort, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                            .labelsHidden()
                            .focused($focusedField, equals: .localPort)
                    }
                }

                LabeledContent("Remote") {
                    HStack(spacing: 4) {
                        TextField("Host", text: $editedTunnel.remoteHost)
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .focused($focusedField, equals: .remoteHost)
                        Text(":")
                            .foregroundStyle(.secondary)
                        TextField("", value: $editedTunnel.remotePort, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                            .labelsHidden()
                            .focused($focusedField, equals: .remotePort)
                    }
                }
            } header: {
                Text("Port Forwarding")
            }

            Section {
                Toggle("Auto-connect on launch", isOn: $editedTunnel.autoConnect)
            } header: {
                Text("Options")
            }

            // Usage examples section
            if status == .connected {
                Section {
                    UsageRow(label: "HTTP", value: "http://\(tunnel.localHost):\(tunnel.localPort)")
                    UsageRow(label: "Host:Port", value: "\(tunnel.localHost):\(tunnel.localPort)")
                } header: {
                    Text("Usage")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save") {
                    saveChanges()
                }
                .disabled(!hasChanges)
            }
        }
        .onChange(of: editedTunnel) { _, _ in
            hasChanges = true
        }
        .onChange(of: tunnel) { _, newValue in
            editedTunnel = newValue
            hasChanges = false
        }
        .onChange(of: focusedField) { oldValue, newValue in
            // Auto-save when focus changes (field loses focus)
            if oldValue != nil && newValue != oldValue && hasChanges {
                saveChanges()
            }
        }
    }

    private func saveChanges() {
        tunnelManager.updateTunnel(editedTunnel)
        hasChanges = false
    }

    private func sshCommand(for tunnel: Tunnel) -> String {
        var cmd = "ssh -N -L \(tunnel.localHost):\(tunnel.localPort):\(tunnel.remoteHost):\(tunnel.remotePort)"
        if tunnel.useAlias {
            // For alias mode, only add -p if not default port
            if tunnel.port != 22 {
                cmd += " -p \(tunnel.port)"
            }
        } else {
            // For host mode, always add -p and optionally -i
            if tunnel.port != 22 {
                cmd += " -p \(tunnel.port)"
            }
            if let identityFile = tunnel.identityFile, !identityFile.isEmpty {
                cmd += " -i \(identityFile)"
            }
        }
        cmd += " \(tunnel.host)"
        return cmd
    }
}

struct UsageRow: View {
    let label: String
    let value: String
    @State private var copied = false

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(copied ? .green : .secondary)
            .help("Copy to clipboard")
        }
    }
}

#Preview {
    TunnelDetailView(tunnel: Tunnel(
        name: "Test Tunnel",
        host: "user@example.com",
        port: 22,
        localHost: "127.0.0.1",
        localPort: 8080,
        remoteHost: "127.0.0.1",
        remotePort: 8080
    ))
    .environment(TunnelManager())
    .frame(width: 500, height: 700)
}
