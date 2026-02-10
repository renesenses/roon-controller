import Foundation

// MARK: - Roon Connection Orchestrator

/// Orchestrates the full lifecycle of a connection to Roon Core:
/// SOOD discovery → WebSocket connect → MOO registration → message routing.
/// Handles bidirectional communication (extension sends requests, Core sends requests back).
actor RoonConnection {

    // MARK: - State

    enum ConnectionState: Sendable {
        case disconnected
        case discovering
        case connecting
        case registering
        case connected(coreName: String)
        case failed(String)
    }

    private(set) var state: ConnectionState = .disconnected

    // MARK: - Callbacks (use Data to stay Sendable)

    var onStateChange: (@Sendable (ConnectionState) -> Void)?
    var onZonesData: (@Sendable (Data) -> Void)?
    var onQueueData: (@Sendable (String, Data) -> Void)?

    // MARK: - Components

    private let transport = MOOTransport()
    private let discovery = SOODDiscovery()
    private let requestIds = MOORequestIdGenerator()

    // MARK: - Pending requests (for async request/response)

    private var pendingRequests: [Int: CheckedContinuation<MOOMessage, Error>] = [:]

    // MARK: - Subscriptions

    private var zoneSubscriptionRequestId: Int?
    private var queueSubscriptions: [String: Int] = [:] // zone_id -> requestId

    // MARK: - Core info

    private(set) var coreHost: String?
    private(set) var corePort: Int?
    private(set) var coreName: String?

    // MARK: - Service names (assigned by Core during registration)

    private(set) var transportServiceName: String?
    private(set) var browseServiceName: String?
    private(set) var imageServiceName: String?

    // MARK: - Reconnection

    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private let maxReconnectDelay: Double = 30
    private var shouldReconnect = false

    // MARK: - Connect

    func connect() async {
        shouldReconnect = true
        reconnectAttempt = 0
        updateState(.discovering)
        await startDiscovery()
    }

    func connectDirect(host: String, port: Int = 9330) async {
        shouldReconnect = true
        reconnectAttempt = 0
        coreHost = host
        corePort = port
        await connectToCore(host: host, port: port)
    }

    func disconnect() async {
        shouldReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        await discovery.stop()
        await transport.disconnect()
        pendingRequests.values.forEach { $0.resume(throwing: MOOTransportError.notConnected) }
        pendingRequests.removeAll()
        zoneSubscriptionRequestId = nil
        queueSubscriptions.removeAll()
        updateState(.disconnected)
    }

    // MARK: - Discovery

    private func startDiscovery() async {
        await discovery.stop()

        await discovery.setOnCoreDiscovered { [weak self] core in
            Task { [weak self] in
                guard let self = self else { return }
                let currentState = await self.state
                if case .discovering = currentState {
                    await self.discovery.stop()
                    await self.connectToCore(host: core.host, port: core.port)
                }
            }
        }

        await discovery.start()
    }

    // MARK: - Core Connection

    private func connectToCore(host: String, port: Int) async {
        coreHost = host
        corePort = port
        updateState(.connecting)

        await transport.setOnMessage { [weak self] message in
            Task { [weak self] in
                await self?.handleMessage(message)
            }
        }

        await transport.setOnStateChange { [weak self] transportState in
            Task { [weak self] in
                if case .disconnected = transportState {
                    await self?.handleTransportDisconnect()
                }
            }
        }

        await transport.connect(host: host, port: port)
        await performRegistration()
    }

    // MARK: - Registration Handshake

    private func performRegistration() async {
        updateState(.registering)

        do {
            // Step 1: Send registry:1/info
            let infoBody = try JSONSerialization.data(withJSONObject: RoonRegistration.infoRequestBody())
            let infoResponse = try await sendRequestData(
                name: "com.roonlabs.registry:1/info",
                bodyData: infoBody
            )

            if let body = infoResponse.bodyJSON {
                parseServiceNames(from: body)
            }

            // Step 2: Send registry:1/register
            let registerBody = try JSONSerialization.data(withJSONObject: RoonRegistration.registerRequestBody())
            let registerResponse = try await sendRequestData(
                name: "com.roonlabs.registry:1/register",
                bodyData: registerBody
            )

            let result = RoonRegistration.parseRegistrationResponse(registerResponse.bodyJSON)
            switch result {
            case .registered(let token, let coreId, let name):
                RoonRegistration.saveToken(token, coreId: coreId)
                coreName = name.isEmpty ? "Roon Core" : name
                reconnectAttempt = 0
                updateState(.connected(coreName: coreName ?? "Roon Core"))
                await subscribeZones()

            case .notRegistered:
                break
            }
        } catch {
            updateState(.failed("Registration failed: \(error.localizedDescription)"))
            scheduleReconnect()
        }
    }

    // MARK: - Message Routing

    private func handleMessage(_ message: MOOMessage) {
        switch message.verb {
        case .complete, .continue:
            handleResponse(message)
        case .request:
            handleCoreRequest(message)
        }
    }

    private func handleResponse(_ message: MOOMessage) {
        let requestId = message.requestId

        if message.verb == .continue {
            if requestId == zoneSubscriptionRequestId {
                handleZoneSubscriptionUpdate(message)
                return
            }
            if let zoneId = queueSubscriptions.first(where: { $0.value == requestId })?.key {
                handleQueueSubscriptionUpdate(message, zoneId: zoneId)
                return
            }
            // Could be a delayed registration response (or the initial one as Continue)
            if message.name.contains("register") || message.name == "Registered" {
                let result = RoonRegistration.parseRegistrationResponse(message.bodyJSON)
                if case .registered(let token, let coreId, let name) = result {
                    RoonRegistration.saveToken(token, coreId: coreId)
                    coreName = name.isEmpty ? "Roon Core" : name
                    updateState(.connected(coreName: coreName ?? "Roon Core"))
                    Task { await self.subscribeZones() }
                }
                // Fall through to also resume pending continuation (prevents 30s timeout)
            }
        }

        if let continuation = pendingRequests.removeValue(forKey: requestId) {
            continuation.resume(returning: message)
        }
    }

    private func handleCoreRequest(_ message: MOOMessage) {
        let name = message.name

        if name.hasSuffix("/ping") || name.contains("ping:1") {
            let response = MOOMessage.complete(name: "Success", requestId: message.requestId)
            Task { try? await transport.send(response) }
        } else if name.contains("status:1") || name.hasSuffix("/subscribe_status") {
            let statusBody: [String: Any] = ["message": "Ready", "is_error": false]
            if let jsonData = try? JSONSerialization.data(withJSONObject: statusBody) {
                let response = MOOMessage.complete(name: "Subscribed", requestId: message.requestId, body: jsonData)
                Task { try? await transport.send(response) }
            }
        }
    }

    // MARK: - Zone Subscription

    private func subscribeZones() async {
        let requestId = requestIds.next()
        zoneSubscriptionRequestId = requestId

        let body: [String: Any] = ["subscription_key": "zones"]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return }

        let data = MOOMessage.request(
            name: "\(transportServiceName ?? "com.roonlabs.transport:2")/subscribe_zones",
            requestId: requestId,
            body: bodyData
        )
        try? await transport.send(data)
    }

    private func handleZoneSubscriptionUpdate(_ message: MOOMessage) {
        guard let body = message.body else { return }
        onZonesData?(body)
    }

    // MARK: - Queue Subscription

    func subscribeQueue(zoneId: String) async {
        queueSubscriptions.removeValue(forKey: zoneId)

        let requestId = requestIds.next()
        queueSubscriptions[zoneId] = requestId

        let body: [String: Any] = [
            "subscription_key": "queue_\(zoneId)",
            "max_items": 100
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return }

        let data = MOOMessage.request(
            name: "\(transportServiceName ?? "com.roonlabs.transport:2")/subscribe_queue",
            requestId: requestId,
            body: bodyData
        )
        try? await transport.send(data)
    }

    private func handleQueueSubscriptionUpdate(_ message: MOOMessage, zoneId: String) {
        guard let body = message.body else { return }
        onQueueData?(zoneId, body)
    }

    // MARK: - Public Request API

    /// Send a MOO request with pre-serialized body data and wait for the response.
    func sendRequestData(name: String, bodyData: Data? = nil) async throws -> MOOMessage {
        let requestId = requestIds.next()

        let data: Data
        if let bodyData = bodyData {
            data = MOOMessage.request(name: name, requestId: requestId, body: bodyData)
        } else {
            data = MOOMessage.request(name: name, requestId: requestId)
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestId] = continuation

            Task {
                do {
                    try await transport.send(data)
                } catch {
                    if let cont = pendingRequests.removeValue(forKey: requestId) {
                        cont.resume(throwing: error)
                    }
                }
            }

            Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if let cont = pendingRequests.removeValue(forKey: requestId) {
                    cont.resume(throwing: MOOTransportError.timeout)
                }
            }
        }
    }

    // MARK: - Service Name Helpers

    func transportService() -> String {
        transportServiceName ?? "com.roonlabs.transport:2"
    }

    func browseService() -> String {
        browseServiceName ?? "com.roonlabs.browse:1"
    }

    func imageService() -> String {
        imageServiceName ?? "com.roonlabs.image:1"
    }

    // MARK: - Private Helpers

    private func parseServiceNames(from body: [String: Any]) {
        if let services = body["services"] as? [[String: Any]] {
            for service in services {
                guard let name = service["name"] as? String else { continue }
                if name.contains("transport") {
                    transportServiceName = name
                } else if name.contains("browse") {
                    browseServiceName = name
                } else if name.contains("image") {
                    imageServiceName = name
                }
            }
        }
    }

    private func handleTransportDisconnect() {
        pendingRequests.values.forEach { $0.resume(throwing: MOOTransportError.notConnected) }
        pendingRequests.removeAll()
        zoneSubscriptionRequestId = nil
        queueSubscriptions.removeAll()

        updateState(.disconnected)

        if shouldReconnect {
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard shouldReconnect else { return }
        reconnectTask?.cancel()

        let delay = min(pow(2.0, Double(reconnectAttempt)), maxReconnectDelay)
        reconnectAttempt += 1

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            guard let self = self else { return }
            let host = await self.coreHost
            let port = await self.corePort

            if let host = host, let port = port {
                await self.connectToCore(host: host, port: port)
            } else {
                await self.connect()
            }
        }
    }

    private func updateState(_ newState: ConnectionState) {
        state = newState
        onStateChange?(newState)
    }
}

// MARK: - Actor helper extensions

extension RoonConnection {
    func setOnStateChange(_ handler: @escaping @Sendable (ConnectionState) -> Void) {
        onStateChange = handler
    }
    func setOnZonesData(_ handler: @escaping @Sendable (Data) -> Void) {
        onZonesData = handler
    }
    func setOnQueueData(_ handler: @escaping @Sendable (String, Data) -> Void) {
        onQueueData = handler
    }
}

extension SOODDiscovery {
    func setOnCoreDiscovered(_ handler: @escaping @Sendable (DiscoveredCore) -> Void) {
        onCoreDiscovered = handler
    }
}

extension MOOTransport {
    func setOnMessage(_ handler: @escaping @Sendable (MOOMessage) -> Void) {
        onMessage = handler
    }
    func setOnStateChange(_ handler: @escaping @Sendable (State) -> Void) {
        onStateChange = handler
    }
}
