import Foundation
import Combine

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

    // MARK: - Private

    private let connection = RoonConnection()
    private var transportService: RoonTransportService?
    private var browseService: RoonBrowseService?
    private var imageService: RoonImageService?

    private var lastTrackPerZone: [String: String] = [:]
    private var isConnected = false
    private var historyPlaybackIndex: Int?
    private var zonesById: [String: RoonZone] = [:]

    // MARK: - Connection

    func connect() {
        guard !isConnected else { return }
        isConnected = true
        connectionState = .connecting
        if playbackHistory.isEmpty { loadHistory() }

        // Initialize services
        transportService = RoonTransportService(connection: connection)
        browseService = RoonBrowseService(connection: connection)
        imageService = RoonImageService(connection: connection)

        // Configure image provider
        Task {
            await RoonImageProvider.shared.setImageService(imageService)
            await LocalImageServer.shared.start()
        }

        // Setup callbacks
        Task {
            await connection.setOnStateChange { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.handleConnectionStateChange(state)
                }
            }

            await connection.setOnZonesData { [weak self] data in
                Task { @MainActor [weak self] in
                    self?.handleZonesData(data)
                }
            }

            await connection.setOnQueueData { [weak self] zoneId, data in
                Task { @MainActor [weak self] in
                    self?.handleQueueData(zoneId: zoneId, data: data)
                }
            }

            // Start connection (discovery + registration)
            await connection.connect()
        }
    }

    func disconnect() {
        isConnected = false
        Task {
            await connection.disconnect()
        }
        connectionState = .disconnected
        zones = []
        currentZone = nil
        zonesById = [:]
    }

    // MARK: - Connection State Handling

    private func handleConnectionStateChange(_ state: RoonConnection.ConnectionState) {
        switch state {
        case .disconnected:
            if isConnected {
                connectionState = .disconnected
            }
        case .discovering, .connecting, .registering:
            connectionState = .connecting
        case .connected(let coreName):
            connectionState = .connected
            lastError = nil
            _ = coreName
        case .failed(let error):
            connectionState = .disconnected
            lastError = error
        }
    }

    // MARK: - Zone Handling

    private func handleZonesData(_ data: Data) {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let zonesArray = body["zones"] as? [[String: Any]] {
            zonesById.removeAll()
            for zoneDict in zonesArray {
                if let zone = decodeZone(zoneDict) {
                    zonesById[zone.zone_id] = zone
                }
            }
        }

        if let changed = body["zones_changed"] as? [[String: Any]] {
            for zoneDict in changed {
                if let zone = decodeZone(zoneDict) {
                    zonesById[zone.zone_id] = zone
                }
            }
        }

        if let added = body["zones_added"] as? [[String: Any]] {
            for zoneDict in added {
                if let zone = decodeZone(zoneDict) {
                    zonesById[zone.zone_id] = zone
                }
            }
        }

        if let removed = body["zones_removed"] as? [String] {
            for id in removed {
                zonesById.removeValue(forKey: id)
            }
        }

        if let seekChanged = body["zones_seek_changed"] as? [[String: Any]] {
            for seekInfo in seekChanged {
                if let zoneId = seekInfo["zone_id"] as? String,
                   let _ = zonesById[zoneId] {
                    var zoneDict = encodeZone(zonesById[zoneId]!)
                    if let seekPos = seekInfo["seek_position"] as? Int {
                        zoneDict["seek_position"] = seekPos
                    }
                    if let decoded = decodeZone(zoneDict) {
                        zonesById[zoneId] = decoded
                    }
                }
            }
        }

        let allZones = Array(zonesById.values)
        for zone in allZones {
            trackPlaybackHistory(zone: zone)
        }

        if allZones != zones {
            zones = allZones
        }

        if let current = currentZone {
            let updated = zonesById[current.zone_id]
            if updated != currentZone {
                currentZone = updated
            }
        }

        if currentZone == nil, let first = zones.first {
            selectZone(first)
        }
    }

    // MARK: - Queue Handling

    private func handleQueueData(zoneId: String, data: Data) {
        guard zoneId == currentZone?.zone_id else { return }
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let itemsArray = body["items"] as? [[String: Any]] else { return }

        let decoder = JSONDecoder()
        let decodedItems: [QueueItem] = itemsArray.compactMap { dict in
            guard let itemData = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
            return try? decoder.decode(QueueItem.self, from: itemData)
        }
        queueItems = decodedItems
    }

    // MARK: - Transport Controls

    func play() {
        guard let zoneId = currentZone?.zone_id else { return }
        Task { try? await transportService?.control(zoneId: zoneId, control: "play") }
    }

    func pause() {
        guard let zoneId = currentZone?.zone_id else { return }
        Task { try? await transportService?.control(zoneId: zoneId, control: "pause") }
    }

    func playPause() {
        guard let zoneId = currentZone?.zone_id else { return }
        Task { try? await transportService?.control(zoneId: zoneId, control: "playpause") }
    }

    func stop() {
        guard let zoneId = currentZone?.zone_id else { return }
        Task { try? await transportService?.control(zoneId: zoneId, control: "stop") }
    }

    func next() {
        // If playing from history, go to next history item (older)
        if let idx = historyPlaybackIndex, idx + 1 < playbackHistory.count {
            let nextItem = playbackHistory[idx + 1]
            searchAndPlay(title: nextItem.title, artist: nextItem.artist, album: nextItem.album)
            return
        }
        historyPlaybackIndex = nil
        guard let zoneId = currentZone?.zone_id else { return }
        Task { try? await transportService?.control(zoneId: zoneId, control: "next") }
    }

    func previous() {
        // If playing from history, go to previous history item (more recent)
        if let idx = historyPlaybackIndex, idx - 1 >= 0 {
            let prevItem = playbackHistory[idx - 1]
            searchAndPlay(title: prevItem.title, artist: prevItem.artist, album: prevItem.album)
            return
        }
        historyPlaybackIndex = nil
        guard let zoneId = currentZone?.zone_id else { return }
        Task { try? await transportService?.control(zoneId: zoneId, control: "previous") }
    }

    // MARK: - Seek

    func seek(position: Int) {
        guard let zoneId = currentZone?.zone_id else { return }
        Task { try? await transportService?.seek(zoneId: zoneId, how: "absolute", seconds: position) }
    }

    func seekRelative(seconds: Int) {
        guard let zoneId = currentZone?.zone_id else { return }
        Task { try? await transportService?.seek(zoneId: zoneId, how: "relative", seconds: seconds) }
    }

    // MARK: - Volume

    func setVolume(outputId: String, value: Double) {
        Task { try? await transportService?.changeVolume(outputId: outputId, how: "absolute", value: value) }
    }

    func mute(outputId: String) {
        Task { try? await transportService?.mute(outputId: outputId, how: "mute") }
    }

    func unmute(outputId: String) {
        Task { try? await transportService?.mute(outputId: outputId, how: "unmute") }
    }

    func toggleMute(outputId: String) {
        Task { try? await transportService?.mute(outputId: outputId, how: "toggle") }
    }

    // MARK: - Settings

    func setShuffle(_ enabled: Bool) {
        guard let zoneId = currentZone?.zone_id else { return }
        Task { try? await transportService?.changeSettings(zoneId: zoneId, settings: ["shuffle": enabled]) }
    }

    func setLoop(_ mode: String) {
        guard let zoneId = currentZone?.zone_id else { return }
        Task { try? await transportService?.changeSettings(zoneId: zoneId, settings: ["loop": mode]) }
    }

    func setAutoRadio(_ enabled: Bool) {
        guard let zoneId = currentZone?.zone_id else { return }
        Task { try? await transportService?.changeSettings(zoneId: zoneId, settings: ["auto_radio": enabled]) }
    }

    // MARK: - Zone Selection

    func selectZone(_ zone: RoonZone) {
        currentZone = zone
        queueItems = []
        historyPlaybackIndex = nil
        subscribeQueue()
    }

    // MARK: - Queue

    func subscribeQueue() {
        guard let zoneId = currentZone?.zone_id else { return }
        Task { await transportService?.subscribeQueue(zoneId: zoneId) }
    }

    func playFromHere(queueItemId: Int) {
        historyPlaybackIndex = nil
        guard let zoneId = currentZone?.zone_id else { return }
        Task { try? await transportService?.playFromHere(zoneId: zoneId, queueItemId: queueItemId) }
    }

    // MARK: - Browse

    private var pendingBrowseKey: String?

    func browse(hierarchy: String = "browse", itemKey: String? = nil, input: String? = nil, popLevels: Int? = nil, popAll: Bool = false) {
        let browseKey = itemKey ?? "__root__"
        if itemKey != nil && browseKey == pendingBrowseKey {
            return
        }
        pendingBrowseKey = browseKey

        guard let browseService = browseService else { return }
        let zoneId = currentZone?.zone_id

        Task {
            do {
                let response = try await browseService.browse(
                    hierarchy: hierarchy,
                    zoneId: zoneId,
                    itemKey: itemKey,
                    input: input,
                    popLevels: popLevels,
                    popAll: popAll
                )
                await MainActor.run {
                    self.handleBrowseResponse(response, isPageLoad: false)
                }
            } catch {
                await MainActor.run {
                    self.lastError = "Browse error: \(error.localizedDescription)"
                }
            }
        }
    }

    func browseLoad(hierarchy: String = "browse", offset: Int = 0, count: Int = 100) {
        guard let browseService = browseService else { return }

        Task {
            do {
                let response = try await browseService.load(hierarchy: hierarchy, offset: offset, count: count)
                await MainActor.run {
                    self.handleBrowseLoadResponse(response)
                }
            } catch {
                // Load failed silently
            }
        }
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

    private func handleBrowseResponse(_ response: RoonBrowseService.BrowseResponse, isPageLoad: Bool) {
        let decoder = JSONDecoder()
        let newItems: [BrowseItem] = response.items.compactMap { dict in
            guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
            return try? decoder.decode(BrowseItem.self, from: data)
        }

        var list: BrowseList?
        if let listDict = response.list,
           let listData = try? JSONSerialization.data(withJSONObject: listDict) {
            list = try? decoder.decode(BrowseList.self, from: listData)
        }

        browseResult = BrowseResult(
            action: response.action,
            list: list,
            items: newItems,
            offset: 0
        )

        if let title = list?.title {
            if let level = list?.level, level > 0 {
                while browseStack.count >= level {
                    browseStack.removeLast()
                }
                browseStack.append(title)
            } else {
                browseStack = [title]
            }
        }
    }

    private func handleBrowseLoadResponse(_ response: RoonBrowseService.LoadResponse) {
        let decoder = JSONDecoder()
        let newItems: [BrowseItem] = response.items.compactMap { dict in
            guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
            return try? decoder.decode(BrowseItem.self, from: data)
        }

        let offset = response.offset

        if offset > 0, var existing = browseResult {
            existing.items.append(contentsOf: newItems)
            existing.offset = offset
            browseResult = existing
        } else {
            var list: BrowseList?
            if let listDict = response.list,
               let listData = try? JSONSerialization.data(withJSONObject: listDict) {
                list = try? decoder.decode(BrowseList.self, from: listData)
            }
            browseResult = BrowseResult(
                action: "list",
                list: list,
                items: newItems,
                offset: 0
            )
        }
    }

    // MARK: - Play from History (searchAndPlay)

    func searchAndPlay(title: String, artist: String = "", album: String = "") {
        guard let zoneId = currentZone?.zone_id else { return }
        guard let browseService = browseService else { return }

        // Track history playback index
        if let idx = playbackHistory.firstIndex(where: { $0.title == title }) {
            historyPlaybackIndex = idx
        }

        let playSessionBrowse = RoonBrowseService(connection: connection, sessionKey: "play_search")

        Task {
            await performPlaySearch(
                browseService: playSessionBrowse,
                zoneId: zoneId,
                title: title,
                artist: artist,
                album: album
            )
        }
    }

    private func performPlaySearch(
        browseService: RoonBrowseService,
        zoneId: String,
        title: String,
        artist: String,
        album: String
    ) async {
        do {
            // Step 1: Reset browse and find search
            _ = try await browseService.browse(zoneId: zoneId, popAll: true)
            let rootLoad = try await browseService.load(offset: 0, count: 20)
            let rootItems = rootLoad.items

            var searchItem = rootItems.first { ($0["input_prompt"] as? [String: Any]) != nil }

            if searchItem == nil {
                // Try Library submenu
                let libraryItem = rootItems.first {
                    let t = $0["title"] as? String ?? ""
                    return t == "Library" || t == "Bibliothèque"
                }
                if let libraryItem = libraryItem, let itemKey = libraryItem["item_key"] as? String {
                    _ = try await browseService.browse(zoneId: zoneId, itemKey: itemKey)
                    let libLoad = try await browseService.load(offset: 0, count: 20)
                    searchItem = libLoad.items.first { ($0["input_prompt"] as? [String: Any]) != nil }
                }
            }

            guard let searchItem = searchItem, let searchItemKey = searchItem["item_key"] as? String else { return }

            // Try album-based search first if album is provided
            if !album.isEmpty {
                let albumSuccess = try await doAlbumSearch(
                    browseService: browseService, zoneId: zoneId,
                    searchItemKey: searchItemKey, title: title, album: album
                )
                if albumSuccess { return }
            }

            // Fallback: search by track title
            try await doTrackSearch(
                browseService: browseService, zoneId: zoneId,
                searchItemKey: searchItemKey, title: title
            )
        } catch {
            // Search failed
        }
    }

    private func doAlbumSearch(
        browseService: RoonBrowseService,
        zoneId: String,
        searchItemKey: String,
        title: String,
        album: String
    ) async throws -> Bool {
        let searchResult = try await browseService.browse(zoneId: zoneId, itemKey: searchItemKey, input: album)
        guard !searchResult.items.isEmpty else { return false }

        let albumsCat = searchResult.items.first { item in
            let hint = item["hint"] as? String ?? ""
            let t = item["title"] as? String ?? ""
            return hint == "list" && t.lowercased().contains("album")
        }
        guard let albumsCat = albumsCat, let albumsCatKey = albumsCat["item_key"] as? String else { return false }

        let albumsResult = try await browseService.browse(zoneId: zoneId, itemKey: albumsCatKey)
        guard let firstAlbum = albumsResult.items.first,
              let firstAlbumKey = firstAlbum["item_key"] as? String else { return false }

        let tracksResult = try await browseService.browse(zoneId: zoneId, itemKey: firstAlbumKey)
        let titleLower = title.lowercased()
        let matchTrack = tracksResult.items.first { item in
            let hint = item["hint"] as? String ?? ""
            let t = item["title"] as? String ?? ""
            return hint == "action_list" && t.lowercased().contains(titleLower)
        } ?? tracksResult.items.first { ($0["hint"] as? String) == "action_list" }

        if let matchTrack = matchTrack, let trackKey = matchTrack["item_key"] as? String {
            try await playBrowseItem(browseService: browseService, zoneId: zoneId, itemKey: trackKey)
            return true
        }

        return false
    }

    private func doTrackSearch(
        browseService: RoonBrowseService,
        zoneId: String,
        searchItemKey: String,
        title: String
    ) async throws {
        // Reset browse first
        _ = try await browseService.browse(zoneId: zoneId, popAll: true)
        let rootLoad = try await browseService.load(offset: 0, count: 20)
        let rootItems = rootLoad.items

        var si = rootItems.first { ($0["input_prompt"] as? [String: Any]) != nil }
        if si == nil {
            let lib = rootItems.first {
                let t = $0["title"] as? String ?? ""
                return t == "Library" || t == "Bibliothèque"
            }
            if let lib = lib, let libKey = lib["item_key"] as? String {
                _ = try await browseService.browse(zoneId: zoneId, itemKey: libKey)
                let libLoad = try await browseService.load(offset: 0, count: 20)
                si = libLoad.items.first { ($0["input_prompt"] as? [String: Any]) != nil }
            }
        }

        guard let si = si, let siKey = si["item_key"] as? String else { return }

        let searchResult = try await browseService.browse(zoneId: zoneId, itemKey: siKey, input: title)
        guard !searchResult.items.isEmpty else { return }

        // Look for direct action item
        let actionItem = searchResult.items.first { ($0["hint"] as? String) == "action_list" }
        if let actionItem = actionItem, let key = actionItem["item_key"] as? String {
            try await playBrowseItem(browseService: browseService, zoneId: zoneId, itemKey: key)
            return
        }

        // Navigate into a category
        let category = searchResult.items.first { item in
            let hint = item["hint"] as? String ?? ""
            let t = item["title"] as? String ?? ""
            return hint == "list" && t.lowercased().contains("track")
        } ?? searchResult.items.first { ($0["hint"] as? String) == "list" }

        guard let category = category, let catKey = category["item_key"] as? String else { return }

        let catResult = try await browseService.browse(zoneId: zoneId, itemKey: catKey)
        if let trackItem = catResult.items.first(where: { ($0["hint"] as? String) == "action_list" }),
           let trackKey = trackItem["item_key"] as? String {
            try await playBrowseItem(browseService: browseService, zoneId: zoneId, itemKey: trackKey)
        }
    }

    private func playBrowseItem(
        browseService: RoonBrowseService,
        zoneId: String,
        itemKey: String,
        depth: Int = 0
    ) async throws {
        guard depth <= 3 else { return }

        let result = try await browseService.browse(zoneId: zoneId, itemKey: itemKey)
        let action = result.action

        if action == "message" { return } // Action executed

        // Look for play actions
        let playFromHere = result.items.first { item in
            let hint = item["hint"] as? String ?? ""
            let t = item["title"] as? String ?? ""
            return hint == "action" && (t.lowercased().contains("play from here") || t.lowercased().contains("lire") && t.lowercased().contains("partir"))
        }

        let directAction = playFromHere ?? result.items.first { ($0["hint"] as? String) == "action" }

        if let directAction = directAction, let key = directAction["item_key"] as? String {
            _ = try await browseService.browse(zoneId: zoneId, itemKey: key)
            return
        }

        // Recurse into nested action_list
        let nextItem = result.items.first { ($0["hint"] as? String) == "action_list" } ?? result.items.first
        if let nextItem = nextItem, let key = nextItem["item_key"] as? String {
            try await playBrowseItem(browseService: browseService, zoneId: zoneId, itemKey: key, depth: depth + 1)
        }
    }

    // MARK: - Core Connection (manual)

    func connectCore(ip: String) {
        connectionState = .connecting
        Task {
            await connection.disconnect()
            await connection.connectDirect(host: ip, port: 9330)
        }
    }

    // MARK: - Image URL

    func imageURL(key: String?, width: Int = 300, height: Int = 300) -> URL? {
        guard let key = key else { return nil }
        return LocalImageServer.imageURL(key: key, width: width, height: height)
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

        if let last = playbackHistory.first(where: { $0.zone_name == zone.display_name }),
           last.title == title {
            return
        }

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

    // MARK: - Zone Encoding/Decoding Helpers

    private func decodeZone(_ dict: [String: Any]) -> RoonZone? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(RoonZone.self, from: data)
    }

    private func encodeZone(_ zone: RoonZone) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(zone),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }
}
