import Foundation
import Network

// MARK: - SOOD Discovery Protocol

/// Discovers Roon Core instances on the local network using the SOOD protocol.
/// SOOD uses UDP multicast on 239.255.90.90:9003 with a proprietary binary format:
/// `"SOOD" + 0x02 + 'Q'/'R' + properties`
actor SOODDiscovery {

    struct DiscoveredCore: Sendable, Equatable {
        let coreId: String
        let displayName: String
        let host: String
        let port: Int
    }

    // MARK: - Constants

    private static let multicastGroup = "239.255.90.90"
    private static let soodPort: UInt16 = 9003
    private static let magic = Data([0x53, 0x4F, 0x4F, 0x44]) // "SOOD"
    private static let version: UInt8 = 0x02
    private static let typeQuery: UInt8 = 0x51 // 'Q'
    private static let typeReply: UInt8 = 0x52 // 'R'

    // MARK: - Properties

    private var connection: NWConnection?
    private var listener: NWListener?
    private var receiveTask: Task<Void, Never>?
    private var queryTask: Task<Void, Never>?
    private var discoveredCores: [String: DiscoveredCore] = [:]

    var onCoreDiscovered: ((DiscoveredCore) -> Void)?

    // MARK: - Start / Stop

    func start() {
        stop()
        startListening()
        startQueryLoop()
    }

    func stop() {
        queryTask?.cancel()
        queryTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        listener?.cancel()
        listener = nil
        connection?.cancel()
        connection = nil
        discoveredCores.removeAll()
    }

    func getDiscoveredCores() -> [DiscoveredCore] {
        Array(discoveredCores.values)
    }

    // MARK: - Listening for SOOD replies

    private func startListening() {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        params.requiredInterfaceType = .other

        do {
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: 0)!)
            self.listener = listener

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    break
                case .failed:
                    Task { [weak self] in await self?.restartListening() }
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .global(qos: .utility))
                Task { await self?.receiveSOODData(on: connection) }
            }

            listener.start(queue: .global(qos: .utility))
        } catch {
            // Listener failed to start
        }
    }

    private func restartListening() {
        listener?.cancel()
        listener = nil
        startListening()
    }

    private nonisolated func receiveSOODData(on connection: NWConnection) async {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let data = data, error == nil else { return }
            Task { await self?.handleSOODReply(data, from: connection) }
        }
    }

    // MARK: - Sending SOOD queries

    private func startQueryLoop() {
        queryTask?.cancel()
        queryTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sendQuery()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000) // 5s between queries
                } catch {
                    break
                }
            }
        }
    }

    private func sendQuery() {
        let queryPacket = buildQueryPacket()

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        let host = NWEndpoint.Host(Self.multicastGroup)
        let port = NWEndpoint.Port(rawValue: Self.soodPort)!
        let endpoint = NWEndpoint.hostPort(host: host, port: port)
        let connection = NWConnection(to: endpoint, using: params)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: queryPacket, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            case .failed, .cancelled:
                break
            default:
                break
            }
        }

        connection.start(queue: .global(qos: .utility))

        // Also send via direct UDP to common ports for discovery
        sendDirectQuery(queryPacket)
    }

    private func sendDirectQuery(_ packet: Data) {
        // Roon Core listens on port 9003 for SOOD queries
        // Send on all available network interfaces
        let interfaces = getNetworkInterfaces()
        for iface in interfaces {
            let broadcastAddr = iface.broadcast ?? "255.255.255.255"
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true

            let host = NWEndpoint.Host(broadcastAddr)
            let port = NWEndpoint.Port(rawValue: Self.soodPort)!
            let conn = NWConnection(to: .hostPort(host: host, port: port), using: params)

            conn.stateUpdateHandler = { state in
                if state == .ready {
                    conn.send(content: packet, completion: .contentProcessed { _ in
                        conn.cancel()
                    })
                }
            }
            conn.start(queue: .global(qos: .utility))
        }
    }

    // MARK: - Packet Building

    private func buildQueryPacket() -> Data {
        var data = Data()
        data.append(Self.magic)
        data.append(Self.version)
        data.append(Self.typeQuery)

        // Add query_service_id property for Roon
        let queryServiceId = "00720724-5143-4a9b-abac-0e50cba674bb"
        appendProperty(&data, key: "_tid", value: UUID().uuidString)
        appendProperty(&data, key: "query_service_id", value: queryServiceId)

        return data
    }

    /// Append a SOOD property: `type(1) + key_len(2 BE) + key + value_len(2 BE) + value`
    private func appendProperty(_ data: inout Data, key: String, value: String) {
        let keyData = Data(key.utf8)
        let valueData = Data(value.utf8)

        // Type byte: 0x01 for UTF-8 string
        data.append(0x01)

        // Key length (big-endian 16-bit)
        var keyLen = UInt16(keyData.count).bigEndian
        data.append(Data(bytes: &keyLen, count: 2))
        data.append(keyData)

        // Value length (big-endian 16-bit)
        var valueLen = UInt16(valueData.count).bigEndian
        data.append(Data(bytes: &valueLen, count: 2))
        data.append(valueData)
    }

    // MARK: - Packet Parsing

    private func handleSOODReply(_ data: Data, from connection: NWConnection) {
        guard data.count >= 6 else { return }

        // Verify magic
        guard data[data.startIndex..<data.startIndex + 4] == Self.magic else { return }
        guard data[data.startIndex + 4] == Self.version else { return }
        guard data[data.startIndex + 5] == Self.typeReply else { return }

        // Parse properties
        let properties = parseProperties(data, from: data.startIndex + 6)

        guard let serviceId = properties["service_id"],
              let httpPort = properties["http_port"],
              let port = Int(httpPort) else { return }

        // Get host from the connection's remote endpoint
        let host: String
        if let name = properties["name"] {
            // Try to get host from properties first
            host = properties["host"] ?? extractHost(from: connection) ?? name
        } else {
            host = extractHost(from: connection) ?? "unknown"
        }

        let displayName = properties["display_name"] ?? properties["name"] ?? serviceId

        let core = DiscoveredCore(
            coreId: serviceId,
            displayName: displayName,
            host: host,
            port: port
        )

        if discoveredCores[serviceId] == nil || discoveredCores[serviceId] != core {
            discoveredCores[serviceId] = core
            onCoreDiscovered?(core)
        }
    }

    /// Parse SOOD properties from binary data.
    private func parseProperties(_ data: Data, from offset: Data.Index) -> [String: String] {
        var properties: [String: String] = [:]
        var pos = offset

        while pos < data.endIndex {
            guard pos + 1 <= data.endIndex else { break }
            let type = data[pos]
            pos = data.index(after: pos)

            guard type == 0x01 else { break } // Only handle UTF-8 string type

            // Key length (big-endian 16-bit)
            guard pos + 2 <= data.endIndex else { break }
            let keyLen = Int(UInt16(data[pos]) << 8 | UInt16(data[data.index(after: pos)]))
            pos = data.index(pos, offsetBy: 2)

            guard pos + keyLen <= data.endIndex else { break }
            let key = String(data: data[pos..<data.index(pos, offsetBy: keyLen)], encoding: .utf8) ?? ""
            pos = data.index(pos, offsetBy: keyLen)

            // Value length (big-endian 16-bit)
            guard pos + 2 <= data.endIndex else { break }
            let valueLen = Int(UInt16(data[pos]) << 8 | UInt16(data[data.index(after: pos)]))
            pos = data.index(pos, offsetBy: 2)

            guard pos + valueLen <= data.endIndex else { break }
            let value = String(data: data[pos..<data.index(pos, offsetBy: valueLen)], encoding: .utf8) ?? ""
            pos = data.index(pos, offsetBy: valueLen)

            properties[key] = value
        }

        return properties
    }

    private nonisolated func extractHost(from connection: NWConnection) -> String? {
        if case .hostPort(let host, _) = connection.currentPath?.remoteEndpoint {
            switch host {
            case .ipv4(let addr):
                return "\(addr)"
            case .ipv6(let addr):
                return "\(addr)"
            case .name(let name, _):
                return name
            @unknown default:
                return nil
            }
        }
        return nil
    }

    // MARK: - Network Interfaces

    private struct NetworkInterface {
        let name: String
        let address: String
        let broadcast: String?
    }

    private nonisolated func getNetworkInterfaces() -> [NetworkInterface] {
        var interfaces: [NetworkInterface] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return interfaces }
        defer { freeifaddrs(firstAddr) }

        var ptr = firstAddr
        while true {
            let iface = ptr.pointee
            let family = iface.ifa_addr.pointee.sa_family

            if family == UInt8(AF_INET) { // IPv4 only
                let name = String(cString: iface.ifa_name)
                // Skip loopback
                if name != "lo0" {
                    var addr = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    var sockAddr = iface.ifa_addr.pointee
                    withUnsafePointer(to: &sockAddr) { sockPtr in
                        sockPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { inPtr in
                            var inAddr = inPtr.pointee.sin_addr
                            inet_ntop(AF_INET, &inAddr, &addr, socklen_t(INET_ADDRSTRLEN))
                        }
                    }
                    let address = String(cString: addr)

                    var broadcastStr: String?
                    if let broadcastAddr = iface.ifa_dstaddr {
                        var bcast = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        var bSockAddr = broadcastAddr.pointee
                        withUnsafePointer(to: &bSockAddr) { sockPtr in
                            sockPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { inPtr in
                                var inAddr = inPtr.pointee.sin_addr
                                inet_ntop(AF_INET, &inAddr, &bcast, socklen_t(INET_ADDRSTRLEN))
                            }
                        }
                        broadcastStr = String(cString: bcast)
                    }

                    interfaces.append(NetworkInterface(name: name, address: address, broadcast: broadcastStr))
                }
            }

            guard let next = iface.ifa_next else { break }
            ptr = next
        }

        return interfaces
    }
}
