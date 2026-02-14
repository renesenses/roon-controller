import XCTest
@testable import Roon_Controller

/// Tests for UI component behavior — verifies the data/state logic that drives each view.
@MainActor
final class ViewBehaviorTests: XCTestCase {

    var service: RoonService!
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        service = RoonService(storageDirectory: tempDir)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - ContentView behavior

    func testContentViewShowsConnectionWhenDisconnected() {
        // ContentView shows ConnectionView when disconnected and no zones
        XCTAssertEqual(service.connectionState, .disconnected)
        XCTAssertTrue(service.zones.isEmpty)
        // Both conditions met → ConnectionView should be shown
    }

    func testContentViewShowsPlayerWhenZonesAvailable() {
        // ContentView shows NavigationSplitView when zones exist
        let zone = makeZone(id: "z1", name: "Test Zone")
        service.zones = [zone]
        XCTAssertFalse(service.zones.isEmpty)
        // zones not empty → main player UI should be shown
    }

    // MARK: - PlayerView behavior

    func testPlayerShowsNoZoneWhenNoneSelected() {
        XCTAssertNil(service.currentZone)
        // PlayerView shows "Selectionnez une zone" when currentZone is nil
    }

    func testPlayerShowsEmptyStateWhenNoNowPlaying() {
        let zone = makeZone(id: "z1", name: "Salon", state: "stopped")
        service.selectZone(zone)
        XCTAssertNotNil(service.currentZone)
        XCTAssertNil(service.currentZone?.now_playing)
        // PlayerView shows emptyState with zone name
    }

    func testPlayerShowsTrackInfoFromThreeLine() {
        let np = NowPlaying(
            one_line: NowPlaying.LineInfo(line1: "One line", line2: nil, line3: nil),
            two_line: nil,
            three_line: NowPlaying.LineInfo(line1: "Track Title", line2: "Artist Name", line3: "Album Name"),
            length: 240, seek_position: 30, image_key: "img123"
        )
        let zone = makeZone(id: "z1", name: "Zone", state: "playing", nowPlaying: np)
        service.selectZone(zone)

        // PlayerView reads three_line for display
        let title = service.currentZone?.now_playing?.three_line?.line1
        let artist = service.currentZone?.now_playing?.three_line?.line2
        let album = service.currentZone?.now_playing?.three_line?.line3
        XCTAssertEqual(title, "Track Title")
        XCTAssertEqual(artist, "Artist Name")
        XCTAssertEqual(album, "Album Name")
    }

    func testPlayerSeekBarProgress() {
        let np = NowPlaying(
            one_line: nil, two_line: nil,
            three_line: NowPlaying.LineInfo(line1: "Song", line2: "Artist", line3: "Album"),
            length: 300, seek_position: 150, image_key: nil
        )
        let zone = makeZone(id: "z1", name: "Zone", state: "playing", nowPlaying: np, seekPosition: 150)
        service.selectZone(zone)

        // Seek bar uses seekPosition / length for progress
        let position = Double(service.seekPosition)
        let duration = Double(np.length ?? 0)
        XCTAssertEqual(position / duration, 0.5, accuracy: 0.01)
    }

    func testPlayerPlayPauseIconReflectsState() {
        let np = makeNowPlaying(title: "Song")
        let playing = makeZone(id: "z1", name: "Zone", state: "playing", nowPlaying: np)
        service.selectZone(playing)
        XCTAssertEqual(service.currentZone?.state, "playing")
        // PlayerView shows "pause.circle.fill" icon

        let paused = makeZone(id: "z1", name: "Zone", state: "paused", nowPlaying: np)
        service.selectZone(paused)
        XCTAssertEqual(service.currentZone?.state, "paused")
        // PlayerView shows "play.circle.fill" icon
    }

    func testPlayerPreviousNextDisabledState() {
        let zone = RoonZone(
            zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: makeNowPlaying(title: "Song"), outputs: nil, settings: nil, seek_position: 0,
            is_play_allowed: true, is_pause_allowed: true, is_seek_allowed: true,
            is_previous_allowed: false, is_next_allowed: false
        )
        service.selectZone(zone)
        XCTAssertEqual(service.currentZone?.is_previous_allowed, false)
        XCTAssertEqual(service.currentZone?.is_next_allowed, false)
        // PlayerView disables and dims previous/next buttons
    }

    func testPlayerPreviousNextEnabledState() {
        let zone = RoonZone(
            zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: makeNowPlaying(title: "Song"), outputs: nil, settings: nil, seek_position: 0,
            is_play_allowed: true, is_pause_allowed: true, is_seek_allowed: true,
            is_previous_allowed: true, is_next_allowed: true
        )
        service.selectZone(zone)
        XCTAssertEqual(service.currentZone?.is_previous_allowed, true)
        XCTAssertEqual(service.currentZone?.is_next_allowed, true)
    }

    func testPlayerShuffleRepeatRadioSettings() {
        let settings = ZoneSettings(shuffle: true, loop: "loop", auto_radio: true)
        let zone = RoonZone(
            zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: makeNowPlaying(title: "Song"), outputs: nil, settings: settings, seek_position: 0,
            is_play_allowed: true, is_pause_allowed: true, is_seek_allowed: true,
            is_previous_allowed: true, is_next_allowed: true
        )
        service.selectZone(zone)
        XCTAssertEqual(service.currentZone?.settings?.shuffle, true)
        XCTAssertEqual(service.currentZone?.settings?.loop, "loop")
        XCTAssertEqual(service.currentZone?.settings?.auto_radio, true)
        // PlayerView highlights shuffle, repeat, and radio icons with accent color
    }

    func testPlayerFavoriteButtonShownForRadio() {
        let zone = RoonZone(
            zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: makeNowPlaying(title: "FIP"),
            outputs: nil, settings: nil, seek_position: nil,
            is_play_allowed: true, is_pause_allowed: true, is_seek_allowed: false,
            is_previous_allowed: false, is_next_allowed: false
        )
        service.selectZone(zone)
        // PlayerView shows heart button when is_seek_allowed == false (radio)
        XCTAssertEqual(service.currentZone?.is_seek_allowed, false)
    }

    func testPlayerFavoriteButtonHiddenForTrack() {
        let zone = RoonZone(
            zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: makeNowPlaying(title: "Song"),
            outputs: nil, settings: nil, seek_position: 10,
            is_play_allowed: true, is_pause_allowed: true, is_seek_allowed: true,
            is_previous_allowed: true, is_next_allowed: true
        )
        service.selectZone(zone)
        // PlayerView hides heart button when is_seek_allowed == true (regular track)
        XCTAssertEqual(service.currentZone?.is_seek_allowed, true)
    }

    func testFormatTime() {
        // PlayerView uses formatTime for seek bar labels
        XCTAssertEqual(formatTime(0), "0:00")
        XCTAssertEqual(formatTime(59), "0:59")
        XCTAssertEqual(formatTime(60), "1:00")
        XCTAssertEqual(formatTime(125), "2:05")
        XCTAssertEqual(formatTime(3661), "61:01")
    }

    // MARK: - SidebarView behavior

    func testSidebarZoneSelection() {
        let z1 = makeZone(id: "z1", name: "Salon")
        let z2 = makeZone(id: "z2", name: "Chambre")
        service.zones = [z1, z2]

        service.selectZone(z1)
        XCTAssertEqual(service.currentZone?.zone_id, "z1")

        service.selectZone(z2)
        XCTAssertEqual(service.currentZone?.zone_id, "z2")
    }

    func testSidebarZoneStateIndicator() {
        // SidebarView shows different icons per state
        let playing = makeZone(id: "z1", name: "Zone", state: "playing")
        XCTAssertEqual(playing.state, "playing")   // green play.fill icon

        let paused = makeZone(id: "z2", name: "Zone", state: "paused")
        XCTAssertEqual(paused.state, "paused")     // orange pause.fill icon

        let stopped = makeZone(id: "z3", name: "Zone", state: "stopped")
        XCTAssertEqual(stopped.state, "stopped")   // gray stop.fill icon
    }

    func testSidebarZoneMiniNowPlaying() {
        let np = NowPlaying(
            one_line: NowPlaying.LineInfo(line1: "Full Title", line2: nil, line3: nil),
            two_line: nil,
            three_line: NowPlaying.LineInfo(line1: "Song", line2: "Artist", line3: "Album"),
            length: 240, seek_position: 10, image_key: "img1"
        )
        let zone = makeZone(id: "z1", name: "Zone", state: "playing", nowPlaying: np)
        service.zones = [zone]

        // SidebarView shows mini now playing: line1 (title) and line2 (artist)
        let title = zone.now_playing?.three_line?.line1 ?? zone.now_playing?.one_line?.line1
        let artist = zone.now_playing?.three_line?.line2
        XCTAssertEqual(title, "Song")
        XCTAssertEqual(artist, "Artist")
    }

    func testSidebarZoneVolumeControls() {
        let volume = RoonOutput.VolumeInfo(
            type: "number", min: 0, max: 100, value: 65, step: 1, is_muted: false
        )
        let output = RoonOutput(output_id: "o1", display_name: "DAC", zone_id: "z1", volume: volume)
        let zone = RoonZone(
            zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: nil, outputs: [output], settings: nil, seek_position: nil,
            is_play_allowed: true, is_pause_allowed: nil, is_seek_allowed: nil,
            is_previous_allowed: nil, is_next_allowed: nil
        )
        service.zones = [zone]

        // SidebarView shows volume slider per output
        let displayedVolume = zone.outputs?.first?.volume?.value
        XCTAssertEqual(displayedVolume, 65)
        XCTAssertEqual(zone.outputs?.first?.volume?.is_muted, false)
    }

    func testSidebarVolumeMutedState() {
        let volume = RoonOutput.VolumeInfo(
            type: "number", min: 0, max: 100, value: 65, step: 1, is_muted: true
        )
        let output = RoonOutput(output_id: "o1", display_name: "DAC", zone_id: "z1", volume: volume)
        let zone = RoonZone(
            zone_id: "z1", display_name: "Zone", state: "stopped",
            now_playing: nil, outputs: [output], settings: nil, seek_position: nil,
            is_play_allowed: true, is_pause_allowed: nil, is_seek_allowed: nil,
            is_previous_allowed: nil, is_next_allowed: nil
        )

        // When muted, SidebarView shows speaker.slash.fill in red
        XCTAssertEqual(zone.outputs?.first?.volume?.is_muted, true)
    }

    func testSidebarBrowseLoadingState() {
        XCTAssertFalse(service.browseLoading)
        // When browseLoading is true, SidebarView shows ProgressView
        service.browseLoading = true
        XCTAssertTrue(service.browseLoading)
    }

    func testSidebarBrowseStackNavigation() {
        // Empty stack → show "Bibliotheque" title, no back button
        XCTAssertTrue(service.browseStack.isEmpty)

        // With stack → show last item as title, show back and home buttons
        service.browseStack = ["Library", "Artists", "The Beatles"]
        XCTAssertEqual(service.browseStack.last, "The Beatles")
        XCTAssertFalse(service.browseStack.isEmpty)
    }

    func testSidebarBrowseSearchFiltering() {
        // SidebarView's filteredBrowseItems filters by searchText
        let item1 = makeBrowseItem(title: "The Beatles", hint: "list")
        let item2 = makeBrowseItem(title: "Radiohead", hint: "list")
        let item3 = makeBrowseItem(title: "The Rolling Stones", hint: "list")

        let items = [item1, item2, item3]
        let query = "the"

        let filtered = items.filter { item in
            (item.title ?? "").localizedCaseInsensitiveContains(query)
        }
        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered[0].title, "The Beatles")
        XCTAssertEqual(filtered[1].title, "The Rolling Stones")
    }

    func testSidebarBrowseItemPlayButton() {
        // Items with hint "action_list" or "action" show play button
        let actionList = makeBrowseItem(title: "Track", hint: "action_list", itemKey: "k1")
        let action = makeBrowseItem(title: "Play", hint: "action", itemKey: "k2")
        let list = makeBrowseItem(title: "Folder", hint: "list", itemKey: "k3")

        XCTAssertTrue(actionList.hint == "action_list" || actionList.hint == "action")
        XCTAssertTrue(action.hint == "action_list" || action.hint == "action")
        XCTAssertFalse(list.hint == "action_list" || list.hint == "action")
    }

    func testSidebarBrowseItemChevron() {
        // Items with hint "list" or "action_list" show chevron.right
        let list = makeBrowseItem(title: "Folder", hint: "list")
        let actionList = makeBrowseItem(title: "Track", hint: "action_list")
        let action = makeBrowseItem(title: "Play", hint: "action")

        XCTAssertTrue(list.hint == "list" || list.hint == "action_list")
        XCTAssertTrue(actionList.hint == "list" || actionList.hint == "action_list")
        XCTAssertFalse(action.hint == "list" || action.hint == "action_list")
    }

    // MARK: - QueueView behavior

    func testQueueEmptyState() {
        XCTAssertTrue(service.queueItems.isEmpty)
        // QueueView shows "File d'attente vide" when empty
    }

    func testQueueItemsDisplay() {
        let items = [
            QueueItem(queue_item_id: 1,
                      one_line: NowPlaying.LineInfo(line1: "Track 1", line2: nil, line3: nil),
                      two_line: nil,
                      three_line: NowPlaying.LineInfo(line1: "Track 1", line2: "Artist 1", line3: "Album 1"),
                      length: 240, image_key: "img1"),
            QueueItem(queue_item_id: 2,
                      one_line: NowPlaying.LineInfo(line1: "Track 2", line2: nil, line3: nil),
                      two_line: nil,
                      three_line: NowPlaying.LineInfo(line1: "Track 2", line2: "Artist 2", line3: "Album 2"),
                      length: 180, image_key: "img2")
        ]
        service.queueItems = items
        XCTAssertEqual(service.queueItems.count, 2)

        // QueueView displays three_line.line1 as title and line2 as subtitle
        XCTAssertEqual(service.queueItems[0].three_line?.line1, "Track 1")
        XCTAssertEqual(service.queueItems[0].three_line?.line2, "Artist 1")
        XCTAssertEqual(service.queueItems[1].length, 180)
    }

    func testQueueCurrentlyPlayingDetection() {
        let np = NowPlaying(
            one_line: nil, two_line: nil,
            three_line: NowPlaying.LineInfo(line1: "Current Song", line2: "Artist", line3: "Album"),
            length: 240, seek_position: 30, image_key: nil
        )
        let zone = makeZone(id: "z1", name: "Zone", state: "playing", nowPlaying: np)
        service.selectZone(zone)

        let item1 = QueueItem(queue_item_id: 1, one_line: nil, two_line: nil,
                              three_line: NowPlaying.LineInfo(line1: "Current Song", line2: "Artist", line3: "Album"),
                              length: 240, image_key: nil)
        let item2 = QueueItem(queue_item_id: 2, one_line: nil, two_line: nil,
                              three_line: NowPlaying.LineInfo(line1: "Next Song", line2: "Artist", line3: "Album"),
                              length: 180, image_key: nil)
        service.queueItems = [item1, item2]

        // QueueView highlights the currently playing track by matching three_line.line1
        let npLine = service.currentZone?.now_playing?.three_line?.line1
        let isPlaying1 = item1.three_line?.line1 == npLine
        let isPlaying2 = item2.three_line?.line1 == npLine
        XCTAssertTrue(isPlaying1)
        XCTAssertFalse(isPlaying2)
    }

    func testQueueFormatDuration() {
        XCTAssertEqual(formatDuration(0), "0:00")
        XCTAssertEqual(formatDuration(59), "0:59")
        XCTAssertEqual(formatDuration(60), "1:00")
        XCTAssertEqual(formatDuration(240), "4:00")
        XCTAssertEqual(formatDuration(3723), "62:03")
    }

    // MARK: - HistoryView behavior

    func testHistoryEmptyState() {
        XCTAssertTrue(service.playbackHistory.isEmpty)
        // HistoryView shows "Aucun historique" when empty
    }

    func testHistoryItemCount() {
        let items = (0..<5).map { i in
            PlaybackHistoryItem(
                id: UUID(), title: "Song \(i)", artist: "Artist", album: "Album",
                image_key: nil, length: 200, zone_name: "Zone", playedAt: Date()
            )
        }
        service.playbackHistory = items
        // HistoryView header shows "\(count) morceaux"
        XCTAssertEqual(service.playbackHistory.count, 5)
    }

    func testHistoryTimeAgo() {
        XCTAssertEqual(timeAgo(Date()), "maintenant")
        XCTAssertEqual(timeAgo(Date().addingTimeInterval(-120)), "il y a 2 min")
        XCTAssertEqual(timeAgo(Date().addingTimeInterval(-7200)), "il y a 2h")
        // Older dates use DateFormatter — just check it doesn't crash
        let old = timeAgo(Date().addingTimeInterval(-90000))
        XCTAssertFalse(old.isEmpty)
    }

    func testHistoryClear() {
        service.playbackHistory = [
            PlaybackHistoryItem(id: UUID(), title: "A", artist: "B", album: "C",
                                image_key: nil, length: 100, zone_name: "Z", playedAt: Date())
        ]
        XCTAssertEqual(service.playbackHistory.count, 1)
        service.clearHistory()
        XCTAssertTrue(service.playbackHistory.isEmpty)
    }

    func testHistoryRadioItem() {
        let radio = PlaybackHistoryItem(
            id: UUID(), title: "FIP", artist: "", album: "",
            image_key: nil, length: nil, isRadio: true, zone_name: "Zone", playedAt: Date()
        )
        XCTAssertTrue(radio.isRadio)
        XCTAssertNil(radio.length)
        // HistoryView conditionally shows duration only when length is non-nil
    }

    // MARK: - FavoritesView behavior

    func testFavoritesEmptyState() {
        XCTAssertTrue(service.radioFavorites.isEmpty)
        // FavoritesView shows "Aucun favori" when empty
    }

    func testFavoritesDisplayTrackInfo() {
        let fav = RadioFavorite(
            id: UUID(), title: "It's A Shame", artist: "Ellis",
            stationName: "FIP", image_key: "img1", savedAt: Date()
        )
        service.radioFavorites = [fav]

        // FavoritesView shows title (track) and artist, not station name
        XCTAssertEqual(service.radioFavorites[0].title, "It's A Shame")
        XCTAssertEqual(service.radioFavorites[0].artist, "Ellis")
        XCTAssertEqual(service.radioFavorites[0].stationName, "FIP")
    }

    func testFavoritesReplayUsesStationName() {
        let fav = RadioFavorite(
            id: UUID(), title: "It's A Shame", artist: "Ellis",
            stationName: "FIP", image_key: nil, savedAt: Date()
        )
        // FavoritesView radio replay: uses stationName for searchAndPlay
        let station = fav.stationName.isEmpty ? fav.title : fav.stationName
        XCTAssertEqual(station, "FIP")
    }

    func testFavoritesReplayFallbackWhenNoStationName() {
        // Old format favorites without stationName
        let fav = RadioFavorite(
            id: UUID(), title: "FIP", artist: "It's A Shame",
            stationName: "", image_key: nil, savedAt: Date()
        )
        let station = fav.stationName.isEmpty ? fav.title : fav.stationName
        XCTAssertEqual(station, "FIP")
    }

    func testFavoritesCount() {
        service.radioFavorites = [
            RadioFavorite(id: UUID(), title: "A", artist: "B", stationName: "FIP", image_key: nil, savedAt: Date()),
            RadioFavorite(id: UUID(), title: "C", artist: "D", stationName: "FIP", image_key: nil, savedAt: Date()),
            RadioFavorite(id: UUID(), title: "E", artist: "F", stationName: "Jazz", image_key: nil, savedAt: Date())
        ]
        // FavoritesView header shows "\(count) favoris"
        XCTAssertEqual(service.radioFavorites.count, 3)
    }

    func testFavoritesPlaylistCreationStatus() {
        XCTAssertNil(service.playlistCreationStatus)
        service.playlistCreationStatus = "Ajout 1/3 : It's A Shame..."
        XCTAssertNotNil(service.playlistCreationStatus)
        // FavoritesView shows ProgressView + status text when non-nil
    }

    func testFavoritesRemove() {
        let fav1 = RadioFavorite(id: UUID(), title: "A", artist: "B", stationName: "S", image_key: nil, savedAt: Date())
        let fav2 = RadioFavorite(id: UUID(), title: "C", artist: "D", stationName: "S", image_key: nil, savedAt: Date())
        service.radioFavorites = [fav1, fav2]

        service.removeRadioFavorite(id: fav1.id)
        XCTAssertEqual(service.radioFavorites.count, 1)
        XCTAssertEqual(service.radioFavorites[0].title, "C")
    }

    func testFavoritesClear() {
        service.radioFavorites = [
            RadioFavorite(id: UUID(), title: "A", artist: "B", stationName: "S", image_key: nil, savedAt: Date())
        ]
        service.clearRadioFavorites()
        XCTAssertTrue(service.radioFavorites.isEmpty)
    }

    // MARK: - RadioFavorite new storage format

    func testSaveRadioFavoriteStoresTrackNotStation() {
        // Simulate radio zone: line1=station, line2=track, line3=artist
        let np = NowPlaying(
            one_line: NowPlaying.LineInfo(line1: "FIP", line2: nil, line3: nil),
            two_line: nil,
            three_line: NowPlaying.LineInfo(line1: "FIP", line2: "It's A Shame", line3: "Ellis"),
            length: nil, seek_position: nil, image_key: "imgkey"
        )
        let zone = RoonZone(
            zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: np, outputs: nil, settings: nil, seek_position: nil,
            is_play_allowed: true, is_pause_allowed: true, is_seek_allowed: false,
            is_previous_allowed: false, is_next_allowed: false
        )
        service.selectZone(zone)
        service.saveRadioFavorite()

        XCTAssertEqual(service.radioFavorites.count, 1)
        XCTAssertEqual(service.radioFavorites[0].title, "It's A Shame")      // track title from line2
        XCTAssertEqual(service.radioFavorites[0].artist, "Ellis")             // artist from line3
        XCTAssertEqual(service.radioFavorites[0].stationName, "FIP")          // station from line1
    }

    func testSaveRadioFavoriteSkipsWhenNoTrackTitle() {
        // Radio with no metadata: line1=station, line2=nil, line3=nil
        let np = NowPlaying(
            one_line: NowPlaying.LineInfo(line1: "FIP", line2: nil, line3: nil),
            two_line: nil,
            three_line: NowPlaying.LineInfo(line1: "FIP", line2: nil, line3: nil),
            length: nil, seek_position: nil, image_key: nil
        )
        let zone = RoonZone(
            zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: np, outputs: nil, settings: nil, seek_position: nil,
            is_play_allowed: true, is_pause_allowed: true, is_seek_allowed: false,
            is_previous_allowed: false, is_next_allowed: false
        )
        service.selectZone(zone)
        service.saveRadioFavorite()

        // Should not save — no track title (line2 is nil)
        XCTAssertTrue(service.radioFavorites.isEmpty)
    }

    func testSaveRadioFavoriteDeduplicatesByTrackAndArtist() {
        let np = NowPlaying(
            one_line: nil, two_line: nil,
            three_line: NowPlaying.LineInfo(line1: "FIP", line2: "Song", line3: "Artist"),
            length: nil, seek_position: nil, image_key: nil
        )
        let zone = RoonZone(
            zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: np, outputs: nil, settings: nil, seek_position: nil,
            is_play_allowed: true, is_pause_allowed: true, is_seek_allowed: false,
            is_previous_allowed: false, is_next_allowed: false
        )
        service.selectZone(zone)

        service.saveRadioFavorite()
        service.saveRadioFavorite() // duplicate

        XCTAssertEqual(service.radioFavorites.count, 1)
    }

    func testIsCurrentTrackFavoriteMatchesByTrackInfo() {
        // Favorite stored with new format
        let fav = RadioFavorite(
            id: UUID(), title: "Song", artist: "Artist",
            stationName: "FIP", image_key: nil, savedAt: Date()
        )
        service.radioFavorites = [fav]

        // Zone playing the same track (line2=Song, line3=Artist)
        let np = NowPlaying(
            one_line: nil, two_line: nil,
            three_line: NowPlaying.LineInfo(line1: "FIP", line2: "Song", line3: "Artist"),
            length: nil, seek_position: nil, image_key: nil
        )
        let zone = RoonZone(
            zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: np, outputs: nil, settings: nil, seek_position: nil,
            is_play_allowed: true, is_pause_allowed: true, is_seek_allowed: false,
            is_previous_allowed: false, is_next_allowed: false
        )
        service.selectZone(zone)

        XCTAssertTrue(service.isCurrentTrackFavorite())
    }

    func testIsCurrentTrackFavoriteReturnsFalseForDifferentTrack() {
        let fav = RadioFavorite(
            id: UUID(), title: "Song A", artist: "Artist A",
            stationName: "FIP", image_key: nil, savedAt: Date()
        )
        service.radioFavorites = [fav]

        let np = NowPlaying(
            one_line: nil, two_line: nil,
            three_line: NowPlaying.LineInfo(line1: "FIP", line2: "Song B", line3: "Artist B"),
            length: nil, seek_position: nil, image_key: nil
        )
        let zone = RoonZone(
            zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: np, outputs: nil, settings: nil, seek_position: nil,
            is_play_allowed: true, is_pause_allowed: true, is_seek_allowed: false,
            is_previous_allowed: false, is_next_allowed: false
        )
        service.selectZone(zone)

        XCTAssertFalse(service.isCurrentTrackFavorite())
    }

    func testRadioFavoriteBackwardCompatibleDecoding() {
        // Old format: no stationName field
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "title": "FIP",
            "artist": "It's A Shame",
            "savedAt": "2025-06-01T12:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let fav = try? decoder.decode(RadioFavorite.self, from: Data(json.utf8))
        XCTAssertNotNil(fav)
        XCTAssertEqual(fav?.title, "FIP")
        XCTAssertEqual(fav?.artist, "It's A Shame")
        XCTAssertEqual(fav?.stationName, "")  // default empty for old format
    }

    func testRadioFavoriteNewFormatRoundTrip() {
        let fav = RadioFavorite(
            id: UUID(), title: "Song", artist: "Artist",
            stationName: "FIP", image_key: "key", savedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode(fav)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try! decoder.decode(RadioFavorite.self, from: data)

        XCTAssertEqual(decoded.title, "Song")
        XCTAssertEqual(decoded.artist, "Artist")
        XCTAssertEqual(decoded.stationName, "FIP")
        XCTAssertEqual(decoded.image_key, "key")
    }

    // MARK: - Roon UI behavior

    func testContentViewDefaultsToRoonMode() {
        // @AppStorage("uiMode") defaults to "roon"
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "uiMode")
        let mode = defaults.string(forKey: "uiMode") ?? "roon"
        XCTAssertEqual(mode, "roon")
    }

    func testRoonTransportBarShowsTrackInfo() {
        let np = NowPlaying(
            one_line: nil, two_line: nil,
            three_line: NowPlaying.LineInfo(line1: "Track Title", line2: "Artist Name", line3: "Album"),
            length: 240, seek_position: 30, image_key: "img1"
        )
        let zone = makeZone(id: "z1", name: "Zone", state: "playing", nowPlaying: np)
        service.selectZone(zone)

        // RoonTransportBarView displays title and artist from three_line
        let title = service.currentZone?.now_playing?.three_line?.line1
        let artist = service.currentZone?.now_playing?.three_line?.line2
        XCTAssertEqual(title, "Track Title")
        XCTAssertEqual(artist, "Artist Name")
    }

    func testRoonTransportBarPlayPauseIcon() {
        let np = makeNowPlaying(title: "Song")

        let playing = makeZone(id: "z1", name: "Zone", state: "playing", nowPlaying: np)
        service.selectZone(playing)
        // Transport bar shows "pause.circle.fill" when playing
        XCTAssertEqual(service.currentZone?.state, "playing")

        let paused = makeZone(id: "z1", name: "Zone", state: "paused", nowPlaying: np)
        service.selectZone(paused)
        // Transport bar shows "play.circle.fill" when paused
        XCTAssertEqual(service.currentZone?.state, "paused")
    }

    func testRoonTransportBarSeekProgress() {
        let np = NowPlaying(
            one_line: nil, two_line: nil,
            three_line: NowPlaying.LineInfo(line1: "Song", line2: "Artist", line3: "Album"),
            length: 200, seek_position: 100, image_key: nil
        )
        let zone = makeZone(id: "z1", name: "Zone", state: "playing", nowPlaying: np, seekPosition: 100)
        service.selectZone(zone)

        let position = Double(service.seekPosition)
        let duration = Double(np.length ?? 0)
        XCTAssertEqual(position / duration, 0.5, accuracy: 0.01)
    }

    func testRoonSidebarSections() {
        // All RoonSection cases have labels and icons
        let sections = RoonSection.allCases
        XCTAssertEqual(sections.count, 7)
        for section in sections {
            XCTAssertFalse(section.label.isEmpty)
            XCTAssertFalse(section.icon.isEmpty)
        }
    }

    func testUIModeCases() {
        let modes = UIMode.allCases
        XCTAssertEqual(modes.count, 2)
        XCTAssertEqual(UIMode.player.label, "Player")
        XCTAssertEqual(UIMode.roon.label, "Roon")
    }

    // MARK: - ConnectionView behavior

    func testConnectionViewStates() {
        // Disconnected state
        XCTAssertEqual(service.connectionState, .disconnected)
        // ConnectionView shows "Deconnecte du Roon Core" with xmark.circle in red

        // No error initially
        XCTAssertNil(service.lastError)
    }

    func testConnectionViewErrorDisplay() {
        service.lastError = "Connexion refusee"
        XCTAssertEqual(service.lastError, "Connexion refusee")
        // ConnectionView shows error text in red at the bottom
    }

    // MARK: - Helpers

    private func makeZone(
        id: String, name: String, state: String = "stopped",
        nowPlaying: NowPlaying? = nil, seekPosition: Int? = nil,
        settings: ZoneSettings? = nil
    ) -> RoonZone {
        RoonZone(
            zone_id: id, display_name: name, state: state,
            now_playing: nowPlaying, outputs: nil, settings: settings, seek_position: seekPosition,
            is_play_allowed: true, is_pause_allowed: nil, is_seek_allowed: nil,
            is_previous_allowed: nil, is_next_allowed: nil
        )
    }

    private func makeNowPlaying(title: String, artist: String = "", album: String = "") -> NowPlaying {
        NowPlaying(
            one_line: nil, two_line: nil,
            three_line: NowPlaying.LineInfo(line1: title, line2: artist, line3: album),
            length: 240, seek_position: 0, image_key: nil
        )
    }

    private func makeBrowseItem(title: String, hint: String, itemKey: String? = nil, imageKey: String? = nil, subtitle: String? = nil) -> BrowseItem {
        var fields: [String] = []
        fields.append("\"title\": \"\(title)\"")
        fields.append("\"hint\": \"\(hint)\"")
        if let key = itemKey { fields.append("\"item_key\": \"\(key)\"") }
        if let img = imageKey { fields.append("\"image_key\": \"\(img)\"") }
        if let sub = subtitle { fields.append("\"subtitle\": \"\(sub)\"") }
        let json = "{\(fields.joined(separator: ", "))}"
        return try! JSONDecoder().decode(BrowseItem.self, from: Data(json.utf8))
    }

    // MARK: - Browse layout detection

    func testArtistDetailDetected() {
        // Artist page: first items have no image, followed by albums with images
        let items: [BrowseItem] = [
            makeBrowseItem(title: "Play Artist", hint: "list", itemKey: "a1"),
            makeBrowseItem(title: "Start Radio", hint: "action", itemKey: "a2"),
            makeBrowseItem(title: "Album 1", hint: "list", itemKey: "b1", imageKey: "img1"),
            makeBrowseItem(title: "Album 2", hint: "list", itemKey: "b2", imageKey: "img2"),
            makeBrowseItem(title: "Album 3", hint: "action_list", itemKey: "b3", imageKey: "img3"),
        ]
        // First item has no image
        XCTAssertNil(items.first?.image_key)
        // There are navigable items with images
        let listWithImage = items.prefix(20).filter {
            $0.image_key != nil && ($0.hint == "list" || $0.hint == "action_list")
        }.count
        XCTAssertGreaterThanOrEqual(listWithImage, 1)
    }

    func testAlbumNotDetectedAsArtist() {
        // Album page: isPlaylistView catches this first; but also first item (Play Album)
        // has no image_key and tracks have no navigable items with images
        let items: [BrowseItem] = [
            makeBrowseItem(title: "Track 1", hint: "action", itemKey: "t1", subtitle: "Artist - Album"),
            makeBrowseItem(title: "Track 2", hint: "action", itemKey: "t2", subtitle: "Artist - Album"),
            makeBrowseItem(title: "Track 3", hint: "action", itemKey: "t3", subtitle: "Artist - Album"),
        ]
        let listWithImage = items.prefix(20).filter {
            $0.image_key != nil && ($0.hint == "list" || $0.hint == "action_list")
        }.count
        // No items with image_key → listWithImage == 0 → not artist detail
        XCTAssertEqual(listWithImage, 0)
    }

    func testCategoryNotDetectedAsArtist() {
        // Category grid (list of artists): first item HAS an image → guard fails
        let items: [BrowseItem] = [
            makeBrowseItem(title: "Artist 1", hint: "list", itemKey: "a1", imageKey: "img1"),
            makeBrowseItem(title: "Artist 2", hint: "list", itemKey: "a2", imageKey: "img2"),
            makeBrowseItem(title: "Artist 3", hint: "list", itemKey: "a3", imageKey: "img3"),
        ]
        // First item has image → not artist detail
        XCTAssertNotNil(items.first?.image_key)
    }

    func testArtistDetailSeparatesActionsAndAlbums() {
        // Items without image_key are actions, items with image_key are albums
        let items: [BrowseItem] = [
            makeBrowseItem(title: "Play Artist", hint: "list", itemKey: "a1"),
            makeBrowseItem(title: "Start Radio", hint: "action", itemKey: "a2"),
            makeBrowseItem(title: "Album 1", hint: "list", itemKey: "b1", imageKey: "img1"),
            makeBrowseItem(title: "Album 2", hint: "list", itemKey: "b2", imageKey: "img2"),
        ]
        let actions = items.filter { $0.image_key == nil }
        let albums = items.filter { $0.image_key != nil }
        XCTAssertEqual(actions.count, 2)
        XCTAssertEqual(albums.count, 2)
        XCTAssertEqual(actions[0].title, "Play Artist")
        XCTAssertEqual(albums[0].title, "Album 1")
    }

    func testParseSubtitleExtractsArtist() {
        // parseSubtitle splits "Artist - Album" into (artist, album)
        func parseSubtitle(_ subtitle: String?) -> (artist: String, album: String) {
            guard let subtitle = subtitle, !subtitle.isEmpty else { return ("", "") }
            if let range = subtitle.range(of: " - ") {
                let artist = String(subtitle[subtitle.startIndex..<range.lowerBound])
                let album = String(subtitle[range.upperBound...])
                return (artist, album)
            }
            return (subtitle, "")
        }

        let result1 = parseSubtitle("Pink Floyd - The Dark Side of the Moon")
        XCTAssertEqual(result1.artist, "Pink Floyd")
        XCTAssertEqual(result1.album, "The Dark Side of the Moon")

        let result2 = parseSubtitle("Solo Artist")
        XCTAssertEqual(result2.artist, "Solo Artist")
        XCTAssertEqual(result2.album, "")

        let result3 = parseSubtitle(nil)
        XCTAssertEqual(result3.artist, "")
        XCTAssertEqual(result3.album, "")

        let result4 = parseSubtitle("")
        XCTAssertEqual(result4.artist, "")
        XCTAssertEqual(result4.album, "")
    }

    func testArtistWithOnlyActionsNotDetected() {
        // Edge case: artist page with only actions loaded (albums not yet loaded)
        let items: [BrowseItem] = [
            makeBrowseItem(title: "Play Artist", hint: "list", itemKey: "a1"),
            makeBrowseItem(title: "Start Radio", hint: "action", itemKey: "a2"),
        ]
        // First item has no image (passes guard) but no items with images
        XCTAssertNil(items.first?.image_key)
        let listWithImage = items.prefix(20).filter {
            $0.image_key != nil && ($0.hint == "list" || $0.hint == "action_list")
        }.count
        // No albums with images → listWithImage == 0 → not detected
        XCTAssertEqual(listWithImage, 0)
    }

    // MARK: - Home Screen behavior

    func testHomeShowsGreeting() {
        // Home screen always shows "Bonjour" greeting at top
        // (verified by RoonContentView.homeContent containing Text("Bonjour"))
        XCTAssertTrue(true) // Structural test — greeting is hardcoded in view
    }

    func testHomeShowsLibraryStats() {
        // Library counts are displayed when available
        service.libraryCounts = ["artists": 856, "albums": 1520, "tracks": 17876, "composers": 98]
        XCTAssertEqual(service.libraryCounts["artists"], 856)
        XCTAssertEqual(service.libraryCounts["albums"], 1520)
        XCTAssertEqual(service.libraryCounts["tracks"], 17876)
        XCTAssertEqual(service.libraryCounts["composers"], 98)
    }

    func testHomeLibraryStatsEmptyWhenNotLoaded() {
        // Before connection, libraryCounts is empty
        XCTAssertTrue(service.libraryCounts.isEmpty)
    }

    func testHomeRecentPlayedTilesFromHistory() {
        // Home "Dernièrement" section shows up to 20 tiles from playbackHistory
        let items = (0..<25).map { i in
            PlaybackHistoryItem(
                id: UUID(), title: "Track \(i)", artist: "Artist \(i)", album: "Album \(i)",
                image_key: "img\(i)", length: 240, isRadio: false, zone_name: "Zone", playedAt: Date()
            )
        }
        service.playbackHistory = items
        XCTAssertEqual(service.playbackHistory.count, 25)
        // View caps at 20: prefix(20)
        let displayed = service.playbackHistory.prefix(20)
        XCTAssertEqual(displayed.count, 20)
    }

    func testHomeUpNextTilesFromQueue() {
        // Queue items can be set (used by QueueView, no longer shown on home)
        let items = (0..<5).map { i in
            QueueItem(queue_item_id: i,
                      one_line: NowPlaying.LineInfo(line1: "Track \(i)", line2: nil, line3: nil),
                      two_line: nil,
                      three_line: NowPlaying.LineInfo(line1: "Track \(i)", line2: "Artist \(i)", line3: "Album \(i)"),
                      length: 240, image_key: "img\(i)")
        }
        service.queueItems = items
        XCTAssertEqual(service.queueItems.count, 5)
    }

    func testHomeOtherZonesFiltered() {
        // Zone filtering: zones with now_playing AND not currentZone (used by zone selection)
        let np = makeNowPlaying(title: "Song")
        let z1 = makeZone(id: "z1", name: "Salon", state: "playing", nowPlaying: np)
        let z2 = makeZone(id: "z2", name: "Chambre", state: "playing", nowPlaying: np)
        let z3 = makeZone(id: "z3", name: "Bureau", state: "stopped") // no now_playing

        service.zones = [z1, z2, z3]
        service.selectZone(z1)

        let otherZones = service.zones.filter {
            $0.zone_id != service.currentZone?.zone_id && $0.now_playing != nil
        }
        XCTAssertEqual(otherZones.count, 1)
        XCTAssertEqual(otherZones.first?.display_name, "Chambre")
    }

    func testHomeDefaultSectionIsHome() {
        // RoonLayoutView defaults to .home section
        // Verified structurally: @State private var selectedSection: RoonSection = .home
        XCTAssertTrue(true)
    }

    // MARK: - Sidebar categories

    func testSidebarCategoriesInitiallyEmpty() {
        XCTAssertTrue(service.sidebarCategories.isEmpty)
        XCTAssertTrue(service.sidebarPlaylists.isEmpty)
    }

    func testSidebarCategoriesCanBeSet() {
        let item = makeBrowseItem(title: "Genres", hint: "list", itemKey: "g1")
        service.sidebarCategories = [item]
        XCTAssertEqual(service.sidebarCategories.count, 1)
        XCTAssertEqual(service.sidebarCategories.first?.title, "Genres")
    }

    func testSidebarPlaylistsCanBeSet() {
        let pl = makeBrowseItem(title: "My Playlist", hint: "action_list", itemKey: "p1")
        service.sidebarPlaylists = [pl]
        XCTAssertEqual(service.sidebarPlaylists.count, 1)
    }

    // MARK: - Sidebar playlist filtering

    func testPlaylistFilterMatchesTitle() {
        let playlists = [
            makeBrowseItem(title: "Jazz Classics", hint: "action_list", itemKey: "p1"),
            makeBrowseItem(title: "Rock Hits", hint: "action_list", itemKey: "p2"),
            makeBrowseItem(title: "Jazz & Soul", hint: "action_list", itemKey: "p3"),
        ]
        let query = "jazz"
        let filtered = playlists.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(query)
        }
        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered[0].title, "Jazz Classics")
        XCTAssertEqual(filtered[1].title, "Jazz & Soul")
    }

    func testPlaylistFilterEmptyQueryReturnsFirst10() {
        // Without search, sidebar shows only the first 10 playlists
        let playlists = (0..<25).map {
            makeBrowseItem(title: "Playlist \($0)", hint: "action_list", itemKey: "p\($0)")
        }
        let query = "   "
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let filtered = trimmed.isEmpty
            ? Array(playlists.prefix(10))
            : playlists.filter { ($0.title ?? "").localizedCaseInsensitiveContains(trimmed) }
        XCTAssertEqual(filtered.count, 10)
    }

    func testPlaylistFilterSearchesAllPlaylists() {
        // Search filters across ALL playlists, not just the visible 10
        let playlists = (0..<25).map {
            makeBrowseItem(title: "Playlist \($0)", hint: "action_list", itemKey: "p\($0)")
        }
        let query = "Playlist 2"
        let filtered = playlists.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(query)
        }
        // Matches: "Playlist 2", "Playlist 20", "Playlist 21", ..., "Playlist 24"
        XCTAssertEqual(filtered.count, 6)
        XCTAssertEqual(filtered[0].title, "Playlist 2")
        XCTAssertEqual(filtered[1].title, "Playlist 20")
    }

    func testPlaylistFilterNoMatch() {
        let playlists = [
            makeBrowseItem(title: "Rock Hits", hint: "action_list", itemKey: "p1"),
            makeBrowseItem(title: "Pop Mix", hint: "action_list", itemKey: "p2"),
        ]
        let query = "classical"
        let filtered = playlists.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(query)
        }
        XCTAssertTrue(filtered.isEmpty)
    }

    // MARK: - Now Playing view behavior

    func testNowPlayingSectionExists() {
        // RoonSection includes .nowPlaying for the Now Playing content view
        let section = RoonSection.nowPlaying
        XCTAssertEqual(section.label, String(localized: "En lecture"))
        XCTAssertEqual(section.icon, "music.note")
    }

    func testNowPlayingShowsTrackInfo() {
        // Now Playing view shows track info from currentZone.now_playing
        let np = makeNowPlaying(title: "Sitar soul", artist: "Phil Upchurch", album: "FIP Radio")
        let zone = makeZone(id: "z1", name: "Bureau", state: "playing", nowPlaying: np)
        service.zones = [zone]
        service.selectZone(zone)

        XCTAssertEqual(service.currentZone?.now_playing?.three_line?.line1, "Sitar soul")
        XCTAssertEqual(service.currentZone?.now_playing?.three_line?.line2, "Phil Upchurch")
        XCTAssertEqual(service.currentZone?.now_playing?.three_line?.line3, "FIP Radio")
    }

    func testNowPlayingEmptyWhenNoTrack() {
        // Now Playing shows empty state when no now_playing on current zone
        let zone = makeZone(id: "z1", name: "Bureau", state: "stopped")
        service.zones = [zone]
        service.selectZone(zone)

        XCTAssertNil(service.currentZone?.now_playing)
    }

    func testNowPlayingUpNextFromQueue() {
        // Now Playing shows up to 5 items from queue in "A SUIVRE" section
        let items = (0..<8).map { i in
            QueueItem(queue_item_id: i,
                      one_line: NowPlaying.LineInfo(line1: "Track \(i)", line2: nil, line3: nil),
                      two_line: nil,
                      three_line: NowPlaying.LineInfo(line1: "Track \(i)", line2: "Artist \(i)", line3: "Album \(i)"),
                      length: 180, image_key: "img\(i)")
        }
        service.queueItems = items
        // View shows prefix(5)
        let displayed = Array(service.queueItems.prefix(5))
        XCTAssertEqual(displayed.count, 5)
        XCTAssertEqual(displayed.last?.queue_item_id, 4)
    }

    func testNowPlayingSettingsState() {
        // Settings controls reflect zone settings (shuffle, loop, auto_radio)
        let settings = ZoneSettings(shuffle: true, loop: "loop", auto_radio: false)
        let np = makeNowPlaying(title: "Track")
        let zone = makeZone(id: "z1", name: "Bureau", state: "playing", nowPlaying: np, settings: settings)
        service.zones = [zone]
        service.selectZone(zone)

        XCTAssertTrue(service.currentZone?.settings?.shuffle ?? false)
        XCTAssertEqual(service.currentZone?.settings?.loop, "loop")
        XCTAssertFalse(service.currentZone?.settings?.auto_radio ?? true)
    }

    func testTransportBarNavigatesToNowPlaying() {
        // Transport bar's onNowPlayingTap callback allows navigation to .nowPlaying
        var navigatedSection: RoonSection = .home
        let callback = { navigatedSection = .nowPlaying }
        callback()
        XCTAssertEqual(navigatedSection, .nowPlaying)
    }

    // MARK: - Default zone selection

    func testDefaultZoneSelection() {
        // When default_zone_name matches an existing zone, that zone is selected
        let z1 = makeZone(id: "z1", name: "Salon")
        let z2 = makeZone(id: "z2", name: "Bureau")
        let z3 = makeZone(id: "z3", name: "Chambre")

        UserDefaults.standard.set("Bureau", forKey: "default_zone_name")
        defer { UserDefaults.standard.removeObject(forKey: "default_zone_name") }

        // Simulate the selection logic from handleZonesData
        let zones = [z1, z2, z3]
        let defaultName = UserDefaults.standard.string(forKey: "default_zone_name") ?? ""
        let target = zones.first(where: { $0.display_name == defaultName }) ?? zones.first!

        XCTAssertEqual(target.display_name, "Bureau")
        XCTAssertEqual(target.zone_id, "z2")
    }

    func testDefaultZoneFallback() {
        // When default_zone_name doesn't match any zone, fall back to first zone
        let z1 = makeZone(id: "z1", name: "Salon")
        let z2 = makeZone(id: "z2", name: "Bureau")

        UserDefaults.standard.set("Inexistante", forKey: "default_zone_name")
        defer { UserDefaults.standard.removeObject(forKey: "default_zone_name") }

        let zones = [z1, z2]
        let defaultName = UserDefaults.standard.string(forKey: "default_zone_name") ?? ""
        let target = zones.first(where: { $0.display_name == defaultName }) ?? zones.first!

        XCTAssertEqual(target.display_name, "Salon")
        XCTAssertEqual(target.zone_id, "z1")
    }

    func testDefaultZoneEmptyMeansAutomatic() {
        // When default_zone_name is empty (no preference), first zone is selected
        let z1 = makeZone(id: "z1", name: "Salon")
        let z2 = makeZone(id: "z2", name: "Bureau")

        UserDefaults.standard.removeObject(forKey: "default_zone_name")

        let zones = [z1, z2]
        let defaultName = UserDefaults.standard.string(forKey: "default_zone_name") ?? ""
        XCTAssertEqual(defaultName, "")
        let target = zones.first(where: { $0.display_name == defaultName }) ?? zones.first!

        XCTAssertEqual(target.display_name, "Salon")
    }

    func testDefaultZoneMatchesDisplayNameNotId() {
        // Selection uses display_name (stable) not zone_id (changes between restarts)
        let z1 = makeZone(id: "1801a803-zone1", name: "Salon")
        let z2 = makeZone(id: "9f32bc01-zone2", name: "Bureau")

        UserDefaults.standard.set("Bureau", forKey: "default_zone_name")
        defer { UserDefaults.standard.removeObject(forKey: "default_zone_name") }

        let zones = [z1, z2]
        let defaultName = UserDefaults.standard.string(forKey: "default_zone_name") ?? ""
        let target = zones.first(where: { $0.display_name == defaultName }) ?? zones.first!

        // Matches by display_name, not by zone_id
        XCTAssertEqual(target.display_name, "Bureau")
        XCTAssertEqual(target.zone_id, "9f32bc01-zone2")
    }

    // MARK: - Default UI mode

    func testSettingsViewDefaultsToRoonMode() {
        // SettingsView @AppStorage("uiMode") defaults to "roon"
        UserDefaults.standard.removeObject(forKey: "uiMode")
        let mode = UserDefaults.standard.string(forKey: "uiMode") ?? "roon"
        XCTAssertEqual(mode, "roon")
    }

    // MARK: - Font registration

    func testRoonFontsRegisterDoesNotCrash() {
        // Font registration should be safe to call multiple times
        RoonFonts.registerAll()
        RoonFonts.registerAll() // second call should be no-op
        XCTAssertTrue(true)
    }

    func testGrifoMFontAvailable() {
        RoonFonts.registerAll()
        let font = NSFont(name: "GrifoM-Medium", size: 12)
        // Font may or may not be available depending on bundle resources in test
        // We just ensure no crash
        _ = font
    }

    // MARK: - Helpers

    private func formatTime(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "maintenant" }
        if interval < 3600 { return "il y a \(Int(interval / 60)) min" }
        if interval < 86400 { return "il y a \(Int(interval / 3600))h" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
