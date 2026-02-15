import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers
import MediaPlayer

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
    var browseCategory: String?
    var streamingAlbumDepth: Int = 0
    @Published var streamingSections: [StreamingSection] = []
    var queueItems: [QueueItem] = []
    var playbackHistory: [PlaybackHistoryItem] = []
    @Published var radioFavorites: [RadioFavorite] = []
    var seekPosition: Int = 0
    @Published var playbackTransitioning: Bool = false
    @Published var browseLoading: Bool = false
    @Published var playlistCreationStatus: String?
    @Published var lastError: String?
    @Published var connectionDetail: String?
    @Published var sidebarCategories: [BrowseItem] = []
    @Published var sidebarPlaylists: [BrowseItem] = []
    @Published var libraryCounts: [String: Int] = [:]
    var recentlyAdded: [BrowseItem] = []
    @Published var profileName: String?
    @Published var streamingCacheVersion: Int = 0
    @Published var myLiveRadioStations: [BrowseItem] = []

    // MARK: - Storage

    private let storageDirectory: URL?

    init(storageDirectory: URL? = nil) {
        self.storageDirectory = storageDirectory
        self.trackImageKeyCache = Self.loadImageKeyCache(
            from: storageDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        )
        loadStreamingSectionsCache()
        loadSidebarCache()
        setupRemoteCommands()
    }

    private var storageDir: URL? {
        storageDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    }

    // MARK: - Private

    private let connection = RoonConnection()
    private var transportService: RoonTransportService?
    private var browseService: RoonBrowseService?
    private var imageService: RoonImageService?

    /// Cache of track title → image_key, built from queue items (persisted to disk)
    private var trackImageKeyCache: [String: String] = [:]
    private var lastTrackPerZone: [String: String] = [:]
    private var currentTrackIdentity: String = ""
    private var isConnected = false
    private var historyPlaybackIndex: Int?
    private var zonesById: [String: RoonZone] = [:]
    private var lastQueueSubscribeTime: Date = .distantPast
    private var currentBrowseTask: Task<Void, Never>?
    private var streamingFetchTask: Task<Void, Never>?

    /// Cache of streaming sections keyed by "Qobuz:Nouvelles Sorties", "TIDAL:New Releases", etc.
    private var streamingSectionsCache: [String: CachedStreamingSections] = [:]
    private static let streamingSectionsCacheFile = "streaming_sections_cache.json"
    private static let streamingSectionsCacheExpiry: TimeInterval = 24 * 60 * 60

    private struct CachedStreamingSections: Codable {
        let sections: [StreamingSection]
        let date: Date
    }

    /// Sidebar categories/playlists disk cache for instant display on launch
    private static let sidebarCacheFile = "sidebar_cache.json"

    private struct CachedSidebar: Codable {
        let categories: [BrowseItem]
        let playlists: [BrowseItem]
    }

    func cancelStreamingFetch() {
        streamingFetchTask?.cancel()
        streamingFetchTask = nil
    }
    private var currentPlayTask: Task<Void, Never>?
    private var prefetchStreamingTask: Task<Void, Never>?
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

            // Start connection: use manual IP if set, otherwise SOOD discovery
            if let manualIP = Self.savedCoreIP, !manualIP.isEmpty {
                await connection.connectDirect(host: manualIP, port: 9330)
            } else {
                await connection.connect()
            }
        }
    }

    func disconnect() {
        isConnected = false
        prefetchStreamingTask?.cancel()
        prefetchStreamingTask = nil
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
                // Auto-reconnect: show "Reconnexion..." instead of flashing red
                connectionState = .connecting
                connectionDetail = "Reconnexion..."
            }
            stopSeekTimer()
        case .discovering:
            connectionState = .connecting
            connectionDetail = "Recherche du Core (SOOD)..."
        case .connecting:
            connectionState = .connecting
            connectionDetail = "Connexion WebSocket..."
        case .registering:
            connectionState = .connecting
            connectionDetail = "Enregistrement aupres du Core..."
        case .waitingForApproval:
            connectionState = .waitingForApproval
            connectionDetail = "En attente d'approbation dans Roon"
        case .connected(let coreName):
            connectionState = .connected
            lastError = nil
            connectionDetail = "Connecte a \(coreName)"
            // Re-subscribe queue after reconnection (lost when transport disconnects)
            subscribeQueue()
            // Re-fetch data after reconnection
            if !sidebarCategories.isEmpty {
                fetchSidebarCategories()
                fetchRecentlyAdded()
                prefetchStreamingServices()
            }
            startRefreshTimer()
        case .failed(let error):
            lastError = error
            if isConnected {
                // Auto-reconnect will fire — show reconnecting, not disconnected
                connectionState = .connecting
                connectionDetail = "Reconnexion... (\(error))"
            } else {
                connectionState = .disconnected
                connectionDetail = "Echec: \(error)"
            }
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

        // Track history only for the selected zone (avoids pollution from other zones)
        if let selectedZoneId = currentZone?.zone_id,
           let selectedZone = zonesById[selectedZoneId] {
            trackPlaybackHistory(zone: selectedZone)
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

        if currentZone == nil, !zones.isEmpty {
            let defaultName = UserDefaults.standard.string(forKey: "default_zone_name") ?? ""
            let target = zones.first(where: { $0.display_name == defaultName }) ?? zones.first!
            selectZone(target)
            // Fetch sidebar categories now that we have a zone for the browse API
            if sidebarCategories.isEmpty {
                fetchSidebarCategories()
                fetchRecentlyAdded()
                fetchProfileName()
                prefetchStreamingServices()
            }
        }

        // Detect track change and reset seek position
        if let zoneId = currentZone?.zone_id, let zone = zonesById[zoneId] {
            let newIdentity = trackIdentity(zone.now_playing)
            if zone.now_playing != nil && newIdentity != currentTrackIdentity {
                // Track changed — reset seek to server value or 0
                currentTrackIdentity = newIdentity
                seekPosition = zone.seek_position ?? 0
                playbackTransitioning = false
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

        // Update macOS Now Playing (Control Center)
        updateNowPlayingInfo()
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
            // Cache image keys for fallback when now_playing.image_key is nil
            var cacheChanged = false
            for item in decodedItems {
                if let title = item.three_line?.line1 ?? item.one_line?.line1,
                   let key = item.image_key,
                   trackImageKeyCache[title] != key {
                    trackImageKeyCache[title] = key
                    cacheChanged = true
                }
            }
            if cacheChanged { saveImageKeyCache() }
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
        playbackTransitioning = true
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
        playbackTransitioning = true
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

    // MARK: - macOS Now Playing (Control Center)

    /// Track identity used to avoid redundant Now Playing updates
    private var lastNowPlayingIdentity: String = ""

    /// Set up MPRemoteCommandCenter handlers (call once at startup)
    /// Note: addTarget closures run on MPRemoteCommandCenter's internal queue,
    /// so we must dispatch to MainActor to call @MainActor-isolated methods.
    func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playPause() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playPause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let pos = Int(posEvent.positionTime)
            Task { @MainActor in self?.seek(position: pos) }
            return .success
        }
    }

    /// Create MPMediaItemArtwork outside of @MainActor context.
    /// The requestHandler closure runs on MPNowPlayingInfoCenter's internal queue,
    /// so it must NOT be @MainActor-isolated.
    private nonisolated static func makeArtwork(data: Data, size: NSSize) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: size) { _ in
            NSImage(data: data) ?? NSImage()
        }
    }

    /// Update macOS Now Playing info from current zone state
    func updateNowPlayingInfo() {
        guard let zone = currentZone, let np = zone.now_playing else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            lastNowPlayingIdentity = ""
            return
        }

        let title = np.three_line?.line1 ?? np.one_line?.line1 ?? ""
        let artist = np.three_line?.line2 ?? ""
        let album = np.three_line?.line3 ?? np.two_line?.line2 ?? ""
        let identity = "\(title)|\(artist)|\(album)"
        let duration = Double(np.length ?? 0)
        let position = Double(seekPosition)

        let info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyAlbumTitle: album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: (zone.state == "playing") ? 1.0 : 0.0
        ]

        // Preserve existing artwork when updating (avoid overwriting async-fetched artwork)
        var mergedInfo = info
        if let existingArtwork = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] {
            mergedInfo[MPMediaItemPropertyArtwork] = existingArtwork
        }

        // Only fetch artwork when track changes
        if identity != lastNowPlayingIdentity {
            lastNowPlayingIdentity = identity
            let imageKey = resolvedImageKey(for: np)
            if let imageKey = imageKey {
                Task {
                    if let imgData = await RoonImageProvider.shared.fetchImage(key: imageKey, width: 600, height: 600),
                       let probe = NSImage(data: imgData) {
                        let artwork = Self.makeArtwork(data: imgData, size: probe.size)
                        var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? mergedInfo
                        updated[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
                    }
                }
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = mergedInfo

        switch zone.state {
        case "playing": MPNowPlayingInfoCenter.default().playbackState = .playing
        case "paused": MPNowPlayingInfoCenter.default().playbackState = .paused
        default: MPNowPlayingInfoCenter.default().playbackState = .stopped
        }
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
        // Track depth when navigating deeper inside a streaming album
        if itemKey != nil && streamingAlbumDepth > 0 {
            streamingAlbumDepth += 1
        }

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
        guard !browseStack.isEmpty else { return }
        browseStack.removeLast()
        if streamingAlbumDepth > 0 {
            streamingAlbumDepth -= 1
        }
        browse(popLevels: 1)
    }

    /// Pop back one level, then navigate into a sibling item (for streaming service tab switching)
    func browseSwitchSibling(itemKey: String, title: String) {
        guard let browseService = browseService else { return }
        let zoneId = currentZone?.zone_id
        pendingBrowseKey = nil
        browseLoading = true

        // Replace last stack entry with new title
        if !browseStack.isEmpty {
            browseStack[browseStack.count - 1] = title
        }

        currentBrowseTask?.cancel()
        currentBrowseTask = Task {
            do {
                // Pop back one level
                _ = try await browseService.browse(zoneId: zoneId, popLevels: 1)
                guard !Task.isCancelled else { return }
                // Navigate into sibling
                let response = try await browseService.browse(zoneId: zoneId, itemKey: itemKey)
                guard !Task.isCancelled else { return }
                DispatchQueue.main.async { [weak self] in
                    self?.handleBrowseResponse(response, isPageLoad: false)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.browseLoading = false
                }
            }
        }
    }

    /// Pre-fetch content for each sub-section of a streaming service tab.
    /// Uses the MAIN browse session (item_keys are session-specific in Roon).
    /// After completion, the session is back at tab content level.
    func fetchStreamingSections(items: [BrowseItem]) {
        guard let browseService = browseService else { return }
        // Guard: must be inside a tab (service + tab in browseStack) to avoid
        // race condition where auto-nav hasn't completed yet
        guard browseStack.count >= 2 else { return }
        let zoneId = currentZone?.zone_id
        let decoder = JSONDecoder()

        // Check cache before fetching (skip empty cached entries)
        let cacheKey = streamingSectionsCacheKey()
        if let cached = streamingSectionsCache[cacheKey],
           !cached.sections.isEmpty,
           Date().timeIntervalSince(cached.date) < Self.streamingSectionsCacheExpiry {
            streamingSections = cached.sections
            return
        }

        streamingSections = []

        streamingFetchTask?.cancel()
        streamingFetchTask = Task {
            var sections: [StreamingSection] = []

            func decodeItems(_ dicts: [[String: Any]]) -> [BrowseItem] {
                dicts.compactMap { dict in
                    guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                    return try? decoder.decode(BrowseItem.self, from: data)
                }
            }

            for item in items {
                guard !Task.isCancelled else { return }
                guard let itemKey = item.item_key, let title = item.title else { continue }
                do {
                    let response = try await browseService.browse(zoneId: zoneId, itemKey: itemKey)
                    guard !Task.isCancelled else {
                        // Pop back before exiting so session stays consistent
                        _ = try? await browseService.browse(zoneId: zoneId, popLevels: 1)
                        return
                    }
                    let level1Items = decodeItems(response.items)

                    let hasImages = level1Items.prefix(5).contains { $0.image_key != nil }

                    if hasImages {
                        sections.append(StreamingSection(id: itemKey, title: title, items: Array(level1Items.prefix(10)), navigationTitles: [title]))
                    } else {
                        for subItem in level1Items.prefix(4) {
                            guard !Task.isCancelled else {
                                _ = try? await browseService.browse(zoneId: zoneId, popLevels: 2)
                                return
                            }
                            guard let subKey = subItem.item_key, let subTitle = subItem.title else { continue }
                            let sectionTitle = "\(title) — \(subTitle)"
                            let subResponse = try await browseService.browse(zoneId: zoneId, itemKey: subKey)
                            guard !Task.isCancelled else {
                                _ = try? await browseService.browse(zoneId: zoneId, popLevels: 2)
                                return
                            }
                            let level2Items = decodeItems(subResponse.items)
                            if !level2Items.isEmpty {
                                sections.append(StreamingSection(id: subKey, title: sectionTitle, items: Array(level2Items.prefix(10)), navigationTitles: [title, subTitle]))
                            }
                            _ = try await browseService.browse(zoneId: zoneId, popLevels: 1)
                        }
                    }

                    _ = try await browseService.browse(zoneId: zoneId, popLevels: 1)
                } catch {
                    _ = try? await browseService.browse(zoneId: zoneId, popLevels: 1)
                }
            }
            guard !Task.isCancelled else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.streamingSections = sections
                if !sections.isEmpty {
                    self.streamingSectionsCache[cacheKey] = CachedStreamingSections(sections: sections, date: Date())
                    self.saveStreamingSectionsCache()
                }
            }
        }
    }

    /// Restore cached sections for a streaming tab, or clear for fresh fetch.
    func prepareStreamingTabSwitch(tabTitle: String) {
        let cacheKey = "\(browseCategory ?? ""):\(tabTitle)"
        if let cached = streamingSectionsCache[cacheKey],
           !cached.sections.isEmpty,
           Date().timeIntervalSince(cached.date) < Self.streamingSectionsCacheExpiry {
            streamingSections = cached.sections
        } else {
            streamingSections = []
        }
    }

    private func streamingSectionsCacheKey() -> String {
        "\(browseCategory ?? ""):\(browseStack.last ?? "")"
    }

    func browseHome() {
        pendingBrowseKey = nil
        browseStack.removeAll()
        browseCategory = nil
        streamingAlbumDepth = 0
        streamingSections = []
        // Keep old browseResult visible while loading root items
        browseLoading = true
        browse(popAll: true)
    }

    /// Navigate into a streaming carousel item.
    /// Waits for the fetch to finish (session at tab content level),
    /// then re-navigates by matching titles to get fresh item keys.
    func browseStreamingItem(albumTitle: String, sectionTitles: [String]) {
        guard let browseService = browseService else { return }
        let zoneId = currentZone?.zone_id

        currentBrowseTask?.cancel()
        pendingBrowseKey = nil
        browseLoading = true

        let fetchTask = streamingFetchTask

        currentBrowseTask = Task {
            // Wait for fetch to complete (session back at tab content level)
            if fetchTask != nil {
                _ = await fetchTask?.value
            }
            streamingFetchTask = nil
            guard !Task.isCancelled else {
                browseLoading = false
                return
            }

            do {
                let decoder = JSONDecoder()
                func decodeItems(_ dicts: [[String: Any]]) -> [BrowseItem] {
                    dicts.compactMap { dict in
                        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                        return try? decoder.decode(BrowseItem.self, from: data)
                    }
                }

                // Load tab content items with fresh keys
                let tabLoad = try await browseService.load(offset: 0, count: 100)
                guard !Task.isCancelled else { return }
                var currentItems = decodeItems(tabLoad.items)

                // Re-navigate section path by matching titles
                for pathTitle in sectionTitles {
                    guard let match = currentItems.first(where: { $0.title == pathTitle }),
                          let matchKey = match.item_key else {
                        browseLoading = false
                        return
                    }
                    let resp = try await browseService.browse(zoneId: zoneId, itemKey: matchKey)
                    guard !Task.isCancelled else { return }
                    currentItems = decodeItems(resp.items)
                }

                // Find album by title and navigate into it
                guard let album = currentItems.first(where: { $0.title == albumTitle }),
                      let albumKey = album.item_key else {
                    browseLoading = false
                    return
                }

                let response = try await browseService.browse(zoneId: zoneId, itemKey: albumKey)
                guard !Task.isCancelled else { return }
                streamingAlbumDepth = sectionTitles.count + 1
                handleBrowseResponse(response, isPageLoad: false)
            } catch {
                browseLoading = false
            }
        }
    }

    /// Pop back from a streaming album to the tab content level, restoring carousel view.
    func browseBackFromStreamingAlbum() {
        guard streamingAlbumDepth > 0 else { return }
        let levels = streamingAlbumDepth
        streamingAlbumDepth = 0
        // Keep streamingSections cached — carousels restore instantly
        pendingBrowseKey = nil
        browseStack.removeAll()
        browse(popLevels: levels)
    }

    /// Navigate from root into a streaming service, match through section titles, and open an album.
    /// Used by the sidebar streaming tab to switch to the browse section with the album displayed.
    func browseToStreamingAlbum(serviceName: String, albumTitle: String, sectionTitles: [String]) {
        guard let browseService = browseService else { return }
        let zoneId = currentZone?.zone_id

        pendingBrowseKey = nil
        browseStack.removeAll()
        browseCategory = serviceName
        streamingAlbumDepth = 0
        streamingSections = []
        cancelStreamingFetch()
        browseResult = nil
        browseLoading = true

        currentBrowseTask?.cancel()
        currentBrowseTask = Task {
            do {
                let decoder = JSONDecoder()
                func decodeItems(_ dicts: [[String: Any]]) -> [BrowseItem] {
                    dicts.compactMap { dict in
                        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                        return try? decoder.decode(BrowseItem.self, from: data)
                    }
                }

                // Reset to root
                let rootResponse = try await browseService.browse(zoneId: zoneId, popAll: true)
                guard !Task.isCancelled else { return }
                var currentItems = decodeItems(rootResponse.items)

                // Find service at root level
                guard let serviceItem = currentItems.first(where: { $0.title == serviceName }),
                      let serviceKey = serviceItem.item_key else {
                    browseLoading = false
                    return
                }

                let serviceResponse = try await browseService.browse(zoneId: zoneId, itemKey: serviceKey)
                guard !Task.isCancelled else { return }
                currentItems = decodeItems(serviceResponse.items)

                // Auto-navigate into the first tab (same pattern as browseToCategory handler)
                if let firstTab = currentItems.first, let tabKey = firstTab.item_key {
                    let tabResponse = try await browseService.browse(zoneId: zoneId, itemKey: tabKey)
                    guard !Task.isCancelled else { return }
                    currentItems = decodeItems(tabResponse.items)
                }

                // Navigate section path by matching titles
                for pathTitle in sectionTitles {
                    guard let match = currentItems.first(where: { $0.title == pathTitle }),
                          let matchKey = match.item_key else {
                        browseLoading = false
                        return
                    }
                    let resp = try await browseService.browse(zoneId: zoneId, itemKey: matchKey)
                    guard !Task.isCancelled else { return }
                    currentItems = decodeItems(resp.items)
                }

                // Find and open album
                guard let album = currentItems.first(where: { $0.title == albumTitle }),
                      let albumKey = album.item_key else {
                    browseLoading = false
                    return
                }

                let response = try await browseService.browse(zoneId: zoneId, itemKey: albumKey)
                guard !Task.isCancelled else { return }
                // +3 = service + first tab + sectionTitles.count levels + album
                streamingAlbumDepth = sectionTitles.count + 3
                handleBrowseResponse(response, isPageLoad: false)
            } catch {
                browseLoading = false
            }
        }
    }

    /// Navigate to browse root, find the search item, and submit a query.
    /// Results appear in browseResult for RoonBrowseContentView.
    func browseSearch(query: String) {
        guard let browseService = browseService else { return }
        let zoneId = currentZone?.zone_id
        browseLoading = true
        pendingBrowseKey = nil
        browseStack.removeAll()
        browseCategory = nil

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

        cacheImageKeys(from: newItems.map { (title: $0.title, imageKey: $0.image_key) })

        // Queue subscription is already active from selectZone();
        // Roon Core sends queue updates automatically when playback starts.

        if let title = list?.title, let level = list?.level, level > 0 {
            while browseStack.count >= level {
                browseStack.removeLast()
            }
            browseStack.append(title)
        }

        // Auto-trigger streaming sections fetch after tab auto-navigation completes.
        // The view's .onAppear fires too early (before browseStack has the tab title),
        // so we trigger here once we're at the right level.
        if let cat = browseCategory, Self.streamingServiceTitles.contains(cat),
           browseStack.count == 2, streamingSections.isEmpty, streamingAlbumDepth == 0 {
            let sample = newItems.prefix(10)
            let listCount = sample.filter { $0.hint == "list" }.count
            if newItems.count >= 2 && listCount > sample.count / 2 {
                fetchStreamingSections(items: newItems)
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

        cacheImageKeys(from: newItems.map { (title: $0.title, imageKey: $0.image_key) })

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

    // MARK: - Profile Name

    private static let settingsTitles = Set(["Settings", "Paramètres"])
    private static let profileTitles = Set(["Profile", "Profil"])

    /// Fetch the active Roon profile name via the browse "settings" hierarchy.
    func fetchProfileName() {
        Task {
            do {
                let decoder = JSONDecoder()
                let session = RoonBrowseService(connection: connection, sessionKey: "profile")
                let zoneId = currentZone?.zone_id

                // Browse root to find Settings
                let rootResponse = try await session.browse(zoneId: zoneId, popAll: true)
                let rootItems: [BrowseItem] = rootResponse.items.compactMap { dict in
                    guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                    return try? decoder.decode(BrowseItem.self, from: data)
                }

                guard let settingsItem = rootItems.first(where: { Self.settingsTitles.contains($0.title ?? "") }),
                      let settingsKey = settingsItem.item_key else { return }

                // Navigate into Settings
                let settingsResponse = try await session.browse(zoneId: zoneId, itemKey: settingsKey)
                let settingsItems: [BrowseItem] = settingsResponse.items.compactMap { dict in
                    guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                    return try? decoder.decode(BrowseItem.self, from: data)
                }

                // The active profile is shown as subtitle of the "Profile" item
                if let profileItem = settingsItems.first(where: { Self.profileTitles.contains($0.title ?? "") }),
                   let name = profileItem.subtitle, !name.isEmpty {
                    await MainActor.run {
                        self.profileName = name
                    }
                }
            } catch {
                // Profile fetch failed silently — greeting will fall back to macOS username
            }
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
    private static let streamingServiceTitles: Set<String> = ["TIDAL", "Qobuz", "KKBOX", "nugs.net"]

    func fetchSidebarCategories() {
        let zoneId = currentZone?.zone_id

        Task {
            let decoder = JSONDecoder()
            func decodeItems(_ dicts: [[String: Any]]) -> [BrowseItem] {
                dicts.compactMap { dict in
                    guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                    return try? decoder.decode(BrowseItem.self, from: data)
                }
            }

            // Session 1: Browse root → Library → categories
            var libraryItems: [BrowseItem] = []
            do {
                let rootSession = RoonBrowseService(connection: connection, sessionKey: "sidebar")
                let rootResponse = try await rootSession.browse(zoneId: zoneId, popAll: true)
                let rootItems = decodeItems(rootResponse.items)

                if let libItem = rootItems.first(where: { Self.libraryTitles.contains($0.title ?? "") }),
                   let libKey = libItem.item_key {
                    let libResponse = try await rootSession.browse(zoneId: zoneId, itemKey: libKey)
                    libraryItems = decodeItems(libResponse.items)
                }

                var allItems: [BrowseItem] = rootItems.filter {
                    let t = $0.title ?? ""
                    return $0.input_prompt == nil
                        && !Self.libraryTitles.contains(t)
                        && !Self.playlistTitles.contains(t)
                        && !Self.hiddenTitles.contains(t)
                }
                allItems.append(contentsOf: libraryItems.filter { $0.input_prompt == nil })
                self.sidebarCategories = allItems
            } catch {
                // Categories fetch failed, keep cached data
            }

            // Session 2: Browse root → Playlists (separate session, item_keys are session-bound)
            do {
                let plSession = RoonBrowseService(connection: connection, sessionKey: "sidebar_pl")
                let plRoot = try await plSession.browse(zoneId: zoneId, popAll: true)
                let plRootItems = decodeItems(plRoot.items)
                if let plItem = plRootItems.first(where: { Self.playlistTitles.contains($0.title ?? "") }),
                   let plKey = plItem.item_key {
                    let plResponse = try await plSession.browse(zoneId: zoneId, itemKey: plKey)
                    let totalCount = (plResponse.list?["count"] as? Int) ?? 0
                    var playlists = decodeItems(plResponse.items)
                    while playlists.count < totalCount {
                        let more = try await plSession.load(offset: playlists.count, count: 100)
                        let moreItems = decodeItems(more.items)
                        if moreItems.isEmpty { break }
                        playlists.append(contentsOf: moreItems)
                    }
                    self.sidebarPlaylists = playlists
                }
            } catch {
                // Playlists fetch failed, keep cached data
            }

            // Persist to disk for instant display on next launch
            saveSidebarCache()

            // Counts in background (non-blocking — sidebar is already fully populated)
            if !libraryItems.isEmpty {
                Task {
                    do {
                        let countSession = RoonBrowseService(connection: self.connection, sessionKey: "sidebar_counts")
                        let cRoot = try await countSession.browse(zoneId: zoneId, popAll: true)
                        let cRootItems = decodeItems(cRoot.items)
                        guard let libItem = cRootItems.first(where: { Self.libraryTitles.contains($0.title ?? "") }),
                              let libKey = libItem.item_key else { return }
                        let cLib = try await countSession.browse(zoneId: zoneId, itemKey: libKey)
                        let cLibItems = decodeItems(cLib.items)

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
                                _ = try await countSession.browse(zoneId: zoneId, popLevels: 1)
                            } catch {
                                // Count fetch failed for this item, continue
                            }
                        }
                        self.libraryCounts = counts
                    } catch {
                        // Counts fetch failed, non-critical
                    }
                }
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

    func browseToCategory(title: String) {
        guard let browseService = browseService else { return }
        let zoneId = currentZone?.zone_id

        pendingBrowseKey = nil
        browseStack.removeAll()
        browseCategory = title
        streamingAlbumDepth = 0
        streamingSections = []
        cancelStreamingFetch()
        // Clear stale browse result to prevent streamingServiceAutoNav from firing
        // with old items (e.g. library content) before the new response arrives.
        browseResult = nil
        browseLoading = true

        currentBrowseTask?.cancel()
        currentBrowseTask = Task {
            do {
                let decoder = JSONDecoder()

                // Reset to root
                let rootResponse = try await browseService.browse(zoneId: zoneId, popAll: true)
                guard !Task.isCancelled else { return }

                let rootItems: [BrowseItem] = rootResponse.items.compactMap { dict in
                    guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                    return try? decoder.decode(BrowseItem.self, from: data)
                }

                // Try at root level first
                if let item = rootItems.first(where: { $0.title == title }),
                   let key = item.item_key {
                    let response = try await browseService.browse(zoneId: zoneId, itemKey: key)
                    guard !Task.isCancelled else { return }
                    DispatchQueue.main.async { [weak self] in
                        self?.handleBrowseResponse(response, isPageLoad: false)
                    }
                    return
                }

                // Not at root — navigate into Library first (item_key is session-bound)
                if let libItem = rootItems.first(where: { Self.libraryTitles.contains($0.title ?? "") }),
                   let libKey = libItem.item_key {
                    let libResponse = try await browseService.browse(zoneId: zoneId, itemKey: libKey)
                    guard !Task.isCancelled else { return }

                    let libItems: [BrowseItem] = libResponse.items.compactMap { dict in
                        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                        return try? decoder.decode(BrowseItem.self, from: data)
                    }

                    if let item = libItems.first(where: { $0.title == title }),
                       let key = item.item_key {
                        let response = try await browseService.browse(zoneId: zoneId, itemKey: key)
                        guard !Task.isCancelled else { return }
                        DispatchQueue.main.async { [weak self] in
                            self?.handleBrowseResponse(response, isPageLoad: false)
                        }
                        return
                    }
                }

                // Fallback: nothing found
                DispatchQueue.main.async { [weak self] in
                    self?.browseLoading = false
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

        // Signal transition so views dim the old track info immediately
        playbackTransitioning = true

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

    /// Fetch all stations from the internet_radio hierarchy into myLiveRadioStations
    func fetchMyLiveRadioStations() {
        let zoneId = currentZone?.zone_id
        let session = RoonBrowseService(connection: connection, sessionKey: "my_live_radio")
        Task {
            do {
                let result = try await session.browse(hierarchy: "internet_radio", zoneId: zoneId, popAll: true)
                let decoder = JSONDecoder()
                let items: [BrowseItem] = result.items.compactMap { dict in
                    guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                    return try? decoder.decode(BrowseItem.self, from: data)
                }
                self.myLiveRadioStations = items
            } catch {
                // silently fail — stations remain empty
            }
        }
    }

    /// Play a station from My Live Radio by name (stations are at the internet_radio root)
    func playMyLiveRadioStation(stationName: String) {
        guard let zoneId = currentZone?.zone_id else { return }
        currentPlayTask?.cancel()
        let session = RoonBrowseService(connection: connection, sessionKey: "play_radio")
        currentPlayTask = Task {
            do {
                try await playRadioStation(browseService: session, zoneId: zoneId, stationName: stationName)
            } catch {
                // silently fail
            }
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

    /// Browse into an item to find and trigger a play action.
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

        if result.action == "message" { return }

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
        currentPlayTask?.cancel()
        let playSession = RoonBrowseService(connection: connection, sessionKey: "play_item")
        currentPlayTask = Task {
            try? await playBrowseItem(browseService: playSession, zoneId: zoneId, itemKey: itemKey)
        }
    }

    /// Play from the current browse session (item keys are context-dependent within the session).
    /// Drills into the item to find a play action, then pops back to restore the browse view.
    /// Uses the API-reported `level` to pop back precisely — some actions (like "Play From Here")
    /// auto-pop, so we must not blindly count levels pushed.
    func playInCurrentSession(itemKey: String) {
        guard let browseService = browseService else { return }
        guard let zoneId = currentZone?.zone_id else { return }
        let previousTask = currentPlayTask
        previousTask?.cancel()
        let targetLevel = browseResult?.list?.level ?? 0
        currentPlayTask = Task {
            func log(_ msg: String) {
                let line = "[\(Date())] \(msg)\n"
                let path = "/tmp/play_debug.log"
                if let data = line.data(using: .utf8) {
                    if FileManager.default.fileExists(atPath: path) {
                        if let fh = FileHandle(forWritingAtPath: path) {
                            fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
                        }
                    } else {
                        FileManager.default.createFile(atPath: path, contents: data)
                    }
                }
            }

            // Serialize play operations to avoid concurrent browse session mutations
            if previousTask != nil {
                log("Waiting for previous task...")
                _ = await previousTask?.value
            }
            guard !Task.isCancelled else { log("CANCELLED"); return }

            log("START key=\(itemKey) targetLevel=\(targetLevel)")

            var currentLevel = targetLevel
            do {
                // Browse into the track → pushes 1 level (action menu)
                let result = try await browseService.browse(zoneId: zoneId, itemKey: itemKey)
                currentLevel = result.list?["level"] as? Int ?? currentLevel + 1
                log("After browse: level=\(currentLevel) action=\(result.action ?? "nil") items=\(result.items.count)")
                guard !Task.isCancelled else {
                    if currentLevel > targetLevel {
                        _ = try? await browseService.browse(zoneId: zoneId, popLevels: currentLevel - targetLevel)
                    }
                    return
                }

                // Find a play action (prefer "Play From Here" / "Lire a partir d'ici")
                let playAction = result.items.first { item in
                    let hint = item["hint"] as? String ?? ""
                    let t = (item["title"] as? String ?? "").lowercased()
                    return hint == "action" && (t.contains("play from here") || (t.contains("lire") && t.contains("partir")))
                } ?? result.items.first { ($0["hint"] as? String) == "action" }

                // Execute the play action (often auto-pops back to the parent level)
                if let action = playAction, let key = action["item_key"] as? String {
                    let actionTitle = action["title"] as? String ?? "?"
                    let actionResult = try await browseService.browse(zoneId: zoneId, itemKey: key)
                    currentLevel = actionResult.list?["level"] as? Int ?? currentLevel
                    log("After action '\(actionTitle)': level=\(currentLevel)")
                } else {
                    log("No play action found")
                }

                // Only pop if we're still above the target level
                let popNeeded = currentLevel - targetLevel
                log("popNeeded=\(popNeeded) (current=\(currentLevel) target=\(targetLevel))")
                if popNeeded > 0 {
                    let popResult = try await browseService.browse(zoneId: zoneId, popLevels: popNeeded)
                    let afterPop = popResult.list?["level"] as? Int ?? -1
                    log("After pop \(popNeeded): level=\(afterPop)")
                }
            } catch {
                log("ERROR: \(error)")
                if currentLevel > targetLevel {
                    _ = try? await browseService.browse(zoneId: zoneId, popLevels: currentLevel - targetLevel)
                }
            }
            log("END")
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
        browseCategory = nil
        // Keep old browseResult visible while navigating to playlist
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
                let totalCount = (plResponse.list?["count"] as? Int) ?? 0
                self.logPL("Playlists container items: \(plResponse.items.count) / total: \(totalCount)")

                // Find the specific playlist by title, paginating if needed
                var allPlItems = plResponse.items
                while allPlItems.count < totalCount {
                    guard !Task.isCancelled else { return }
                    let more = try await browseService.load(offset: allPlItems.count, count: 100)
                    if more.items.isEmpty { break }
                    allPlItems.append(contentsOf: more.items)
                }

                guard let playlistKey = allPlItems.first(where: {
                    ($0["title"] as? String) == title
                })?["item_key"] as? String else {
                    self.logPL("ERROR: Playlist '\(title)' not found in \(allPlItems.count) items")
                    for (i, item) in allPlItems.prefix(5).enumerated() {
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

    private static let coreIPKey = "roon_core_ip"

    static var savedCoreIP: String? {
        UserDefaults.standard.string(forKey: coreIPKey)
    }

    func saveCoreIP(_ ip: String) {
        let trimmed = ip.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.coreIPKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: Self.coreIPKey)
        }
    }

    func connectCore(ip: String) {
        saveCoreIP(ip)
        // Clear stale token to force fresh registration
        RoonRegistration.clearToken()
        // Reset state synchronously
        isConnected = false
        zones = []
        currentZone = nil
        zonesById = [:]
        connectionState = .connecting

        // Initialize services
        transportService = RoonTransportService(connection: connection)
        browseService = RoonBrowseService(connection: connection)
        imageService = RoonImageService(connection: connection)

        isConnected = true

        // Disconnect then connect sequentially in one Task
        Task {
            await connection.disconnect()
            await RoonImageProvider.shared.setImageService(imageService)
            await LocalImageServer.shared.start()

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

            await connection.connectDirect(host: ip, port: 9330)
        }
    }

    // MARK: - Image URL & Prefetch

    /// In-memory decoded image cache for instant rendering (bypasses AsyncImage HTTP round-trip)
    private let prefetchedImages = NSCache<NSString, NSImage>()
    private var prefetchTask: Task<Void, Never>?

    func imageURL(key: String?, width: Int = 300, height: Int = 300) -> URL? {
        guard let key = key else { return nil }
        return LocalImageServer.imageURL(key: key, width: width, height: height)
    }

    /// Return a pre-fetched NSImage if available (synchronous, no await).
    func cachedImage(key: String?, width: Int, height: Int) -> NSImage? {
        guard let key = key else { return nil }
        let cacheKey = RoonImageCache.cacheKey(imageKey: key, width: width, height: height) as NSString
        return prefetchedImages.object(forKey: cacheKey)
    }

    /// Pre-fetch images into memory so they render instantly when rows appear.
    func prefetchImages(keys: [String?], width: Int, height: Int) {
        prefetchTask?.cancel()
        prefetchTask = Task {
            for key in keys {
                guard !Task.isCancelled else { return }
                guard let key = key else { continue }
                let cacheKey = RoonImageCache.cacheKey(imageKey: key, width: width, height: height) as NSString
                // Skip if already in memory
                if prefetchedImages.object(forKey: cacheKey) != nil { continue }
                // Fetch via provider (hits RoonImageCache disk/memory, or Roon Core)
                if let data = await RoonImageProvider.shared.fetchImage(key: key, width: width, height: height),
                   let img = NSImage(data: data) {
                    prefetchedImages.setObject(img, forKey: cacheKey)
                }
            }
        }
    }

    /// Resolve image key for now_playing, with queue fallbacks
    func resolvedImageKey(for np: NowPlaying) -> String? {
        if let key = np.image_key { return key }
        let title = np.three_line?.line1 ?? np.one_line?.line1
        // 1. Look up from persistent cache
        if let title = title, let key = trackImageKeyCache[title] { return key }
        // 2. Search current queue items
        if let title = title {
            let match = queueItems.first {
                ($0.three_line?.line1 ?? $0.one_line?.line1) == title
            }
            if let key = match?.image_key { return key }
        }
        // 3. Last resort: first queue item (likely current track)
        return queueItems.first?.image_key
    }

    /// Generic image key resolution: returns imageKey if non-nil (and caches it),
    /// otherwise looks up the persistent cache by title. Used by all views.
    func resolvedImageKey(title: String?, imageKey: String?) -> String? {
        if let key = imageKey {
            // Feed the cache while we're at it
            if let title = title, trackImageKeyCache[title] != key {
                trackImageKeyCache[title] = key
                saveImageKeyCache()
            }
            return key
        }
        if let title = title, let cached = trackImageKeyCache[title] {
            return cached
        }
        return nil
    }

    /// Populate the image key cache from a list of (title, imageKey) pairs
    private func cacheImageKeys(from items: [(title: String?, imageKey: String?)]) {
        var changed = false
        for item in items {
            if let title = item.title, let key = item.imageKey,
               trackImageKeyCache[title] != key {
                trackImageKeyCache[title] = key
                changed = true
            }
        }
        if changed { saveImageKeyCache() }
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
            image_key: resolvedImageKey(for: np),
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
            cacheImageKeys(from: items.map { (title: $0.title, imageKey: $0.image_key) })
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

    // MARK: - Streaming Sections Cache Persistence

    private func loadStreamingSectionsCache() {
        guard let dir = storageDir else { return }
        let path = dir.appendingPathComponent(Self.streamingSectionsCacheFile)
        guard let data = try? Data(contentsOf: path) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let cache = try? decoder.decode([String: CachedStreamingSections].self, from: data) {
            // Filter out expired entries
            let now = Date()
            streamingSectionsCache = cache.filter { now.timeIntervalSince($0.value.date) < Self.streamingSectionsCacheExpiry }
        }
    }

    private func saveStreamingSectionsCache() {
        guard let dir = storageDir else { return }
        let path = dir.appendingPathComponent(Self.streamingSectionsCacheFile)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(streamingSectionsCache) {
            try? data.write(to: path)
        }
        streamingCacheVersion += 1
    }

    /// Returns cached streaming sections for a given service, excluding expired entries.
    func cachedStreamingSectionsForService(_ serviceName: String) -> [StreamingSection] {
        let prefix = "\(serviceName):"
        let now = Date()
        return streamingSectionsCache
            .filter { $0.key.hasPrefix(prefix) && now.timeIntervalSince($0.value.date) < Self.streamingSectionsCacheExpiry }
            .sorted { $0.key < $1.key }
            .flatMap { $0.value.sections }
    }

    // MARK: - Sidebar Cache Persistence

    private func loadSidebarCache() {
        guard let dir = storageDir else { return }
        let path = dir.appendingPathComponent(Self.sidebarCacheFile)
        guard let data = try? Data(contentsOf: path) else { return }
        if let cached = try? JSONDecoder().decode(CachedSidebar.self, from: data) {
            sidebarCategories = cached.categories
            sidebarPlaylists = cached.playlists
        }
    }

    private func saveSidebarCache() {
        guard let dir = storageDir else { return }
        let path = dir.appendingPathComponent(Self.sidebarCacheFile)
        let cached = CachedSidebar(categories: sidebarCategories, playlists: sidebarPlaylists)
        if let data = try? JSONEncoder().encode(cached) {
            try? data.write(to: path)
        }
    }

    // MARK: - Streaming Services Pre-fetch

    func prefetchStreamingServices() {
        prefetchStreamingTask?.cancel()
        prefetchStreamingTask = Task {
            // Wait for sidebar categories to be populated by fetchSidebarCategories()
            for _ in 0..<20 {
                if !sidebarCategories.isEmpty || Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            guard !Task.isCancelled, !sidebarCategories.isEmpty else { return }

            let services = sidebarCategories.compactMap(\.title).filter {
                Self.streamingServiceTitles.contains($0)
            }
            guard !services.isEmpty else { return }

            let zoneId = currentZone?.zone_id

            for serviceName in services {
                guard !Task.isCancelled else { return }

                // Skip if all cached entries for this service are still valid
                let servicePrefix = "\(serviceName):"
                let cachedEntries = streamingSectionsCache.filter { $0.key.hasPrefix(servicePrefix) }
                if !cachedEntries.isEmpty &&
                   cachedEntries.allSatisfy({ Date().timeIntervalSince($0.value.date) < Self.streamingSectionsCacheExpiry }) {
                    continue
                }

                await prefetchServiceSections(serviceName: serviceName, zoneId: zoneId)
            }

            guard !Task.isCancelled else { return }
            saveStreamingSectionsCache()
        }
    }

    private func prefetchServiceSections(serviceName: String, zoneId: String?) async {
        let session = RoonBrowseService(connection: connection, sessionKey: "prefetch_\(serviceName.lowercased())")
        let decoder = JSONDecoder()

        func decodeItems(_ dicts: [[String: Any]]) -> [BrowseItem] {
            dicts.compactMap { dict in
                guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                return try? decoder.decode(BrowseItem.self, from: data)
            }
        }

        do {
            // Browse root
            let rootResponse = try await session.browse(zoneId: zoneId, popAll: true)
            let rootItems = decodeItems(rootResponse.items)
            guard !Task.isCancelled else { return }

            // Find service at root level or inside Library
            var serviceKey: String?
            if let item = rootItems.first(where: { $0.title == serviceName }) {
                serviceKey = item.item_key
            } else if let libItem = rootItems.first(where: { Self.libraryTitles.contains($0.title ?? "") }),
                      let libKey = libItem.item_key {
                let libResponse = try await session.browse(zoneId: zoneId, itemKey: libKey)
                let libItems = decodeItems(libResponse.items)
                serviceKey = libItems.first(where: { $0.title == serviceName })?.item_key
            }

            guard let serviceKey = serviceKey, !Task.isCancelled else {
                return
            }

            // Navigate into service → get tabs
            let tabsResponse = try await session.browse(zoneId: zoneId, itemKey: serviceKey)
            let tabs = decodeItems(tabsResponse.items)
            guard !Task.isCancelled else { return }

            // Only process tabs with non-empty titles (skip search/action items with empty titles)
            let navigableTabs = tabs.filter { $0.title != nil && !$0.title!.isEmpty && $0.item_key != nil }
            for tab in navigableTabs {
                guard !Task.isCancelled else { return }
                guard let tabKey = tab.item_key, let tabTitle = tab.title else { continue }

                let cacheKey = "\(serviceName):\(tabTitle)"

                // Skip if this tab's cache is still valid
                if let cached = streamingSectionsCache[cacheKey],
                   Date().timeIntervalSince(cached.date) < Self.streamingSectionsCacheExpiry {
                    continue
                }

                // Navigate into tab
                let tabContent = try await session.browse(zoneId: zoneId, itemKey: tabKey)
                let tabItems = decodeItems(tabContent.items)
                guard !Task.isCancelled else {
                    _ = try? await session.browse(zoneId: zoneId, popLevels: 1)
                    return
                }

                var sections: [StreamingSection] = []

                for subItem in tabItems {
                    guard !Task.isCancelled else {
                        _ = try? await session.browse(zoneId: zoneId, popLevels: 1)
                        return
                    }
                    guard let subKey = subItem.item_key, let subTitle = subItem.title else { continue }

                    let subResponse = try await session.browse(zoneId: zoneId, itemKey: subKey)
                    let subItems = decodeItems(subResponse.items)
                    guard !Task.isCancelled else {
                        _ = try? await session.browse(zoneId: zoneId, popLevels: 2)
                        return
                    }

                    let hasImages = subItems.prefix(5).contains { $0.image_key != nil }

                    if hasImages {
                        sections.append(StreamingSection(
                            id: subKey,
                            title: subTitle,
                            items: Array(subItems.prefix(10)),
                            navigationTitles: [subTitle]
                        ))
                    } else {
                        for subSubItem in subItems.prefix(4) {
                            guard !Task.isCancelled else {
                                _ = try? await session.browse(zoneId: zoneId, popLevels: 2)
                                return
                            }
                            guard let subSubKey = subSubItem.item_key,
                                  let subSubTitle = subSubItem.title else { continue }
                            let sectionTitle = "\(subTitle) — \(subSubTitle)"
                            let subSubResponse = try await session.browse(zoneId: zoneId, itemKey: subSubKey)
                            let level2Items = decodeItems(subSubResponse.items)
                            guard !Task.isCancelled else {
                                _ = try? await session.browse(zoneId: zoneId, popLevels: 2)
                                return
                            }
                            if !level2Items.isEmpty {
                                sections.append(StreamingSection(
                                    id: subSubKey,
                                    title: sectionTitle,
                                    items: Array(level2Items.prefix(10)),
                                    navigationTitles: [subTitle, subSubTitle]
                                ))
                            }
                            _ = try await session.browse(zoneId: zoneId, popLevels: 1)
                        }
                    }

                    _ = try await session.browse(zoneId: zoneId, popLevels: 1)
                }

                if !sections.isEmpty {
                    streamingSectionsCache[cacheKey] = CachedStreamingSections(sections: sections, date: Date())
                }

                // Pop back to tabs level
                _ = try await session.browse(zoneId: zoneId, popLevels: 1)
            }
        } catch {
            // Prefetch failed silently — will retry on next connection
        }
    }

    // MARK: - Image Key Cache Persistence

    private static let imageKeyCacheFile = "track_image_keys.json"

    private static func loadImageKeyCache(from dir: URL?) -> [String: String] {
        guard let dir = dir else { return [:] }
        let path = dir.appendingPathComponent(imageKeyCacheFile)
        guard let data = try? Data(contentsOf: path),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }

    private func saveImageKeyCache() {
        guard let dir = storageDir else { return }
        let path = dir.appendingPathComponent(Self.imageKeyCacheFile)
        if let data = try? JSONEncoder().encode(trackImageKeyCache) {
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
            image_key: resolvedImageKey(for: np),
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
            cacheImageKeys(from: items.map { (title: $0.title, imageKey: $0.image_key) })
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
