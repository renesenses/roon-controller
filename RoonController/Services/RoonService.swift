import Foundation
import Combine

private func debugLog(_ message: String) {
    let line = "[\(Date())] \(message)\n"
    NSLog("%@", message)
    if let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
        let path = dir.appendingPathComponent("roon_debug.log").path
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: path) {
                if let fh = FileHandle(forWritingAtPath: path) {
                    fh.seekToEndOfFile()
                    fh.write(data)
                    fh.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: path, contents: data)
            }
        }
    }
}

@MainActor
class RoonService: ObservableObject {

    // MARK: - Published State

    @Published var connectionState: RoonState = .disconnected
    @Published var zones: [RoonZone] = []
    @Published var currentZone: RoonZone?
    @Published var browseResult: BrowseResult?
    @Published var browseStack: [String] = []
    @Published var queueItems: [QueueItem] = []
    @Published var playbackHistory: [PlaybackHistoryItem] = []
    @Published var lastError: String?

    // MARK: - Configuration

    var backendHost: String = "localhost"
    var backendPort: Int = 3333

    // MARK: - Private

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession = .shared
    private var lastTrackPerZone: [String: String] = [:]  // zone_id -> track title
    private var isConnected = false
    private var reconnectAttempt = 0
    private let maxReconnectDelay: Double = 30
    private var reconnectTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?

    // MARK: - Connection

    func connect() {
        guard webSocketTask == nil else { return }
        connectionState = .connecting
        if playbackHistory.isEmpty { loadHistory() }

        let urlString = "ws://\(backendHost):\(backendPort)"
        guard let url = URL(string: urlString) else {
            lastError = "Invalid WebSocket URL"
            connectionState = .disconnected
            return
        }

        webSocketTask = urlSession.webSocketTask(with: url)
        webSocketTask?.resume()
        isConnected = true
        reconnectAttempt = 0
        startReceiveLoop()
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        isConnected = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
    }

    // MARK: - Receive Loop (async)

    private func startReceiveLoop() {
        receiveTask?.cancel()
        let ws = webSocketTask
        receiveTask = Task.detached { [weak self] in
            guard let ws = ws else { return }
            while !Task.isCancelled {
                do {
                    let message = try await ws.receive()
                    let text: String?
                    switch message {
                    case .string(let s):
                        text = s
                    case .data(let d):
                        text = String(data: d, encoding: .utf8)
                    @unknown default:
                        text = nil
                    }
                    if let text = text {
                        await self?.handleMessage(text)
                    }
                } catch {
                    await self?.handleDisconnect()
                    break
                }
            }
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        let decoder = JSONDecoder()

        guard let base = try? decoder.decode(WSMessage.self, from: data) else {
            print("[WS] Failed to decode base message: \(text.prefix(200))")
            return
        }
        debugLog("[WS] Received: \(base.type)")

        switch base.type {
        case "state":
            if let msg = try? decoder.decode(WSStateMessage.self, from: data) {
                connectionState = RoonState(rawValue: msg.state) ?? .disconnected
            }

        case "zones", "zones_changed":
            if let msg = try? decoder.decode(WSZonesMessage.self, from: data) {
                let newZones = msg.zones
                // Track now_playing changes for history
                for zone in newZones {
                    trackPlaybackHistory(zone: zone)
                }
                // Only update if zones actually changed
                if newZones != zones {
                    zones = newZones
                }
                // Update currentZone if it still exists
                if let current = currentZone {
                    let updated = zones.first(where: { $0.zone_id == current.zone_id })
                    if updated != currentZone {
                        currentZone = updated
                    }
                }
                // Auto-select first zone if none selected
                if currentZone == nil, let first = zones.first {
                    currentZone = first
                }
            }

        case "browse_result":
            do {
                let msg = try decoder.decode(WSBrowseResultMessage.self, from: data)
                let newItems = msg.items ?? []
                let offset = msg.offset ?? 0

                if offset > 0, var existing = browseResult {
                    // Pagination: append items
                    existing.items.append(contentsOf: newItems)
                    existing.offset = offset
                    browseResult = existing
                    debugLog("[Browse] Appended \(newItems.count) items at offset \(offset), total: \(existing.items.count)")
                } else {
                    // New browse result
                    browseResult = BrowseResult(
                        action: msg.action,
                        list: msg.list,
                        items: newItems,
                        offset: 0
                    )
                    debugLog("[Browse] Got \(newItems.count) items, list: \(msg.list?.title ?? "nil"), level: \(msg.list?.level ?? -1), total: \(msg.list?.count ?? 0)")
                    if let title = msg.list?.title {
                        if let level = msg.list?.level, level > 0 {
                            while browseStack.count >= level {
                                browseStack.removeLast()
                            }
                            browseStack.append(title)
                        } else {
                            browseStack = [title]
                        }
                    }
                }
            } catch {
                debugLog("[Browse] Decode error: \(error)")
            }

        case "queue":
            if let msg = try? decoder.decode(WSQueueMessage.self, from: data) {
                if msg.zone_id == currentZone?.zone_id {
                    queueItems = msg.items
                }
            }

        case "error":
            if let msg = try? decoder.decode(WSErrorMessage.self, from: data) {
                lastError = msg.message
                print("[WS] Error from backend: \(msg.message)")
            }

        default:
            break
        }
    }

    // MARK: - Reconnection

    private func handleDisconnect() {
        webSocketTask = nil
        receiveTask = nil
        if isConnected {
            connectionState = .disconnected
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard isConnected else { return }
        reconnectTask?.cancel()

        let delay = min(pow(2.0, Double(reconnectAttempt)), maxReconnectDelay)
        reconnectAttempt += 1

        print("[WS] Reconnecting in \(delay)s (attempt \(reconnectAttempt))...")

        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, self.isConnected else { return }
            self.webSocketTask = nil
            self.connect()
        }
    }

    // MARK: - Transport Controls

    func play() {
        guard let zoneId = currentZone?.zone_id else { return }
        send(["type": "transport/control", "zone_id": zoneId, "control": "play"])
    }

    func pause() {
        guard let zoneId = currentZone?.zone_id else { return }
        send(["type": "transport/control", "zone_id": zoneId, "control": "pause"])
    }

    func playPause() {
        guard let zoneId = currentZone?.zone_id else { return }
        send(["type": "transport/control", "zone_id": zoneId, "control": "playpause"])
    }

    func stop() {
        guard let zoneId = currentZone?.zone_id else { return }
        send(["type": "transport/control", "zone_id": zoneId, "control": "stop"])
    }

    func next() {
        guard let zoneId = currentZone?.zone_id else { return }
        send(["type": "transport/control", "zone_id": zoneId, "control": "next"])
    }

    func previous() {
        guard let zoneId = currentZone?.zone_id else { return }
        send(["type": "transport/control", "zone_id": zoneId, "control": "previous"])
    }

    // MARK: - Seek

    func seek(position: Int) {
        guard let zoneId = currentZone?.zone_id else { return }
        send(["type": "transport/seek", "zone_id": zoneId, "how": "absolute", "seconds": position])
    }

    func seekRelative(seconds: Int) {
        guard let zoneId = currentZone?.zone_id else { return }
        send(["type": "transport/seek", "zone_id": zoneId, "how": "relative", "seconds": seconds])
    }

    // MARK: - Volume

    func setVolume(outputId: String, value: Double) {
        send(["type": "transport/volume", "output_id": outputId, "value": value, "how": "absolute"])
    }

    func mute(outputId: String) {
        send(["type": "transport/mute", "output_id": outputId, "how": "mute"])
    }

    func unmute(outputId: String) {
        send(["type": "transport/mute", "output_id": outputId, "how": "unmute"])
    }

    func toggleMute(outputId: String) {
        send(["type": "transport/mute", "output_id": outputId, "how": "toggle"])
    }

    // MARK: - Settings

    func setShuffle(_ enabled: Bool) {
        guard let zoneId = currentZone?.zone_id else { return }
        send(["type": "transport/settings", "zone_id": zoneId, "shuffle": enabled])
    }

    func setLoop(_ mode: String) {
        guard let zoneId = currentZone?.zone_id else { return }
        send(["type": "transport/settings", "zone_id": zoneId, "loop": mode])
    }

    func setAutoRadio(_ enabled: Bool) {
        guard let zoneId = currentZone?.zone_id else { return }
        send(["type": "transport/settings", "zone_id": zoneId, "auto_radio": enabled])
    }

    // MARK: - Zone Selection

    func selectZone(_ zone: RoonZone) {
        currentZone = zone
        queueItems = []
        subscribeQueue()
    }

    // MARK: - Queue

    func subscribeQueue() {
        guard let zoneId = currentZone?.zone_id else { return }
        send(["type": "transport/subscribe_queue", "zone_id": zoneId])
    }

    func playFromHere(queueItemId: Int) {
        guard let zoneId = currentZone?.zone_id else { return }
        send(["type": "transport/play_from_here", "zone_id": zoneId, "queue_item_id": queueItemId])
    }

    // MARK: - Browse

    private var pendingBrowseKey: String?

    func browse(hierarchy: String = "browse", itemKey: String? = nil, input: String? = nil, popLevels: Int? = nil, popAll: Bool = false) {
        // Prevent duplicate browse requests for the same item_key
        let browseKey = itemKey ?? "__root__"
        debugLog("[Browse] browse() called: itemKey=\(itemKey ?? "nil"), pendingBrowseKey=\(pendingBrowseKey ?? "nil")")
        if itemKey != nil && browseKey == pendingBrowseKey {
            debugLog("[Browse] BLOCKED by pendingBrowseKey guard")
            return
        }
        pendingBrowseKey = browseKey

        var msg: [String: Any] = ["type": "browse/browse", "hierarchy": hierarchy]
        if let zoneId = currentZone?.zone_id {
            msg["zone_id"] = zoneId
        }
        if let itemKey = itemKey { msg["item_key"] = itemKey }
        if let input = input { msg["input"] = input }
        if let popLevels = popLevels { msg["pop_levels"] = popLevels }
        if popAll { msg["pop_all"] = true }
        send(msg)
    }

    func browseLoad(hierarchy: String = "browse", offset: Int = 0, count: Int = 100) {
        send(["type": "browse/load", "hierarchy": hierarchy, "offset": offset, "count": count])
    }

    func browseBack() {
        pendingBrowseKey = nil
        browse(popLevels: 1)
        if !browseStack.isEmpty {
            browseStack.removeLast()
        }
    }

    func browseHome() {
        pendingBrowseKey = nil
        browseStack.removeAll()
        browseResult = nil
        browse(popAll: true)
    }

    // MARK: - Core Connection

    func connectCore(ip: String) {
        send(["type": "core/connect", "ip": ip])
    }

    // MARK: - Image URL

    func imageURL(key: String?, width: Int = 300, height: Int = 300) -> URL? {
        guard let key = key else { return nil }
        return URL(string: "http://\(backendHost):\(backendPort)/api/image/\(key)?scale=fit&width=\(width)&height=\(height)")
    }

    // MARK: - Playback History

    private func trackPlaybackHistory(zone: RoonZone) {
        guard zone.state == "playing",
              let np = zone.now_playing,
              let title = np.three_line?.line1 ?? np.one_line?.line1,
              !title.isEmpty else { return }

        let trackKey = "\(zone.zone_id):\(title)"
        if lastTrackPerZone[zone.zone_id] == trackKey { return }
        lastTrackPerZone[zone.zone_id] = trackKey

        let item = PlaybackHistoryItem(
            id: UUID(),
            title: title,
            artist: np.three_line?.line2 ?? np.two_line?.line1 ?? "",
            album: np.three_line?.line3 ?? "",
            image_key: np.image_key,
            length: np.length,
            zone_name: zone.display_name,
            playedAt: Date()
        )
        playbackHistory.insert(item, at: 0)
        // Keep last 500 items
        if playbackHistory.count > 500 {
            playbackHistory = Array(playbackHistory.prefix(500))
        }
        saveHistory()
    }

    func loadHistory() {
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let path = dir.appendingPathComponent("playback_history.json")
        guard let data = try? Data(contentsOf: path) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let items = try? decoder.decode([PlaybackHistoryItem].self, from: data) {
            playbackHistory = items
        }
    }

    private func saveHistory() {
        guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let path = dir.appendingPathComponent("playback_history.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(playbackHistory) {
            try? data.write(to: path)
        }
    }

    func clearHistory() {
        playbackHistory.removeAll()
        lastTrackPerZone.removeAll()
        saveHistory()
    }

    // MARK: - Send Helper

    private func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else {
            print("[WS] Failed to serialize message")
            return
        }
        debugLog("[WS] Sending: \(text)")
        webSocketTask?.send(.string(text)) { error in
            if let error = error {
                print("[WS] Send error: \(error.localizedDescription)")
            }
        }
    }
}
