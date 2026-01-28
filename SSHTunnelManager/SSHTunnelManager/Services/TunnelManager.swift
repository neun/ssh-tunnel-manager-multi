import Foundation
import SwiftUI
import Darwin

/// File to store active PIDs for cleanup on crash/force quit
private let pidFileURL: URL = {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let appFolder = appSupport.appendingPathComponent("SSHTunnelManager", isDirectory: true)
    try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
    return appFolder.appendingPathComponent("active_pids.txt")
}()

/// Process group ID for all SSH child processes (accessed from signal handlers, so must be global)
private var sshProcessGroupID: pid_t = 0

/// Kill SSH processes using specified local port
private func findAndKillSSHProcesses(localPort: Int) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
    task.arguments = ["-f", "ssh.*-L.*:\(localPort):"]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    try? task.run()
    task.waitUntilExit()
}

/// Kill processes by PIDs from file (cleanup from previous session)
private func killOrphanedProcesses() {
    guard FileManager.default.fileExists(atPath: pidFileURL.path) else { return }

    if let content = try? String(contentsOf: pidFileURL, encoding: .utf8) {
        let pids = content.components(separatedBy: "\n").compactMap { Int32($0) }
        for pid in pids {
            kill(pid, SIGKILL)
        }
    }
    try? FileManager.default.removeItem(at: pidFileURL)
}

/// Save active PIDs to file
private func savePIDsToFile(_ pids: [Int32]) {
    let content = pids.map { String($0) }.joined(separator: "\n")
    try? content.write(to: pidFileURL, atomically: true, encoding: .utf8)
}

/// Remove PID file
private func removePIDFile() {
    try? FileManager.default.removeItem(at: pidFileURL)
}

/// Kill entire process group (all SSH children)
private func killProcessGroup() {
    if sshProcessGroupID != 0 {
        // Kill entire process group with negative PID
        kill(-sshProcessGroupID, SIGKILL)
    }
}

@Observable
@MainActor
class TunnelManager {
    var tunnels: [Tunnel] = []
    private var processIDs: [UUID: Int32] = [:]
    private var connectionStatus: [UUID: ConnectionStatus] = [:]
    private var shouldBeConnected: Set<UUID> = [] // Tracks desired state for reconnection
    private let configStore = ConfigStore()
    private var reconnectTask: Task<Void, Never>?

    init() {
        // Kill any orphaned processes from previous session
        killOrphanedProcesses()

        // Create a new process group for SSH processes
        // Using our own PID ensures children inherit this group
        sshProcessGroupID = getpid()

        // Register atexit handler as last resort cleanup
        atexit {
            killProcessGroup()
        }

        Task {
            await loadTunnels()
            await autoConnectTunnels()
        }

        // Start reconnection monitor
        startReconnectMonitor()
    }

    private func startReconnectMonitor() {
        reconnectTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await reconnectDisconnectedTunnels()
            }
        }
    }

    private func reconnectDisconnectedTunnels() {
        for tunnelID in shouldBeConnected {
            guard let tunnel = tunnels.first(where: { $0.id == tunnelID }) else {
                shouldBeConnected.remove(tunnelID)
                continue
            }

            let status = connectionStatus[tunnelID] ?? .disconnected
            if status == .disconnected {
                // Mark as connecting and attempt reconnect
                connectionStatus[tunnelID] = .connecting
                reconnect(tunnel: tunnel)
            }
        }
    }

    private func reconnect(tunnel: Tunnel) {
        let localPort = tunnel.localPort
        let tunnelCopy = tunnel

        Task.detached {
            findAndKillSSHProcesses(localPort: localPort)
            try? await Task.sleep(for: .milliseconds(100))

            await MainActor.run {
                self.startSSHProcess(tunnel: tunnelCopy)
            }
        }
    }

    func loadTunnels() async {
        tunnels = await configStore.load()
    }

    func saveTunnels() async {
        await configStore.save(tunnels)
    }

    private func autoConnectTunnels() async {
        for tunnel in tunnels where tunnel.autoConnect {
            await connectAsync(tunnel: tunnel)
        }
    }

    func isConnected(_ tunnel: Tunnel) -> Bool {
        connectionStatus[tunnel.id] == .connected
    }

    func status(for tunnel: Tunnel) -> ConnectionStatus {
        connectionStatus[tunnel.id] ?? .disconnected
    }

    func connect(tunnel: Tunnel) {
        guard !isConnected(tunnel) else { return }

        // Mark as should be connected for auto-reconnect
        shouldBeConnected.insert(tunnel.id)
        connectionStatus[tunnel.id] = .connecting

        let localPort = tunnel.localPort
        let tunnelCopy = tunnel

        Task.detached {
            findAndKillSSHProcesses(localPort: localPort)
            try? await Task.sleep(for: .milliseconds(100))

            await MainActor.run {
                self.startSSHProcess(tunnel: tunnelCopy)
            }
        }
    }

    private func connectAsync(tunnel: Tunnel) async {
        guard !isConnected(tunnel) else { return }

        // Mark as should be connected for auto-reconnect
        shouldBeConnected.insert(tunnel.id)
        connectionStatus[tunnel.id] = .connecting

        let localPort = tunnel.localPort

        await Task.detached {
            findAndKillSSHProcesses(localPort: localPort)
            try? await Task.sleep(for: .milliseconds(100))
        }.value

        startSSHProcess(tunnel: tunnel)
    }

    private func startSSHProcess(tunnel: Tunnel) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")

        var arguments = [
            "-N",
            "-L", "\(tunnel.localHost):\(tunnel.localPort):\(tunnel.remoteHost):\(tunnel.remotePort)",
            tunnel.host,
            "-p", "\(tunnel.port)",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3"
        ]

        if let identityFile = tunnel.identityFile, !identityFile.isEmpty {
            let expandedPath = (identityFile as NSString).expandingTildeInPath
            arguments.insert(contentsOf: ["-i", expandedPath], at: 1)
        }

        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let pid = process.processIdentifier
            processIDs[tunnel.id] = pid
            connectionStatus[tunnel.id] = .connected

            // Save PIDs to file for crash recovery
            updatePIDFile()

            let tunnelID = tunnel.id
            Task.detached { [weak self] in
                process.waitUntilExit()
                await MainActor.run { [weak self] in
                    self?.handleProcessTermination(tunnelID: tunnelID)
                }
            }
        } catch {
            print("Failed to start SSH tunnel: \(error)")
            connectionStatus[tunnel.id] = .disconnected
        }
    }

    private func updatePIDFile() {
        let pids = Array(processIDs.values)
        if pids.isEmpty {
            removePIDFile()
        } else {
            savePIDsToFile(pids)
        }
    }

    private func handleProcessTermination(tunnelID: UUID) {
        processIDs.removeValue(forKey: tunnelID)
        // If should still be connected, mark as connecting (will trigger reconnect)
        // Otherwise mark as disconnected
        if shouldBeConnected.contains(tunnelID) {
            connectionStatus[tunnelID] = .connecting
        } else {
            connectionStatus[tunnelID] = .disconnected
        }
        updatePIDFile()
    }

    func disconnect(tunnel: Tunnel) {
        // Remove from auto-reconnect set
        shouldBeConnected.remove(tunnel.id)

        guard let pid = processIDs[tunnel.id] else {
            connectionStatus[tunnel.id] = .disconnected
            return
        }

        // Send SIGTERM first, then SIGKILL after brief delay
        kill(pid, SIGTERM)

        // Give process time to terminate gracefully
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            kill(pid, SIGKILL) // Force kill if still alive
        }

        processIDs.removeValue(forKey: tunnel.id)
        connectionStatus[tunnel.id] = .disconnected
        updatePIDFile()
    }

    func toggle(tunnel: Tunnel) {
        if isConnected(tunnel) {
            disconnect(tunnel: tunnel)
        } else {
            connect(tunnel: tunnel)
        }
    }

    func addTunnel() {
        let newTunnel = Tunnel(
            name: "New Tunnel",
            host: "user@example.com",
            port: 22,
            localPort: 8080,
            remoteHost: "127.0.0.1",
            remotePort: 8080
        )
        tunnels.append(newTunnel)
        Task { await saveTunnels() }
    }

    func deleteTunnel(_ tunnel: Tunnel) {
        if isConnected(tunnel) {
            disconnect(tunnel: tunnel)
        }
        tunnels.removeAll { $0.id == tunnel.id }
        Task { await saveTunnels() }
    }

    func updateTunnel(_ tunnel: Tunnel) {
        if let index = tunnels.firstIndex(where: { $0.id == tunnel.id }) {
            let wasConnected = isConnected(tunnel)
            if wasConnected {
                disconnect(tunnel: tunnels[index])
            }
            tunnels[index] = tunnel
            Task { await saveTunnels() }
        }
    }

    /// Disconnect all tunnels - called on app termination
    func disconnectAll() {
        // Stop reconnection monitor
        reconnectTask?.cancel()
        reconnectTask = nil
        shouldBeConnected.removeAll()

        let pids = Array(processIDs.values)

        // Kill all tracked processes immediately with SIGKILL
        for pid in pids {
            kill(pid, SIGKILL)
        }

        // Also kill by local port pattern as backup (catches any missed processes)
        for tunnel in tunnels {
            findAndKillSSHProcesses(localPort: tunnel.localPort)
        }

        processIDs.removeAll()
        for tunnel in tunnels {
            connectionStatus[tunnel.id] = .disconnected
        }

        // Clean up PID file
        removePIDFile()
    }

    /// Synchronous disconnect for use in signal handlers (non-async context)
    nonisolated func disconnectAllSync() {
        // Read PIDs file directly since we can't access actor state
        if let content = try? String(contentsOf: pidFileURL, encoding: .utf8) {
            let pids = content.components(separatedBy: "\n").compactMap { Int32($0) }
            for pid in pids {
                kill(pid, SIGKILL)
            }
        }
        // Kill process group as ultimate fallback
        killProcessGroup()
        removePIDFile()
    }

    func checkAllStatuses() {
        for (tunnelID, pid) in processIDs {
            let result = kill(pid, 0)
            if result != 0 {
                processIDs.removeValue(forKey: tunnelID)
                if shouldBeConnected.contains(tunnelID) {
                    connectionStatus[tunnelID] = .connecting
                } else {
                    connectionStatus[tunnelID] = .disconnected
                }
            }
        }
        updatePIDFile()
    }
}
