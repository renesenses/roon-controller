import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

@MainActor
class RoonService: ObservableObject {

    // MARK: - Published State
    //
    // The 5 "hot" properties below are NOT @Published to avoid cascading
    // objectWillChange notifications during rapid zone/queue updates.
    // We call objectWillChange.send() manually once before batched mutations.

    @Published var connectionState: RoonState = .disconnected
    var zones: [RoonZone] = []
    var currentZone: RoonZone?
    @Published var browseResult: BrowseResult?
    @Published var browseStack: [String] = []
    var queueItems: [QueueItem] = []
    var playbackHistory: [PlaybackHistoryItem] = []
    @Published var radioFavorites: [RadioFavorite] = []
    var seekPosition: Int = 0
    @Published var browseLoading: Bool = false
    @Published var playlistCreationStatus: String?
    @Published var lastError: String?
    @Published var sidebarCategories: [BrowseItem] = []
    @Published var sidebarPlaylists: [BrowseItem] = []
    @Published var libraryCounts: [String: Int] = [:]
    var recentlyAdded: [BrowseItem] = []

    // MARK: - Storage

    private let storageDirectory: URL?

    init(storageDirectory: URL? = nil) {
        self.storageDirectory = storageDirectory
    }

    private var storageDir: URL? {
        storageDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    }

    // MARK: - Private

    private let connection = RoonConnection()
    private var transportService: RoonTransportService?
    private var browseService: RoonBrowseService?
    private var imageService: RoonImageService?

    private var lastTrackPerZone: [String: String] = [:]
    private var currentTrackIdentity: String = ""
    private var isConnected = false
    private var historyPlaybackIndex: Int?
    private var zonesById: [String: RoonZone] = [:]
    private var lastQueueSubscribeTime: Date = .distantPast
    private var currentBrowseTask: Task<Void, Never>?
    private var currentPlayTask: Task<Void, Never>?
    private var seekTimer: Timer?
    private var refreshTimer: Timer?

    // MARK: - Connection

    func connect() {
        guard !isConnected else { return }
        isConnected = true
        connectionState = .connecting
        if playbackHistory.isEmpty { loadHistory() }
        if radioFavorites.isEmpty { loadFavorites() }

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
                DispatchQueue.main.async { [weak self] in
                    self?.handleConnectionStateChange(state)
                }
            }

            await connection.setOnZonesData { [weak self] data in
                DispatchQueue.main.async { [weak self] in
                    self?.handleZonesData(data)
                }
            }

            await connection.setOnQueueData { [weak self] zoneId, data in
                DispatchQueue.main.async { [weak self] in
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
        zones = []
        currentZone = nil
        zonesById = [:]
        connectionState = .disconnected // @Published triggers single objectWillChange
    }

    // MARK: - Connection State Handling

    private func handleConnectionStateChange(_ state: RoonConnection.ConnectionState) {
        switch state {
        case .disconnected:
            if isConnected {
                connectionState = .disconnected
            }
            stopSeekTimer()
        case .discovering, .connecting, .registering:
            connectionState = .connecting
        case .waitingForApproval:
            connectionState = .waitingForApproval
        case .connected(let coreName):
            connectionState = .connected
            lastError = nil
            _ = coreName
            // Re-subscribe queue after reconnection (lost when transport disconnects)
            subscribeQueue()
            // Re-fetch data after reconnection
            if !sidebarCategories.isEmpty {
                fetchSidebarCategories()
                fetchRecentlyAdded()
            }
            startRefreshTimer()
        case .failed(let error):
            connectionState = .disconnected
            lastError = error
            stopSeekTimer()
            stopRefreshTimer()
        }
    }

    // MARK: - Zone Handling

    func handleZonesData(_ data: Data) {
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

        let isSeekOnly = body["zones_seek_changed"] != nil
            && body["zones"] == nil
            && body["zones_changed"] == nil
            && body["zones_added"] == nil
            && body["zones_removed"] == nil

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
            // seekPosition is driven by the interpolation timer (while playing)
            // and synced from full zone updates — no update needed here
            if isSeekOnly { return }
        }

        // Sort zones consistently (Dictionary.values has no guaranteed order)
        let allZones = Array(zonesById.values).sorted { $0.zone_id < $1.zone_id }

        // Track history before notifying views (may modify playbackHistory)
        for zone in allZones {
            trackPlaybackHistory(zone: zone)
        }

        // Single objectWillChange for all mutations below
        objectWillChange.send()

        zones = allZones

        if let current = currentZone {
            let updated = zonesById[current.zone_id]
            if updated != currentZone {
                currentZone = updated
            }
        }

        if currentZone == nil, let first = zones.first {
            selectZone(first)
            // Fetch sidebar categories now that we have a zone for the browse API
            if sidebarCategories.isEmpty {
                fetchSidebarCategories()
                fetchRecentlyAdded()
            }
        }

        // Detect track change and reset seek position
        if let zoneId = currentZone?.zone_id, let zone = zonesById[zoneId] {
            let newIdentity = trackIdentity(zone.now_playing)
            if zone.now_playing != nil && newIdentity != currentTrackIdentity {
                // Track changed — reset seek to server value or 0
                currentTrackIdentity = newIdentity
                seekPosition = zone.seek_position ?? 0
            } else if zone.state == "playing", let serverSeek = zone.seek_position {
                // Same track, playing: sync from server
                seekPosition = serverSeek
            }
        }

        // Manage seek interpolation timer based on playback state
        if currentZone?.state == "playing" {
            startSeekTimer()
        } else {
            stopSeekTimer()
        }
    }

    // MARK: - Queue Handling

    private func handleQueueData(zoneId: String, data: Data) {
        guard zoneId == currentZone?.zone_id else { return }
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let itemsArray = body["items"] as? [[String: Any]] {
            let decoder = JSONDecoder()
            let decodedItems: [QueueItem] = itemsArray.compactMap { dict in
                guard let itemData = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                return try? decoder.decode(QueueItem.self, from: itemData)
            }
            objectWillChange.send()
            queueItems = decodedItems
        } else if body["changes"] != nil {
            // Incremental queue update — re-subscribe to get full queue
            subscribeQueue()
        }
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
            searchAndPlay(title: nextItem.title, artist: nextItem.artist, album: nextItem.album, isRadio: nextItem.isRadio)
            return
        }
        historyPlaybackIndex = nil
        guard let zoneId = currentZone?.zone_id else { return }
        objectWillChange.send()
        seekPosition = 0
        Task { try? await transportService?.control(zoneId: zoneId, control: "next") }
    }

    func previous() {
        // If playing from history, go to previous history item (more recent)
        if let idx = historyPlaybackIndex, idx - 1 >= 0 {
            let prevItem = playbackHistory[idx - 1]
            searchAndPlay(title: prevItem.title, artist: prevItem.artist, album: prevItem.album, isRadio: prevItem.isRadio)
            return
        }
        historyPlaybackIndex = nil
        guard let zoneId = currentZone?.zone_id else { return }
        objectWillChange.send()
        seekPosition = 0
        Task { try? await transportService?.control(zoneId: zoneId, control: "previous") }
    }

    // MARK: - Seek

    func seek(position: Int) {
        guard let zoneId = currentZone?.zone_id else { return }
        objectWillChange.send()
        seekPosition = position
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
        objectWillChange.send()
        currentZone = zone
        seekPosition = zone.seek_position ?? 0
        currentTrackIdentity = trackIdentity(zone.now_playing)
        queueItems = []
        historyPlaybackIndex = nil
        subscribeQueue()
    }

    // MARK: - Queue

    func subscribeQueue() {
        guard let zoneId = currentZone?.zone_id else { return }
        // Debounce: don't re-subscribe more than once per second
        let now = Date()
        guard now.timeIntervalSince(lastQueueSubscribeTime) > 1.0 else { return }
        lastQueueSubscribeTime = now
        Task { await transportService?.subscribeQueue(zoneId: zoneId) }
    }

    func playFromHere(queueItemId: Int) {
        historyPlaybackIndex = nil
        guard let zoneId = currentZone?.zone_id else { return }
        objectWillChange.send()
        seekPosition = 0
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

        browseLoading = true

        // Cancel previous browse to avoid concurrent requests on the same session
        currentBrowseTask?.cancel()
        currentBrowseTask = Task {
            do {
                let response = try await browseService.browse(
                    hierarchy: hierarchy,
                    zoneId: zoneId,
                    itemKey: itemKey,
                    input: input,
                    popLevels: popLevels,
                    popAll: popAll
                )
                guard !Task.isCancelled else {
                    DispatchQueue.main.async { [weak self] in self?.browseLoading = false }
                    return
                }
                DispatchQueue.main.async { [weak self] in
                    self?.handleBrowseResponse(response, isPageLoad: false)
                }
            } catch {
                guard !Task.isCancelled else {
                    DispatchQueue.main.async { [weak self] in self?.browseLoading = false }
                    return
                }
                DispatchQueue.main.async { [weak self] in
                    self?.browseLoading = false
                    self?.lastError = "Browse error: \(error.localizedDescription)"
                }
            }
        }
    }

    func browseLoad(hierarchy: String = "browse", offset: Int = 0, count: Int = 100) {
        guard let browseService = browseService else { return }

        Task {
            do {
                let response = try await browseService.load(hierarchy: hierarchy, offset: offset, count: count)
                DispatchQueue.main.async { [weak self] in
                    self?.handleBrowseLoadResponse(response)
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

    /// Navigate to browse root, find the search item, and submit a query.
    /// Results appear in browseResult for RoonBrowseContentView.
    func browseSearch(query: String) {
        guard let browseService = browseService else { return }
        let zoneId = currentZone?.zone_id
        browseLoading = true
        pendingBrowseKey = nil
        browseStack.removeAll()

        currentBrowseTask?.cancel()
        currentBrowseTask = Task {
            do {
                // Reset to root
                _ = try await browseService.browse(zoneId: zoneId, popAll: true)
                guard !Task.isCancelled else { return }
                let rootLoad = try await browseService.load(offset: 0, count: 20)
                guard !Task.isCancelled else { return }

                // Find search item (has input_prompt)
                let searchItem = rootLoad.items.first { ($0["input_prompt"] as? [String: Any]) != nil }
                guard let searchItem = searchItem,
                      let searchItemKey = searchItem["item_key"] as? String else {
                    await MainActor.run { browseLoading = false }
                    return
                }

                // Submit search query
                let response = try await browseService.browse(zoneId: zoneId, itemKey: searchItemKey, input: query)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    handleBrowseResponse(response, isPageLoad: false)
                }
            } catch {
                await MainActor.run {
                    browseLoading = false
                    lastError = "Search error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func handleBrowseResponse(_ response: RoonBrowseService.BrowseResponse, isPageLoad: Bool) {
        browseLoading = false
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

        // Queue subscription is already active from selectZone();
        // Roon Core sends queue updates automatically when playback starts.

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

    // MARK: - Sidebar Categories

    private static let playlistTitles = Set(["Listes de lecture", "Playlists"])

    // Mapping from Roon titles (FR/EN) to normalized keys for libraryCounts
    private static let countKeyMap: [String: String] = [
        "Albums": "albums", "Artistes": "artists", "Artists": "artists",
        "Morceaux": "tracks", "Tracks": "tracks",
        "Compositeurs": "composers", "Composers": "composers"
    ]

    private static let libraryTitles = Set(["Library", "Bibliothèque"])
    private static let hiddenTitles = Set(["Settings", "Paramètres"])

    func fetchSidebarCategories() {
        let zoneId = currentZone?.zone_id

        Task {
            do {
                let decoder = JSONDecoder()

                // Session 1: Browse root → then into Library (same session so item_key is valid)
                let rootSession = RoonBrowseService(connection: connection, sessionKey: "sidebar")
                let rootResponse = try await rootSession.browse(zoneId: zoneId, popAll: true)
                let rootItems: [BrowseItem] = rootResponse.items.compactMap { dict in
                    guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                    return try? decoder.decode(BrowseItem.self, from: data)
                }

                // Navigate into Library using the SAME session (item_key is session-bound)
                var libraryItems: [BrowseItem] = []
                if let libItem = rootItems.first(where: { Self.libraryTitles.contains($0.title ?? "") }),
                   let libKey = libItem.item_key {
                    let libResponse = try await rootSession.browse(zoneId: zoneId, itemKey: libKey)
                    libraryItems = libResponse.items.compactMap { dict in
                        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                        return try? decoder.decode(BrowseItem.self, from: data)
                    }
                }

                // Session 2: Browse root → then into Playlists
                var playlists: [BrowseItem] = []
                let plSession = RoonBrowseService(connection: connection, sessionKey: "sidebar_pl")
                let plRootResponse = try await plSession.browse(zoneId: zoneId, popAll: true)
                let plRootItems: [BrowseItem] = plRootResponse.items.compactMap { dict in
                    guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                    return try? decoder.decode(BrowseItem.self, from: data)
                }
                if let plItem = plRootItems.first(where: { Self.playlistTitles.contains($0.title ?? "") }),
                   let plKey = plItem.item_key {
                    let plResponse = try await plSession.browse(zoneId: zoneId, itemKey: plKey)
                    playlists = plResponse.items.compactMap { dict in
                        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                        return try? decoder.decode(BrowseItem.self, from: data)
                    }
                }

                // Merge: root items (except Library, Settings, Playlists, search) + library sub-items
                var allItems: [BrowseItem] = rootItems.filter {
                    let t = $0.title ?? ""
                    return $0.input_prompt == nil
                        && !Self.libraryTitles.contains(t)
                        && !Self.playlistTitles.contains(t)
                        && !Self.hiddenTitles.contains(t)
                }
                allItems.append(contentsOf: libraryItems.filter { $0.input_prompt == nil })

                await MainActor.run {
                    self.sidebarCategories = allItems
                    self.sidebarPlaylists = playlists
                }

                // Session 3: Fetch library counts — navigate root → Library, then each sub-item
                if !libraryItems.isEmpty {
                    let countSession = RoonBrowseService(connection: connection, sessionKey: "sidebar_counts")
                    // Navigate to Library level
                    let cRoot = try await countSession.browse(zoneId: zoneId, popAll: true)
                    let cRootItems: [BrowseItem] = cRoot.items.compactMap { dict in
                        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                        return try? decoder.decode(BrowseItem.self, from: data)
                    }
                    if let libItem = cRootItems.first(where: { Self.libraryTitles.contains($0.title ?? "") }),
                       let libKey = libItem.item_key {
                        let cLib = try await countSession.browse(zoneId: zoneId, itemKey: libKey)
                        let cLibItems: [BrowseItem] = cLib.items.compactMap { dict in
                            guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                            return try? decoder.decode(BrowseItem.self, from: data)
                        }

                        var counts: [String: Int] = [:]
                        for item in cLibItems {
                            guard let title = item.title,
                                  let normalizedKey = Self.countKeyMap[title],
                                  counts[normalizedKey] == nil,
                                  let key = item.item_key else { continue }
                            do {
                                let catResponse = try await countSession.browse(zoneId: zoneId, itemKey: key)
                                if let list = catResponse.list, let count = list["count"] as? Int {
                                    counts[normalizedKey] = count
                                }
                                // Pop back to Library level for next item
                                _ = try await countSession.browse(zoneId: zoneId, popLevels: 1)
                            } catch {
                                // Count fetch failed for this item, continue
                            }
                        }

                        await MainActor.run {
                            self.libraryCounts = counts
                        }
                    }
                }
            } catch {
                // Sidebar fetch failed silently
            }
        }
    }

    // MARK: - Recently Added (Browse: Library → Albums)

    private static let albumsTitles = Set(["Albums"])

    func fetchRecentlyAdded() {
        let zoneId = currentZone?.zone_id

        Task {
            do {
                let decoder = JSONDecoder()
                let session = RoonBrowseService(connection: connection, sessionKey: "recently_added")

                // Navigate to root
                let rootResponse = try await session.browse(zoneId: zoneId, popAll: true)
                let rootItems: [BrowseItem] = rootResponse.items.compactMap { dict in
                    guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                    return try? decoder.decode(BrowseItem.self, from: data)
                }

                // Navigate into Library
                guard let libItem = rootItems.first(where: { Self.libraryTitles.contains($0.title ?? "") }),
                      let libKey = libItem.item_key else { return }
                let libResponse = try await session.browse(zoneId: zoneId, itemKey: libKey)
                let libItems: [BrowseItem] = libResponse.items.compactMap { dict in
                    guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                    return try? decoder.decode(BrowseItem.self, from: data)
                }

                // Navigate into Albums
                guard let albumsItem = libItems.first(where: { Self.albumsTitles.contains($0.title ?? "") }),
                      let albumsKey = albumsItem.item_key else { return }
                let albumsResponse = try await session.browse(zoneId: zoneId, itemKey: albumsKey)

                // Load first 20 items (sorted by date added by default)
                let items: [BrowseItem] = albumsResponse.items.compactMap { dict in
                    guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                    return try? decoder.decode(BrowseItem.self, from: data)
                }

                // If browse returned fewer than 20, try load for more
                var allItems = items
                if allItems.count < 20 {
                    let loadResult = try await session.load(offset: 0, count: 20)
                    let loadItems: [BrowseItem] = loadResult.items.compactMap { dict in
                        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                        return try? decoder.decode(BrowseItem.self, from: data)
                    }
                    if loadItems.count > allItems.count {
                        allItems = loadItems
                    }
                }

                await MainActor.run {
                    objectWillChange.send()
                    self.recentlyAdded = Array(allItems.prefix(20))
                }
            } catch {
                // Recently added fetch failed silently
            }
        }
    }

    func playRecentlyAddedItem(itemKey: String) {
        guard let zoneId = currentZone?.zone_id else { return }
        let session = RoonBrowseService(connection: connection, sessionKey: "play_recent")
        currentPlayTask?.cancel()
        currentPlayTask = Task {
            do {
                try await playBrowseItem(browseService: session, zoneId: zoneId, itemKey: itemKey)
            } catch {
                // Play failed silently
            }
        }
    }

    func browseToCategory(itemKey: String) {
        guard let browseService = browseService else { return }
        let zoneId = currentZone?.zone_id

        pendingBrowseKey = nil
        browseStack.removeAll()
        browseResult = nil
        browseLoading = true

        currentBrowseTask?.cancel()
        currentBrowseTask = Task {
            do {
                // Reset to root first
                _ = try await browseService.browse(zoneId: zoneId, popAll: true)
                guard !Task.isCancelled else { return }
                // Navigate into the category
                let response = try await browseService.browse(zoneId: zoneId, itemKey: itemKey)
                guard !Task.isCancelled else { return }
                DispatchQueue.main.async { [weak self] in
                    self?.handleBrowseResponse(response, isPageLoad: false)
                }
            } catch {
                guard !Task.isCancelled else { return }
                DispatchQueue.main.async { [weak self] in
                    self?.browseLoading = false
                }
            }
        }
    }

    // MARK: - Play from History (searchAndPlay)

    func searchAndPlay(title: String, artist: String = "", album: String = "", isRadio: Bool = false) {
        guard let zoneId = currentZone?.zone_id else { return }

        // Cancel any in-flight play operation to avoid concurrent browse requests
        currentPlayTask?.cancel()

        // Track history playback index
        if let idx = playbackHistory.firstIndex(where: { $0.title == title }) {
            historyPlaybackIndex = idx
        }

        if isRadio {
            let stationName = album.isEmpty ? title : album
            let radioSession = RoonBrowseService(connection: connection, sessionKey: "play_radio")
            currentPlayTask = Task {
                try? await playRadioStation(browseService: radioSession, zoneId: zoneId, stationName: stationName)
            }
            return
        }

        let playSessionBrowse = RoonBrowseService(connection: connection, sessionKey: "play_search")

        currentPlayTask = Task {
            await performPlaySearch(
                browseService: playSessionBrowse,
                zoneId: zoneId,
                title: title,
                artist: artist,
                album: album
            )
        }
    }

    private func playRadioStation(
        browseService: RoonBrowseService,
        zoneId: String,
        stationName: String
    ) async throws {
        let result = try await browseService.browse(hierarchy: "internet_radio", zoneId: zoneId, popAll: true)
        guard !Task.isCancelled else { return }
        let nameLower = stationName.lowercased()
        let station = result.items.first {
            ($0["title"] as? String)?.lowercased() == nameLower
        }
        guard let station = station, let key = station["item_key"] as? String else { return }
        try await playBrowseItem(browseService: browseService, zoneId: zoneId, itemKey: key, hierarchy: "internet_radio")
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
            guard !Task.isCancelled else { return }
            let rootLoad = try await browseService.load(offset: 0, count: 20)
            guard !Task.isCancelled else { return }
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
                    guard !Task.isCancelled else { return }
                    let libLoad = try await browseService.load(offset: 0, count: 20)
                    guard !Task.isCancelled else { return }
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
                guard !Task.isCancelled else { return }
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
        guard !Task.isCancelled else { return false }
        guard !searchResult.items.isEmpty else { return false }

        let albumsCat = searchResult.items.first { item in
            let hint = item["hint"] as? String ?? ""
            let t = item["title"] as? String ?? ""
            return hint == "list" && t.lowercased().contains("album")
        }
        guard let albumsCat = albumsCat, let albumsCatKey = albumsCat["item_key"] as? String else { return false }

        let albumsResult = try await browseService.browse(zoneId: zoneId, itemKey: albumsCatKey)
        guard !Task.isCancelled else { return false }
        guard let firstAlbum = albumsResult.items.first,
              let firstAlbumKey = firstAlbum["item_key"] as? String else { return false }

        let tracksResult = try await browseService.browse(zoneId: zoneId, itemKey: firstAlbumKey)
        guard !Task.isCancelled else { return false }
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
        guard !Task.isCancelled else { return }
        let rootLoad = try await browseService.load(offset: 0, count: 20)
        guard !Task.isCancelled else { return }
        let rootItems = rootLoad.items

        var si = rootItems.first { ($0["input_prompt"] as? [String: Any]) != nil }
        if si == nil {
            let lib = rootItems.first {
                let t = $0["title"] as? String ?? ""
                return t == "Library" || t == "Bibliothèque"
            }
            if let lib = lib, let libKey = lib["item_key"] as? String {
                _ = try await browseService.browse(zoneId: zoneId, itemKey: libKey)
                guard !Task.isCancelled else { return }
                let libLoad = try await browseService.load(offset: 0, count: 20)
                guard !Task.isCancelled else { return }
                si = libLoad.items.first { ($0["input_prompt"] as? [String: Any]) != nil }
            }
        }

        guard let si = si, let siKey = si["item_key"] as? String else { return }

        let searchResult = try await browseService.browse(zoneId: zoneId, itemKey: siKey, input: title)
        guard !Task.isCancelled else { return }
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
        guard !Task.isCancelled else { return }
        if let trackItem = catResult.items.first(where: { ($0["hint"] as? String) == "action_list" }),
           let trackKey = trackItem["item_key"] as? String {
            try await playBrowseItem(browseService: browseService, zoneId: zoneId, itemKey: trackKey)
        }
    }

    private func playBrowseItem(
        browseService: RoonBrowseService,
        zoneId: String,
        itemKey: String,
        depth: Int = 0,
        hierarchy: String = "browse"
    ) async throws {
        guard depth <= 3 else { return }
        guard !Task.isCancelled else { return }

        let result = try await browseService.browse(hierarchy: hierarchy, zoneId: zoneId, itemKey: itemKey)
        guard !Task.isCancelled else { return }
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
            _ = try await browseService.browse(hierarchy: hierarchy, zoneId: zoneId, itemKey: key)
            return
        }

        // Recurse into nested action_list
        let nextItem = result.items.first { ($0["hint"] as? String) == "action_list" } ?? result.items.first
        if let nextItem = nextItem, let key = nextItem["item_key"] as? String {
            try await playBrowseItem(browseService: browseService, zoneId: zoneId, itemKey: key, depth: depth + 1, hierarchy: hierarchy)
        }
    }

    func playItem(itemKey: String) {
        guard let zoneId = currentZone?.zone_id else { return }
        // Cancel any in-flight play operation
        currentPlayTask?.cancel()
        // Use a dedicated session to avoid corrupting the UI browse session
        let playSession = RoonBrowseService(connection: connection, sessionKey: "play_item")
        currentPlayTask = Task {
            try? await playBrowseItem(browseService: playSession, zoneId: zoneId, itemKey: itemKey)
        }
    }

    /// Play from the current browse session (item keys are session-bound).
    /// Drills into the item to find a play action, then pops back to restore the playlist view.
    func playInCurrentSession(itemKey: String) {
        guard let browseService = browseService else { return }
        guard let zoneId = currentZone?.zone_id else { return }
        currentPlayTask?.cancel()
        currentPlayTask = Task {
            do {
                try await playBrowseItem(browseService: browseService, zoneId: zoneId, itemKey: itemKey)
                // Pop back to the playlist level so the browse view stays on the playlist
                _ = try await browseService.browse(zoneId: zoneId, popLevels: 1)
            } catch {
                // Play failed silently
            }
        }
    }

    private func logPL(_ msg: String) {
        let line = "\(Date()): \(msg)\n"
        let path = "/tmp/roon_pl_debug.txt"
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(line.data(using: .utf8)!)
            fh.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
        }
    }

    func browsePlaylist(title: String) {
        logPL("START browsePlaylist title='\(title)'")
        guard let browseService = browseService else {
            logPL("ERROR: browseService is nil")
            return
        }
        let zoneId = currentZone?.zone_id

        pendingBrowseKey = nil
        browseLoading = true
        browseResult = nil
        browseStack = []

        currentBrowseTask?.cancel()
        currentBrowseTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                // Pop to root
                let rootResponse = try await browseService.browse(zoneId: zoneId, popAll: true)
                guard !Task.isCancelled else { return }
                self.logPL("Root items: \(rootResponse.items.count)")
                for item in rootResponse.items {
                    self.logPL("  - \(item["title"] as? String ?? "?") key=\(item["item_key"] as? String ?? "?")")
                }

                // Find "Playlists" in root
                guard let plKey = rootResponse.items.first(where: {
                    let t = $0["title"] as? String ?? ""
                    return Self.playlistTitles.contains(t)
                })?["item_key"] as? String else {
                    self.logPL("ERROR: Playlists not found in root items")
                    await MainActor.run { self.browseLoading = false }
                    return
                }
                self.logPL("Found Playlists key=\(plKey)")

                // Navigate into Playlists container
                let plResponse = try await browseService.browse(zoneId: zoneId, itemKey: plKey)
                guard !Task.isCancelled else { return }
                self.logPL("Playlists container items: \(plResponse.items.count)")

                // Find the specific playlist by title (keys are session-specific)
                guard let playlistKey = plResponse.items.first(where: {
                    ($0["title"] as? String) == title
                })?["item_key"] as? String else {
                    self.logPL("ERROR: Playlist '\(title)' not found in \(plResponse.items.count) items")
                    for (i, item) in plResponse.items.prefix(5).enumerated() {
                        self.logPL("  [\(i)] \(item["title"] as? String ?? "?")")
                    }
                    await MainActor.run { self.browseLoading = false }
                    return
                }
                self.logPL("Found playlist '\(title)' key=\(playlistKey)")

                // Navigate into the playlist
                let response = try await browseService.browse(zoneId: zoneId, itemKey: playlistKey)
                guard !Task.isCancelled else { return }
                self.logPL("Playlist content: \(response.items.count) items, action=\(response.action ?? "nil")")

                await MainActor.run {
                    self.handleBrowseResponse(response, isPageLoad: false)
                }
            } catch {
                self.logPL("Error: \(error)")
                await MainActor.run {
                    self.browseLoading = false
                }
            }
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
            isRadio: zone.is_seek_allowed == false,
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
        guard let dir = storageDir else { return }
        let path = dir.appendingPathComponent("playback_history.json")
        guard let data = try? Data(contentsOf: path) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let items = try? decoder.decode([PlaybackHistoryItem].self, from: data) {
            objectWillChange.send()
            playbackHistory = items
        }
    }

    private func saveHistory() {
        guard let dir = storageDir else { return }
        let path = dir.appendingPathComponent("playback_history.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(playbackHistory) {
            try? data.write(to: path)
        }
    }

    func clearHistory() {
        objectWillChange.send()
        playbackHistory.removeAll()
        lastTrackPerZone.removeAll()
        saveHistory()
    }

    // MARK: - Radio Favorites

    func saveRadioFavorite() {
        guard let zone = currentZone,
              zone.is_seek_allowed == false,
              let np = zone.now_playing else { return }

        // For radio: line1=station, line2=track title, line3=artist
        let stationName = np.three_line?.line1 ?? np.one_line?.line1 ?? ""
        let trackTitle = np.three_line?.line2 ?? ""
        let trackArtist = np.three_line?.line3 ?? ""

        // Need at least a track title to save as favorite
        guard !trackTitle.isEmpty else { return }

        // Deduplication by track title + artist
        if radioFavorites.contains(where: { $0.title == trackTitle && $0.artist == trackArtist }) {
            return
        }

        let fav = RadioFavorite(
            id: UUID(),
            title: trackTitle,
            artist: trackArtist,
            stationName: stationName,
            image_key: np.image_key,
            savedAt: Date()
        )
        radioFavorites.insert(fav, at: 0)
        saveFavorites()
    }

    func removeRadioFavorite(id: UUID) {
        radioFavorites.removeAll { $0.id == id }
        saveFavorites()
    }

    func clearRadioFavorites() {
        radioFavorites.removeAll()
        saveFavorites()
    }

    func isCurrentTrackFavorite() -> Bool {
        guard let np = currentZone?.now_playing else { return false }
        // For radio: line2=track title, line3=artist
        let trackTitle = np.three_line?.line2 ?? ""
        let trackArtist = np.three_line?.line3 ?? ""
        guard !trackTitle.isEmpty else { return false }
        return radioFavorites.contains { $0.title == trackTitle && $0.artist == trackArtist }
    }

    func loadFavorites() {
        guard let dir = storageDir else { return }
        let path = dir.appendingPathComponent("radio_favorites.json")
        guard let data = try? Data(contentsOf: path) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let items = try? decoder.decode([RadioFavorite].self, from: data) {
            radioFavorites = items.sorted { $0.savedAt > $1.savedAt }
        }
    }

    private func saveFavorites() {
        guard let dir = storageDir else { return }
        let path = dir.appendingPathComponent("radio_favorites.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(radioFavorites) {
            try? data.write(to: path)
        }
    }

    // MARK: - Export Favorites

    func exportFavoritesCSV() {
        guard !radioFavorites.isEmpty else { return }

        var lines = [String]()
        for fav in radioFavorites where !fav.title.isEmpty {
            var artistName = fav.artist
            var trackName = fav.title
            // Handle old format "Artist - Track"
            if artistName.isEmpty && trackName.contains(" - ") {
                let parts = trackName.split(separator: " - ", maxSplits: 1)
                if parts.count == 2 {
                    artistName = String(parts[0])
                    trackName = String(parts[1])
                }
            }
            // CSV escape: double quotes around fields, double any internal quotes
            let escapedArtist = artistName.replacingOccurrences(of: "\"", with: "\"\"")
            let escapedTitle = trackName.replacingOccurrences(of: "\"", with: "\"\"")
            lines.append("\"\(escapedArtist)\",\"\(escapedTitle)\"")
        }

        let csv = "Artist,Title\n" + lines.joined(separator: "\n") + "\n"

        let panel = NSSavePanel()
        panel.title = String(localized: "Exporter les favoris")
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy_MM_dd"
        panel.nameFieldStringValue = "\(dateFmt.string(from: Date()))_favoris_radio.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? csv.write(to: url, atomically: true, encoding: .utf8)
            self.playlistCreationStatus = String(localized: "\(lines.count) morceaux exportes")
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run { self.playlistCreationStatus = nil }
            }
        }
    }

    // MARK: - Seek Interpolation

    private func startSeekTimer() {
        guard seekTimer == nil else { return }
        seekTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.currentZone?.state == "playing" {
                    self.objectWillChange.send()
                    self.seekPosition += 1
                }
            }
        }
    }

    private func stopSeekTimer() {
        seekTimer?.invalidate()
        seekTimer = nil
    }

    // MARK: - Refresh Timer (periodic stats/albums refresh)

    private func startRefreshTimer() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.connectionState == .connected else { return }
                self.fetchRecentlyAdded()
            }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// Stable identity for a track (ignores seek_position which changes every second)
    func trackIdentity(_ np: NowPlaying?) -> String {
        guard let np = np, let info = np.three_line else { return "" }
        return "\(info.line1 ?? "")|\(info.line2 ?? "")|\(info.line3 ?? "")|\(np.length ?? 0)"
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
