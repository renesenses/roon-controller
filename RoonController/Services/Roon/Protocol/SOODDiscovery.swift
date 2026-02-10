import Foundation

// MARK: - SOOD Discovery Protocol

/// Discovers Roon Core instances on the local network using the SOOD protocol.
/// SOOD uses UDP multicast on 239.255.90.90:9003 with a proprietary binary format:
/// `"SOOD" + 0x02 + 'Q'/'R' + properties`
///
/// Uses POSIX (BSD) sockets instead of Network.framework to avoid the
/// `com.apple.developer.networking.multicast` entitlement requirement.
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

    private var sendFd: Int32 = -1
    private var recvFd: Int32 = -1
    private var receiveTask: Task<Void, Never>?
    private var sendReceiveTask: Task<Void, Never>?
    private var queryTask: Task<Void, Never>?
    private var discoveredCores: [String: DiscoveredCore] = [:]

    var onCoreDiscovered: ((DiscoveredCore) -> Void)?

    // MARK: - Start / Stop

    func start() {
        stop()
        setupSockets()
        startReceiveLoops()
        startQueryLoop()
    }

    func stop() {
        queryTask?.cancel()
        queryTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        sendReceiveTask?.cancel()
        sendReceiveTask = nil

        if sendFd >= 0 { Darwin.close(sendFd); sendFd = -1 }
        if recvFd >= 0 { Darwin.close(recvFd); recvFd = -1 }
        discoveredCores.removeAll()
    }

    func getDiscoveredCores() -> [DiscoveredCore] {
        Array(discoveredCores.values)
    }

    // MARK: - Socket Setup

    private func setupSockets() {
        // --- Send socket ---
        sendFd = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        guard sendFd >= 0 else { return }

        var yes: Int32 = 1
        Darwin.setsockopt(sendFd, SOL_SOCKET, SO_BROADCAST,
                          &yes, socklen_t(MemoryLayout<Int32>.size))

        var ttl: UInt8 = 1
        Darwin.setsockopt(sendFd, IPPROTO_IP, IP_MULTICAST_TTL,
                          &ttl, socklen_t(MemoryLayout<UInt8>.size))

        // --- Receive socket ---
        recvFd = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        guard recvFd >= 0 else {
            Darwin.close(sendFd); sendFd = -1
            return
        }

        Darwin.setsockopt(recvFd, SOL_SOCKET, SO_REUSEADDR,
                          &yes, socklen_t(MemoryLayout<Int32>.size))
        Darwin.setsockopt(recvFd, SOL_SOCKET, SO_REUSEPORT,
                          &yes, socklen_t(MemoryLayout<Int32>.size))

        var bindAddr = sockaddr_in()
        bindAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        bindAddr.sin_family = sa_family_t(AF_INET)
        bindAddr.sin_port = Self.soodPort.bigEndian
        bindAddr.sin_addr.s_addr = INADDR_ANY

        let rc = withUnsafePointer(to: &bindAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(recvFd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if rc < 0 {
            Darwin.close(recvFd); recvFd = -1
            return
        }

        joinMulticastOnAllInterfaces()
    }

    /// Join the SOOD multicast group on every IPv4 interface.
    private func joinMulticastOnAllInterfaces() {
        guard recvFd >= 0 else { return }
        for iface in getNetworkInterfaces() {
            var mreq = ip_mreq()
            mreq.imr_multiaddr.s_addr = inet_addr(Self.multicastGroup)
            mreq.imr_interface.s_addr = inet_addr(iface.address)
            Darwin.setsockopt(recvFd, IPPROTO_IP, IP_ADD_MEMBERSHIP,
                              &mreq, socklen_t(MemoryLayout<ip_mreq>.size))
            // Errors (e.g. already joined) are intentionally ignored.
        }
    }

    // MARK: - Receive Loops

    private func startReceiveLoops() {
        // Listen on the multicast/receive socket (port 9003)
        receiveTask = makeRecvTask(fd: recvFd)
        // Also listen on the send socket (ephemeral port) for unicast replies
        sendReceiveTask = makeRecvTask(fd: sendFd)
    }

    /// Spawn a detached task that loops on `recvfrom` for the given socket fd.
    private func makeRecvTask(fd: Int32) -> Task<Void, Never>? {
        guard fd >= 0 else { return nil }

        return Task.detached { [weak self] in
            var buf = [UInt8](repeating: 0, count: 65536)
            while !Task.isCancelled {
                var sender = sockaddr_in()
                var senderLen = socklen_t(MemoryLayout<sockaddr_in>.size)

                let n = buf.withUnsafeMutableBufferPointer { bufPtr in
                    withUnsafeMutablePointer(to: &sender) { addrPtr in
                        addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                            Darwin.recvfrom(fd, bufPtr.baseAddress, bufPtr.count,
                                            0, sa, &senderLen)
                        }
                    }
                }
                guard n > 0 else { break } // socket closed or error

                let data = Data(buf[0..<n])
                var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var addr = sender.sin_addr
                inet_ntop(AF_INET, &addr, &ipBuf, socklen_t(INET_ADDRSTRLEN))
                let senderIP = String(cString: ipBuf)

                await self?.handleSOODMessage(data, senderIP: senderIP)
            }
        }
    }

    // MARK: - Query Loop

    private func startQueryLoop() {
        queryTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sendQuery()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func sendQuery() {
        guard sendFd >= 0 else { return }

        // Refresh multicast memberships in case new interfaces appeared.
        joinMulticastOnAllInterfaces()

        let packet = buildQueryPacket()

        // Send to multicast group
        sendPacket(packet, toIP: Self.multicastGroup, port: Self.soodPort)

        // Send to broadcast address on each interface
        for iface in getNetworkInterfaces() {
            let dst = iface.broadcast ?? "255.255.255.255"
            sendPacket(packet, toIP: dst, port: Self.soodPort)
        }
    }

    private func sendPacket(_ packet: Data, toIP ip: String, port: UInt16) {
        var dst = sockaddr_in()
        dst.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        dst.sin_family = sa_family_t(AF_INET)
        dst.sin_port = port.bigEndian
        dst.sin_addr.s_addr = inet_addr(ip)

        packet.withUnsafeBytes { buf in
            withUnsafePointer(to: &dst) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    _ = Darwin.sendto(sendFd, buf.baseAddress, buf.count, 0,
                                      sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    // MARK: - Packet Building

    private func buildQueryPacket() -> Data {
        var data = Data()
        data.append(Self.magic)
        data.append(Self.version)
        data.append(Self.typeQuery)
        appendProperty(&data, key: "_tid", value: UUID().uuidString)
        appendProperty(&data, key: "query_service_id",
                       value: "00720724-5143-4a9b-abac-0e50cba674bb")
        return data
    }

    /// Append a SOOD property: `key_len(1B) + key + value_len(2B BE) + value`
    private func appendProperty(_ data: inout Data, key: String, value: String) {
        let keyBytes = Data(key.utf8)
        let valBytes = Data(value.utf8)

        // Key length (1 byte)
        data.append(UInt8(keyBytes.count))
        data.append(keyBytes)

        // Value length (big-endian 16-bit)
        var vlen = UInt16(valBytes.count).bigEndian
        data.append(Data(bytes: &vlen, count: 2))
        data.append(valBytes)
    }

    // MARK: - Packet Parsing

    private func handleSOODMessage(_ data: Data, senderIP: String) {
        guard data.count >= 6,
              data[0..<4] == Self.magic,
              data[4] == Self.version,
              data[5] == Self.typeReply else { return }

        let props = parseProperties(data, from: 6)

        guard let serviceId = props["service_id"],
              let httpPort = props["http_port"],
              let port = Int(httpPort) else { return }

        let host = props["_replyaddr"] ?? senderIP
        let displayName = props["display_name"] ?? props["name"] ?? serviceId

        let core = DiscoveredCore(
            coreId: serviceId,
            displayName: displayName,
            host: host,
            port: port
        )

        if discoveredCores[serviceId] != core {
            discoveredCores[serviceId] = core
            onCoreDiscovered?(core)
        }
    }

    /// Parse SOOD properties: `key_len(1B) + key + value_len(2B BE) + value`
    private func parseProperties(_ data: Data, from offset: Int) -> [String: String] {
        var props: [String: String] = [:]
        var pos = offset

        while pos < data.count {
            let keyLen = Int(data[pos])
            pos += 1
            guard keyLen > 0, pos + keyLen <= data.count else { break }

            let key = String(data: data[pos..<(pos + keyLen)], encoding: .utf8) ?? ""
            pos += keyLen

            guard pos + 2 <= data.count else { break }
            let valLen = Int(data[pos]) << 8 | Int(data[pos + 1])
            pos += 2

            if valLen == 0xFFFF { continue }        // null sentinel
            if valLen == 0 { props[key] = ""; continue }

            guard pos + valLen <= data.count else { break }
            props[key] = String(data: data[pos..<(pos + valLen)], encoding: .utf8) ?? ""
            pos += valLen
        }
        return props
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

                    interfaces.append(NetworkInterface(
                        name: name, address: address, broadcast: broadcastStr))
                }
            }

            guard let next = iface.ifa_next else { break }
            ptr = next
        }

        return interfaces
    }
}
