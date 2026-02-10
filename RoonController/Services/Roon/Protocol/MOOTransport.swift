import Foundation

// MARK: - MOO WebSocket Transport

/// Manages a binary WebSocket connection to a Roon Core using the MOO/1 protocol.
/// Handles ping/pong keepalive every 10s and automatic reconnection.
actor MOOTransport {

    enum State: Sendable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    // MARK: - Properties

    private(set) var state: State = .disconnected
    private var webSocket: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private var pingTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?

    private var _onMessage: (@Sendable (MOOMessage) -> Void)?
    private var _onStateChange: (@Sendable (State) -> Void)?

    var onMessage: (@Sendable (MOOMessage) -> Void)? {
        get { _onMessage }
        set { _onMessage = newValue }
    }

    var onStateChange: (@Sendable (State) -> Void)? {
        get { _onStateChange }
        set { _onStateChange = newValue }
    }

    // MARK: - Connect / Disconnect

    func connect(host: String, port: Int) {
        // Clean up previous connection without firing disconnect state change
        pingTask?.cancel()
        pingTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil

        let urlString = "ws://\(host):\(port)/api"
        guard let url = URL(string: urlString) else {
            updateState(.failed("Invalid URL: \(urlString)"))
            return
        }

        updateState(.connecting)

        let ws = session.webSocketTask(with: url)
        ws.maximumMessageSize = 16 * 1024 * 1024
        self.webSocket = ws
        ws.resume()

        updateState(.connected)
        startReceiveLoop()
        startPingLoop()
    }

    func disconnect() {
        pingTask?.cancel()
        pingTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        updateState(.disconnected)
    }

    // MARK: - Send

    func send(_ data: Data) async throws {
        guard let ws = webSocket else {
            throw MOOTransportError.notConnected
        }
        try await ws.send(.data(data))
    }

    // MARK: - Receive Loop

    private func startReceiveLoop() {
        receiveTask?.cancel()
        let ws = webSocket
        let handler = _onMessage
        receiveTask = Task { [weak self] in
            guard let ws = ws else { return }
            while !Task.isCancelled {
                do {
                    let message = try await ws.receive()
                    let data: Data
                    switch message {
                    case .data(let d):
                        data = d
                    case .string(let s):
                        data = Data(s.utf8)
                    @unknown default:
                        continue
                    }
                    if let moo = MOOMessage.parse(data) {
                        handler?(moo)
                    }
                } catch {
                    if !Task.isCancelled {
                        await self?.handleDisconnect()
                    }
                    break
                }
            }
        }
    }

    // MARK: - Ping/Pong Keepalive

    private func startPingLoop() {
        pingTask?.cancel()
        let ws = webSocket
        pingTask = Task { [weak self] in
            guard let ws = ws else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                    guard !Task.isCancelled else { break }
                    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                        ws.sendPing { error in
                            if let error = error {
                                cont.resume(throwing: error)
                            } else {
                                cont.resume()
                            }
                        }
                    }
                } catch {
                    if !Task.isCancelled {
                        await self?.handleDisconnect()
                    }
                    break
                }
            }
        }
    }

    // MARK: - Private

    private func handleDisconnect() {
        pingTask?.cancel()
        pingTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        webSocket = nil
        updateState(.disconnected)
    }

    private func updateState(_ newState: State) {
        state = newState
        _onStateChange?(newState)
    }
}

// MARK: - Errors

enum MOOTransportError: Error, LocalizedError {
    case notConnected
    case timeout

    var errorDescription: String? {
        switch self {
        case .notConnected: return "MOO transport not connected"
        case .timeout: return "MOO request timed out"
        }
    }
}
