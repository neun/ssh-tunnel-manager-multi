import Foundation

struct Tunnel: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var host: String           // user@server.com or SSH config alias
    var port: Int              // SSH port (default 22)
    var localHost: String      // Local bind address (default 127.0.0.1)
    var localPort: Int         // Local port to forward
    var remoteHost: String     // Remote host (usually 127.0.0.1)
    var remotePort: Int        // Remote port
    var identityFile: String?  // Path to identity file (~/.ssh/id_rsa)
    var autoConnect: Bool      // Connect on app launch
    var useAlias: Bool         // Use host as SSH config alias (no -i, no -p unless non-22)

    init(
        id: UUID = UUID(),
        name: String = "",
        host: String = "",
        port: Int = 22,
        localHost: String = "127.0.0.1",
        localPort: Int = 8080,
        remoteHost: String = "127.0.0.1",
        remotePort: Int = 8080,
        identityFile: String? = nil,
        autoConnect: Bool = false,
        useAlias: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.localHost = localHost
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.identityFile = identityFile
        self.autoConnect = autoConnect
        self.useAlias = useAlias
    }

    // Codable conformance - exclude runtime properties
    enum CodingKeys: String, CodingKey {
        case id, name, host, port, localHost, localPort, remoteHost, remotePort, identityFile, autoConnect, useAlias
    }

    // Custom decoder to handle old configs without useAlias field
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        localHost = try container.decode(String.self, forKey: .localHost)
        localPort = try container.decode(Int.self, forKey: .localPort)
        remoteHost = try container.decode(String.self, forKey: .remoteHost)
        remotePort = try container.decode(Int.self, forKey: .remotePort)
        identityFile = try container.decodeIfPresent(String.self, forKey: .identityFile)
        autoConnect = try container.decode(Bool.self, forKey: .autoConnect)
        // Default to false for old configs without this field
        useAlias = try container.decodeIfPresent(Bool.self, forKey: .useAlias) ?? false
    }
}
