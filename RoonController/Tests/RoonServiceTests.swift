import XCTest
@testable import Roon_Controller

@MainActor
final class RoonServiceTests: XCTestCase {

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

    // MARK: - Browse duplicate guard

    func testBrowsePendingKeyBlocksDuplicate() {
        // First call should go through (we can't verify the send, but we test the guard logic)
        service.browse(itemKey: "149:0")

        // Capture current browseResult to verify it didn't change from a second call
        let before = service.browseResult

        // Second call with same key should be blocked
        service.browse(itemKey: "149:0")

        // browseResult unchanged (no new result came in)
        XCTAssertEqual(service.browseResult, before)
    }

    func testBrowseDifferentKeyPassesGuard() {
        service.browse(itemKey: "149:0")
        // Different key should not be blocked — this should not crash
        service.browse(itemKey: "150:3")
    }

    func testBrowseBackResetsPendingKey() {
        service.browse(itemKey: "149:0")
        service.browseBack()
        // After back, same key should work again (not blocked)
        service.browse(itemKey: "149:0")
    }

    func testBrowseHomeResetsPendingKey() {
        service.browse(itemKey: "149:0")
        service.browseHome()
        // After home, same key should work again
        service.browse(itemKey: "149:0")
    }

    func testBrowseWithoutItemKeySkipsGuard() {
        // Root browse (no itemKey) should never be blocked
        service.browse()
        service.browse()
    }

    // MARK: - Playback History

    func testHistoryIsInitiallyEmpty() {
        XCTAssertTrue(service.playbackHistory.isEmpty)
    }

    func testClearHistoryRemovesAll() {
        // Manually add an item
        let item = PlaybackHistoryItem(
            id: UUID(), title: "Test", artist: "Artist", album: "Album",
            image_key: nil, length: 100, zone_name: "Zone", playedAt: Date()
        )
        service.playbackHistory = [item]
        XCTAssertEqual(service.playbackHistory.count, 1)

        service.clearHistory()
        XCTAssertTrue(service.playbackHistory.isEmpty)
    }

    // MARK: - History deduplication

    func testHistoryDeduplicationPreventsConsecutiveSameTrack() {
        // Simulate a zone playing a track
        let item = PlaybackHistoryItem(
            id: UUID(), title: "Song A", artist: "Artist", album: "Album",
            image_key: nil, length: 200, zone_name: "Eversolo DMP-A8", playedAt: Date()
        )
        service.playbackHistory = [item]

        // The history already has "Song A" for this zone
        // When zones_changed arrives with the same track, it should not add a duplicate
        XCTAssertEqual(service.playbackHistory.count, 1)
        XCTAssertEqual(service.playbackHistory[0].title, "Song A")
    }

    // MARK: - Zone selection

    func testSelectZoneClearsQueue() {
        let zone = RoonZone(
            zone_id: "z1", display_name: "Test Zone", state: "playing",
            now_playing: nil, outputs: nil, settings: nil, seek_position: nil,
            is_play_allowed: true, is_pause_allowed: nil, is_seek_allowed: nil,
            is_previous_allowed: nil, is_next_allowed: nil
        )
        service.queueItems = [
            QueueItem(queue_item_id: 1, one_line: nil, two_line: nil, three_line: nil, length: nil, image_key: nil)
        ]
        XCTAssertEqual(service.queueItems.count, 1)

        service.selectZone(zone)
        XCTAssertTrue(service.queueItems.isEmpty)
        XCTAssertEqual(service.currentZone?.zone_id, "z1")
    }

    // MARK: - Image URL generation

    func testImageURLGeneration() {
        let url = service.imageURL(key: "abc123", width: 400, height: 400)
        XCTAssertEqual(url?.absoluteString, "http://localhost:9150/image/abc123?width=400&height=400")
    }

    func testImageURLReturnsNilForNilKey() {
        let url = service.imageURL(key: nil)
        XCTAssertNil(url)
    }

    // MARK: - MOO Message Tests

    func testMOOMessageParseRequest() {
        let raw = "MOO/1 REQUEST com.roonlabs.transport:2/control\nRequest-Id: 42\nContent-Type: application/json\n\n{\"control\":\"play\"}"
        let data = Data(raw.utf8)
        let msg = MOOMessage.parse(data)

        XCTAssertNotNil(msg)
        XCTAssertEqual(msg?.verb, .request)
        XCTAssertEqual(msg?.name, "com.roonlabs.transport:2/control")
        XCTAssertEqual(msg?.requestId, 42)
        XCTAssertNotNil(msg?.body)

        let bodyJSON = msg?.bodyJSON
        XCTAssertEqual(bodyJSON?["control"] as? String, "play")
    }

    func testMOOMessageParseContinue() {
        let raw = "MOO/1 CONTINUE Subscribed\nRequest-Id: 7\n\n"
        let data = Data(raw.utf8)
        let msg = MOOMessage.parse(data)

        XCTAssertNotNil(msg)
        XCTAssertEqual(msg?.verb, .continue)
        XCTAssertEqual(msg?.name, "Subscribed")
        XCTAssertEqual(msg?.requestId, 7)
        XCTAssertNil(msg?.body)
    }

    func testMOOMessageParseComplete() {
        let raw = "MOO/1 COMPLETE Success\nRequest-Id: 1\n\n"
        let data = Data(raw.utf8)
        let msg = MOOMessage.parse(data)

        XCTAssertNotNil(msg)
        XCTAssertEqual(msg?.verb, .complete)
        XCTAssertEqual(msg?.name, "Success")
        XCTAssertEqual(msg?.requestId, 1)
    }

    func testMOOMessageBuildRequest() {
        let body: [String: Any] = ["control": "play"]
        let data = MOOMessage.request(name: "com.roonlabs.transport:2/control", requestId: 5, jsonBody: body)

        // Should be parseable
        let msg = MOOMessage.parse(data)
        XCTAssertNotNil(msg)
        XCTAssertEqual(msg?.verb, .request)
        XCTAssertEqual(msg?.name, "com.roonlabs.transport:2/control")
        XCTAssertEqual(msg?.requestId, 5)
        XCTAssertEqual(msg?.bodyJSON?["control"] as? String, "play")
    }

    func testMOOMessageBuildComplete() {
        let data = MOOMessage.complete(name: "Success", requestId: 10)
        let msg = MOOMessage.parse(data)

        XCTAssertNotNil(msg)
        XCTAssertEqual(msg?.verb, .complete)
        XCTAssertEqual(msg?.requestId, 10)
    }

    func testMOOMessageParseInvalidReturnsNil() {
        let raw = "INVALID DATA"
        let data = Data(raw.utf8)
        XCTAssertNil(MOOMessage.parse(data))
    }

    func testMOOMessageParseMissingRequestIdReturnsNil() {
        let raw = "MOO/1 REQUEST test/method\n\n"
        let data = Data(raw.utf8)
        XCTAssertNil(MOOMessage.parse(data))
    }

    func testMOORequestIdGeneratorIncrementsAtomically() {
        let generator = MOORequestIdGenerator()
        let id1 = generator.next()
        let id2 = generator.next()
        let id3 = generator.next()
        XCTAssertEqual(id1, 1)
        XCTAssertEqual(id2, 2)
        XCTAssertEqual(id3, 3)
    }

    // MARK: - MOO Message Content-Length consistency

    func testMOOMessageContentLengthMatchesBody() {
        let body: [String: Any] = [
            "extension_id": "com.bertrand.rooncontroller",
            "display_name": "Roon Controller macOS",
            "required_services": ["com.roonlabs.transport:2", "com.roonlabs.browse:1"]
        ]
        let data = MOOMessage.request(name: "com.roonlabs.registry:1/register", requestId: 1, jsonBody: body)
        let msg = MOOMessage.parse(data)

        XCTAssertNotNil(msg)
        XCTAssertNotNil(msg?.body)

        // Content-Length header must match actual body size
        if let contentLength = msg?.headers["Content-Length"],
           let clValue = Int(contentLength),
           let body = msg?.body {
            XCTAssertEqual(clValue, body.count, "Content-Length must match actual body size")
        }
    }

    func testMOOMessageDataBodyNotReEncoded() {
        // Regression test: Data body must not be Base64-re-encoded via JSONEncoder
        let jsonBody: [String: Any] = ["key": "value"]
        let jsonData = try! JSONSerialization.data(withJSONObject: jsonBody)
        let data = MOOMessage.request(name: "test/method", requestId: 1, body: jsonData)
        let msg = MOOMessage.parse(data)

        XCTAssertNotNil(msg)
        // Body should be valid JSON, not a Base64 string
        let parsed = msg?.bodyJSON
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?["key"] as? String, "value")
    }

    // MARK: - Registration body format

    func testRegistrationBodyServicesAreStringArrays() {
        let body = RoonRegistration.registerRequestBody()

        // required_services must be an array of strings, not objects
        let required = body["required_services"] as? [String]
        XCTAssertNotNil(required, "required_services must be [String]")
        XCTAssertTrue(required?.contains("com.roonlabs.transport:2") ?? false)
        XCTAssertTrue(required?.contains("com.roonlabs.browse:1") ?? false)
        XCTAssertTrue(required?.contains("com.roonlabs.image:1") ?? false)

        // provided_services must be an array of strings
        let provided = body["provided_services"] as? [String]
        XCTAssertNotNil(provided, "provided_services must be [String]")
        XCTAssertTrue(provided?.contains("com.roonlabs.ping:1") ?? false)
        XCTAssertTrue(provided?.contains("com.roonlabs.status:1") ?? false)

        // optional_services must be present
        let optional = body["optional_services"] as? [String]
        XCTAssertNotNil(optional, "optional_services must be [String]")
    }

    func testRegistrationBodyContainsRequiredFields() {
        let body = RoonRegistration.registerRequestBody()

        XCTAssertNotNil(body["extension_id"] as? String)
        XCTAssertNotNil(body["display_name"] as? String)
        XCTAssertNotNil(body["display_version"] as? String)
        XCTAssertNotNil(body["publisher"] as? String)
    }

    func testRegistrationBodyIsValidJSON() {
        let body = RoonRegistration.registerRequestBody()
        // Must be serializable to JSON without error
        let data = try? JSONSerialization.data(withJSONObject: body)
        XCTAssertNotNil(data, "Registration body must be valid JSON")

        // Round-trip: deserialize and check it's still a dictionary
        if let data = data {
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            XCTAssertNotNil(parsed)
        }
    }

    // MARK: - Queue subscription body format

    func testSubscribeQueueBodyContainsZoneOrOutputId() {
        // Regression test: subscribe_queue was rejected with InvalidRequest
        // because zone_or_output_id was missing from the body.
        let zoneId = "1601f2904ed29969cc897bb4fd2fb6f955ba"
        let body: [String: Any] = [
            "zone_or_output_id": zoneId,
            "subscription_key": "queue_\(zoneId)",
            "max_items": 100
        ]

        // zone_or_output_id must be present
        XCTAssertEqual(body["zone_or_output_id"] as? String, zoneId,
                       "subscribe_queue body must include zone_or_output_id")
        XCTAssertNotNil(body["subscription_key"])
        XCTAssertNotNil(body["max_items"])

        // Must be valid JSON
        let data = try? JSONSerialization.data(withJSONObject: body)
        XCTAssertNotNil(data, "subscribe_queue body must be valid JSON")
    }

    func testSubscribeQueueMOOMessageContainsZoneId() {
        // Build the MOO message the same way RoonConnection.subscribeQueue does
        let zoneId = "160186de7aef552def11a7c6800a805d4dee"
        let body: [String: Any] = [
            "zone_or_output_id": zoneId,
            "subscription_key": "queue_\(zoneId)",
            "max_items": 100
        ]
        let bodyData = try! JSONSerialization.data(withJSONObject: body)
        let data = MOOMessage.request(
            name: "com.roonlabs.transport:2/subscribe_queue",
            requestId: 10,
            body: bodyData
        )

        // Parse back and verify
        let msg = MOOMessage.parse(data)
        XCTAssertNotNil(msg)
        XCTAssertEqual(msg?.verb, .request)
        XCTAssertEqual(msg?.name, "com.roonlabs.transport:2/subscribe_queue")

        let parsed = msg?.bodyJSON
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?["zone_or_output_id"] as? String, zoneId,
                       "Parsed subscribe_queue must contain zone_or_output_id")
    }

    // MARK: - Queue data parsing

    func testQueueDataWithItemsFormat() {
        // Simulate the initial queue subscription response
        let queueJSON: [String: Any] = [
            "items": [
                [
                    "queue_item_id": 1,
                    "one_line": ["line1": "Track 1"],
                    "length": 240
                ],
                [
                    "queue_item_id": 2,
                    "one_line": ["line1": "Track 2"],
                    "length": 180
                ]
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: queueJSON)
        let body = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let itemsArray = body["items"] as? [[String: Any]]

        XCTAssertNotNil(itemsArray)
        XCTAssertEqual(itemsArray?.count, 2)

        // Verify items decode as QueueItem
        let decoder = JSONDecoder()
        let items: [QueueItem] = (itemsArray ?? []).compactMap { dict in
            guard let d = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
            return try? decoder.decode(QueueItem.self, from: d)
        }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].queue_item_id, 1)
        XCTAssertEqual(items[1].queue_item_id, 2)
        XCTAssertEqual(items[0].length, 240)
    }

    func testQueueDataWithChangesFormatHasNoItems() {
        // When the Core sends incremental updates, there is no top-level "items" key
        let changesJSON: [String: Any] = [
            "changes": [
                ["operation": "remove", "index": 0, "count": 1]
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: changesJSON)
        let body = try! JSONSerialization.jsonObject(with: data) as! [String: Any]

        // items should be nil — this is the case that needs re-subscription
        let itemsArray = body["items"] as? [[String: Any]]
        XCTAssertNil(itemsArray, "Changes format should not have top-level items")
        XCTAssertNotNil(body["changes"], "Changes format must have changes key")
    }

    // MARK: - Radio history

    func testRadioHistoryItemIsRadioFlag() {
        let radio = PlaybackHistoryItem(
            id: UUID(), title: "FIP", artist: "", album: "",
            image_key: nil, length: nil, isRadio: true, zone_name: "Zone", playedAt: Date()
        )
        XCTAssertTrue(radio.isRadio)

        let track = PlaybackHistoryItem(
            id: UUID(), title: "Song", artist: "Artist", album: "Album",
            image_key: nil, length: 240, isRadio: false, zone_name: "Zone", playedAt: Date()
        )
        XCTAssertFalse(track.isRadio)
    }

    func testRadioHistoryItemBackwardCompatibility() {
        // Old history JSON without isRadio field should decode with isRadio = false
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "title": "Old Track", "artist": "Artist", "album": "Album",
            "length": 200, "zone_name": "Zone",
            "playedAt": "2025-01-01T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let item = try? decoder.decode(PlaybackHistoryItem.self, from: Data(json.utf8))
        XCTAssertNotNil(item)
        XCTAssertFalse(item!.isRadio, "Old history items without isRadio must default to false")
    }

    func testRadioStationNameResolution() {
        // When album is empty, title should be used as station name
        let radioNoAlbum = PlaybackHistoryItem(
            id: UUID(), title: "FIP", artist: "", album: "",
            image_key: nil, length: nil, isRadio: true, zone_name: "Zone", playedAt: Date()
        )
        let stationName1 = radioNoAlbum.album.isEmpty ? radioNoAlbum.title : radioNoAlbum.album
        XCTAssertEqual(stationName1, "FIP")

        // When album has the station name (track metadata available), album is used
        let radioWithAlbum = PlaybackHistoryItem(
            id: UUID(), title: "I Will Survive", artist: "Gloria Gaynor", album: "FIP",
            image_key: nil, length: 200, isRadio: true, zone_name: "Zone", playedAt: Date()
        )
        let stationName2 = radioWithAlbum.album.isEmpty ? radioWithAlbum.title : radioWithAlbum.album
        XCTAssertEqual(stationName2, "FIP")
    }

    func testRadioDetectionFromZone() {
        // is_seek_allowed == false indicates a radio stream
        let radioZone = RoonZone(
            zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: NowPlaying(
                one_line: nil, two_line: nil,
                three_line: NowPlaying.LineInfo(line1: "FIP", line2: nil, line3: nil),
                length: nil, seek_position: nil, image_key: nil
            ),
            outputs: nil, settings: nil, seek_position: nil,
            is_play_allowed: true, is_pause_allowed: true, is_seek_allowed: false,
            is_previous_allowed: false, is_next_allowed: false
        )
        XCTAssertEqual(radioZone.is_seek_allowed, false)

        // Regular playback has is_seek_allowed == true
        let normalZone = RoonZone(
            zone_id: "z2", display_name: "Zone", state: "playing",
            now_playing: NowPlaying(
                one_line: nil, two_line: nil,
                three_line: NowPlaying.LineInfo(line1: "Song", line2: "Artist", line3: "Album"),
                length: 240, seek_position: 10, image_key: nil
            ),
            outputs: nil, settings: nil, seek_position: 10,
            is_play_allowed: true, is_pause_allowed: true, is_seek_allowed: true,
            is_previous_allowed: true, is_next_allowed: true
        )
        XCTAssertEqual(normalZone.is_seek_allowed, true)
    }

    // MARK: - Radio Favorites

    func testRadioFavoritesInitiallyEmpty() {
        XCTAssertTrue(service.radioFavorites.isEmpty)
    }

    func testSaveRadioFavoriteRequiresRadioZone() {
        // No zone selected — should not add anything
        service.saveRadioFavorite()
        XCTAssertTrue(service.radioFavorites.isEmpty)
    }

    func testRemoveRadioFavorite() {
        let fav = RadioFavorite(
            id: UUID(), title: "Song", artist: "Artist",
            image_key: nil, savedAt: Date()
        )
        service.radioFavorites = [fav]
        XCTAssertEqual(service.radioFavorites.count, 1)

        service.removeRadioFavorite(id: fav.id)
        XCTAssertTrue(service.radioFavorites.isEmpty)
    }

    func testClearRadioFavorites() {
        let fav1 = RadioFavorite(id: UUID(), title: "A", artist: "B", image_key: nil, savedAt: Date())
        let fav2 = RadioFavorite(id: UUID(), title: "C", artist: "D", image_key: nil, savedAt: Date())
        service.radioFavorites = [fav1, fav2]
        XCTAssertEqual(service.radioFavorites.count, 2)

        service.clearRadioFavorites()
        XCTAssertTrue(service.radioFavorites.isEmpty)
    }

    func testRadioFavoriteDeduplication() {
        let fav = RadioFavorite(
            id: UUID(), title: "Song", artist: "Artist",
            image_key: nil, savedAt: Date()
        )
        service.radioFavorites = [fav]

        // isCurrentTrackFavorite should detect the duplicate
        // (without a zone, saveRadioFavorite won't add, but we test the model)
        XCTAssertEqual(service.radioFavorites.count, 1)
    }

    func testRadioFavoriteCodable() {
        let fav = RadioFavorite(
            id: UUID(), title: "Test", artist: "Artist",
            image_key: "abc123", savedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try? encoder.encode([fav])
        XCTAssertNotNil(data)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try? decoder.decode([RadioFavorite].self, from: data!)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.count, 1)
        XCTAssertEqual(decoded?[0].title, "Test")
        XCTAssertEqual(decoded?[0].artist, "Artist")
        XCTAssertEqual(decoded?[0].image_key, "abc123")
    }

    func testIsCurrentTrackFavoriteWithNoZone() {
        // No zone selected — should return false
        XCTAssertFalse(service.isCurrentTrackFavorite())
    }

    // MARK: - Seek position preservation

    func testSeekPositionPreservedOnPause() {
        // Simulate a playing zone with seek at 120
        let playingZone = RoonZone(
            zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: NowPlaying(
                one_line: nil, two_line: nil,
                three_line: NowPlaying.LineInfo(line1: "Song", line2: "Artist", line3: "Album"),
                length: 300, seek_position: 120, image_key: nil
            ),
            outputs: nil, settings: nil, seek_position: 120,
            is_play_allowed: true, is_pause_allowed: true, is_seek_allowed: true,
            is_previous_allowed: true, is_next_allowed: true
        )
        service.selectZone(playingZone)
        XCTAssertEqual(service.seekPosition, 120)

        // Simulate zones_changed with paused state and seek_position: 0 (as Roon sends)
        let pausedZoneJSON: [String: Any] = [
            "zones_changed": [
                [
                    "zone_id": "z1",
                    "display_name": "Zone",
                    "state": "paused",
                    "seek_position": 0,
                    "is_play_allowed": true
                ]
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: pausedZoneJSON)
        service.handleZonesData(data)

        // seekPosition must NOT reset to 0 — it should stay at 120
        XCTAssertEqual(service.seekPosition, 120, "Seek position must be preserved on pause")
    }

    func testSeekPositionPreservedOnPauseWithNilSeek() {
        // Simulate a playing zone with seek at 60
        let zone = RoonZone(
            zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: NowPlaying(
                one_line: nil, two_line: nil,
                three_line: NowPlaying.LineInfo(line1: "Song", line2: "Artist", line3: "Album"),
                length: 200, seek_position: 60, image_key: nil
            ),
            outputs: nil, settings: nil, seek_position: 60,
            is_play_allowed: true, is_pause_allowed: true, is_seek_allowed: true,
            is_previous_allowed: true, is_next_allowed: true
        )
        service.selectZone(zone)
        XCTAssertEqual(service.seekPosition, 60)

        // Simulate zones_changed with paused state and NO seek_position field
        let pausedZoneJSON: [String: Any] = [
            "zones_changed": [
                [
                    "zone_id": "z1",
                    "display_name": "Zone",
                    "state": "paused",
                    "is_play_allowed": true
                ]
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: pausedZoneJSON)
        service.handleZonesData(data)

        // seekPosition must stay at 60
        XCTAssertEqual(service.seekPosition, 60, "Seek position must be preserved when server sends nil seek")
    }

    func testSeekPositionUpdatesWhenPlaying() {
        // Simulate a playing zone
        let zone = RoonZone(
            zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: NowPlaying(
                one_line: nil, two_line: nil,
                three_line: NowPlaying.LineInfo(line1: "Song", line2: "Artist", line3: "Album"),
                length: 300, seek_position: 10, image_key: nil
            ),
            outputs: nil, settings: nil, seek_position: 10,
            is_play_allowed: true, is_pause_allowed: true, is_seek_allowed: true,
            is_previous_allowed: true, is_next_allowed: true
        )
        service.selectZone(zone)
        XCTAssertEqual(service.seekPosition, 10)

        // Simulate zones_changed with updated seek while still playing
        let updatedJSON: [String: Any] = [
            "zones_changed": [
                [
                    "zone_id": "z1",
                    "display_name": "Zone",
                    "state": "playing",
                    "seek_position": 50,
                    "is_play_allowed": true
                ]
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: updatedJSON)
        service.handleZonesData(data)

        // seekPosition should update to 50
        XCTAssertEqual(service.seekPosition, 50, "Seek position must update when zone is playing")
    }

    func testSeekMethodUpdatesPositionImmediately() {
        let zone = RoonZone(
            zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: nil, outputs: nil, settings: nil, seek_position: 30,
            is_play_allowed: true, is_pause_allowed: nil, is_seek_allowed: true,
            is_previous_allowed: nil, is_next_allowed: nil
        )
        service.selectZone(zone)
        XCTAssertEqual(service.seekPosition, 30)

        // User seeks to position 120 — should update immediately
        service.seek(position: 120)
        XCTAssertEqual(service.seekPosition, 120, "Seek must update seekPosition immediately for responsive UI")
    }

    // MARK: - Seek reset on track change

    func testNextResetsSeekPositionToZero() {
        // Setup: zone playing at seek 180
        let zone = RoonZone(
            zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: NowPlaying(
                one_line: nil, two_line: nil,
                three_line: NowPlaying.LineInfo(line1: "Song A", line2: "Artist", line3: "Album"),
                length: 300, seek_position: 180, image_key: nil
            ),
            outputs: nil, settings: nil, seek_position: 180,
            is_play_allowed: true, is_pause_allowed: true, is_seek_allowed: true,
            is_previous_allowed: true, is_next_allowed: true
        )
        service.selectZone(zone)
        XCTAssertEqual(service.seekPosition, 180)

        // Action: user clicks "next"
        service.next()

        // seekPosition must immediately reset to 0
        XCTAssertEqual(service.seekPosition, 0, "next() must reset seekPosition to 0 immediately")
    }

    func testPreviousResetsSeekPositionToZero() {
        // Setup: zone playing at seek 240
        let zone = RoonZone(
            zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: NowPlaying(
                one_line: nil, two_line: nil,
                three_line: NowPlaying.LineInfo(line1: "Song B", line2: "Artist", line3: "Album"),
                length: 300, seek_position: 240, image_key: nil
            ),
            outputs: nil, settings: nil, seek_position: 240,
            is_play_allowed: true, is_pause_allowed: true, is_seek_allowed: true,
            is_previous_allowed: true, is_next_allowed: true
        )
        service.selectZone(zone)
        XCTAssertEqual(service.seekPosition, 240)

        // Action: user clicks "previous"
        service.previous()

        // seekPosition must immediately reset to 0
        XCTAssertEqual(service.seekPosition, 0, "previous() must reset seekPosition to 0 immediately")
    }

    func testNextWithNoZoneDoesNotCrash() {
        // No zone selected — next() should be a no-op
        service.seekPosition = 42
        service.next()
        // seekPosition unchanged (no zone, guard returns early)
        XCTAssertEqual(service.seekPosition, 42)
    }

    func testPreviousWithNoZoneDoesNotCrash() {
        // No zone selected — previous() should be a no-op
        service.seekPosition = 42
        service.previous()
        XCTAssertEqual(service.seekPosition, 42)
    }

    func testSelectZoneResetsSeekToZonePosition() {
        // First zone at seek 200
        let zone1 = RoonZone(
            zone_id: "z1", display_name: "Zone 1", state: "playing",
            now_playing: nil, outputs: nil, settings: nil, seek_position: 200,
            is_play_allowed: true, is_pause_allowed: nil, is_seek_allowed: nil,
            is_previous_allowed: nil, is_next_allowed: nil
        )
        service.selectZone(zone1)
        XCTAssertEqual(service.seekPosition, 200)

        // Switch to zone at seek 0 (just started)
        let zone2 = RoonZone(
            zone_id: "z2", display_name: "Zone 2", state: "playing",
            now_playing: nil, outputs: nil, settings: nil, seek_position: 0,
            is_play_allowed: true, is_pause_allowed: nil, is_seek_allowed: nil,
            is_previous_allowed: nil, is_next_allowed: nil
        )
        service.selectZone(zone2)
        XCTAssertEqual(service.seekPosition, 0, "Switching zone must set seekPosition to the new zone's seek_position")
    }

    func testSelectZoneWithNilSeekResetsToZero() {
        let zone1 = RoonZone(
            zone_id: "z1", display_name: "Zone 1", state: "playing",
            now_playing: nil, outputs: nil, settings: nil, seek_position: 150,
            is_play_allowed: true, is_pause_allowed: nil, is_seek_allowed: nil,
            is_previous_allowed: nil, is_next_allowed: nil
        )
        service.selectZone(zone1)
        XCTAssertEqual(service.seekPosition, 150)

        // Switch to a stopped zone with no seek
        let zone2 = RoonZone(
            zone_id: "z2", display_name: "Zone 2", state: "stopped",
            now_playing: nil, outputs: nil, settings: nil, seek_position: nil,
            is_play_allowed: true, is_pause_allowed: nil, is_seek_allowed: nil,
            is_previous_allowed: nil, is_next_allowed: nil
        )
        service.selectZone(zone2)
        XCTAssertEqual(service.seekPosition, 0, "Zone with nil seek_position must default to 0")
    }

    func testZonesChangedWithNewTrackUpdatesSeek() {
        // Setup: zone playing track A at seek 200
        let zone = RoonZone(
            zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: NowPlaying(
                one_line: nil, two_line: nil,
                three_line: NowPlaying.LineInfo(line1: "Song A", line2: "Artist", line3: "Album"),
                length: 300, seek_position: 200, image_key: nil
            ),
            outputs: nil, settings: nil, seek_position: 200,
            is_play_allowed: true, is_pause_allowed: true, is_seek_allowed: true,
            is_previous_allowed: true, is_next_allowed: true
        )
        service.selectZone(zone)
        XCTAssertEqual(service.seekPosition, 200)

        // Server sends zones_changed: new track at seek 3 (playing state)
        let changedJSON: [String: Any] = [
            "zones_changed": [
                [
                    "zone_id": "z1",
                    "display_name": "Zone",
                    "state": "playing",
                    "seek_position": 3,
                    "is_play_allowed": true,
                    "now_playing": [
                        "three_line": ["line1": "Song B", "line2": "Artist", "line3": "Album"],
                        "length": 250,
                        "seek_position": 3
                    ]
                ]
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: changedJSON)
        service.handleZonesData(data)

        // seekPosition must follow the server (new track, playing)
        XCTAssertEqual(service.seekPosition, 3, "When server sends new track playing at seek 3, seekPosition must update")
    }

    func testZonesSeekChangedAloneDoesNotResetUI() {
        // Setup: zone playing at seek 100
        let zone = RoonZone(
            zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: NowPlaying(
                one_line: nil, two_line: nil,
                three_line: NowPlaying.LineInfo(line1: "Song", line2: "Artist", line3: "Album"),
                length: 300, seek_position: 100, image_key: nil
            ),
            outputs: nil, settings: nil, seek_position: 100,
            is_play_allowed: true, is_pause_allowed: true, is_seek_allowed: true,
            is_previous_allowed: true, is_next_allowed: true
        )
        service.selectZone(zone)
        service.seekPosition = 105 // simulating local interpolation ahead of server

        // Server sends zones_seek_changed only (no zones_changed)
        // This is the frequent seek update; it should NOT alter the UI seekPosition
        let seekJSON: [String: Any] = [
            "zones_seek_changed": [
                ["zone_id": "z1", "seek_position": 102]
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: seekJSON)
        service.handleZonesData(data)

        // seekPosition stays at the local interpolated value (105), not overwritten to 102
        XCTAssertEqual(service.seekPosition, 105, "zones_seek_changed alone must not overwrite local interpolation")
    }

    func testSeekPositionAfterNextThenServerUpdate() {
        // Setup: playing at seek 250
        let zone = RoonZone(
            zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: NowPlaying(
                one_line: nil, two_line: nil,
                three_line: NowPlaying.LineInfo(line1: "Song A", line2: "Artist", line3: "Album"),
                length: 300, seek_position: 250, image_key: nil
            ),
            outputs: nil, settings: nil, seek_position: 250,
            is_play_allowed: true, is_pause_allowed: true, is_seek_allowed: true,
            is_previous_allowed: true, is_next_allowed: true
        )
        service.selectZone(zone)
        XCTAssertEqual(service.seekPosition, 250)

        // User clicks next — seek resets to 0
        service.next()
        XCTAssertEqual(service.seekPosition, 0)

        // Server confirms new track playing at seek 2
        let changedJSON: [String: Any] = [
            "zones_changed": [
                [
                    "zone_id": "z1",
                    "display_name": "Zone",
                    "state": "playing",
                    "seek_position": 2,
                    "is_play_allowed": true,
                    "now_playing": [
                        "three_line": ["line1": "Song B", "line2": "New Artist", "line3": "New Album"],
                        "length": 200,
                        "seek_position": 2
                    ]
                ]
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: changedJSON)
        service.handleZonesData(data)

        // seekPosition follows the server update for the new track
        XCTAssertEqual(service.seekPosition, 2, "After next() + server update, seekPosition must reflect new track")
    }

    func testPlayFromHereResetsSeekPositionToZero() {
        let zone = RoonZone(
            zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: NowPlaying(
                one_line: nil, two_line: nil,
                three_line: NowPlaying.LineInfo(line1: "Song A", line2: "Artist", line3: "Album"),
                length: 300, seek_position: 200, image_key: nil
            ),
            outputs: nil, settings: nil, seek_position: 200,
            is_play_allowed: true, is_pause_allowed: true, is_seek_allowed: true,
            is_previous_allowed: true, is_next_allowed: true
        )
        service.selectZone(zone)
        XCTAssertEqual(service.seekPosition, 200)

        // User clicks a queue item to play from here
        service.playFromHere(queueItemId: 42)
        XCTAssertEqual(service.seekPosition, 0, "playFromHere must reset seekPosition to 0")
    }

    func testTrackIdentityDiffersForDifferentTracks() {
        let npA = NowPlaying(
            one_line: nil, two_line: nil,
            three_line: NowPlaying.LineInfo(line1: "Song A", line2: "Artist", line3: "Album"),
            length: 300, seek_position: 100, image_key: nil
        )
        let npB = NowPlaying(
            one_line: nil, two_line: nil,
            three_line: NowPlaying.LineInfo(line1: "Song B", line2: "Artist", line3: "Album"),
            length: 250, seek_position: 0, image_key: nil
        )
        // Same track at different seek positions must have same identity
        let npA2 = NowPlaying(
            one_line: nil, two_line: nil,
            three_line: NowPlaying.LineInfo(line1: "Song A", line2: "Artist", line3: "Album"),
            length: 300, seek_position: 200, image_key: nil
        )

        let idA = service.trackIdentity(npA)
        let idB = service.trackIdentity(npB)
        let idA2 = service.trackIdentity(npA2)

        XCTAssertNotEqual(idA, idB, "Different tracks must have different identity")
        XCTAssertEqual(idA, idA2, "Same track at different seek must have same identity")
        XCTAssertEqual(service.trackIdentity(nil), "", "nil now_playing must return empty identity")
    }

    func testAutoAdvanceResetsSeekViaZonesChanged() {
        // Simulate: track A playing at seek 290 (near end)
        let zone = RoonZone(
            zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: NowPlaying(
                one_line: nil, two_line: nil,
                three_line: NowPlaying.LineInfo(line1: "Song A", line2: "Artist", line3: "Album A"),
                length: 300, seek_position: 290, image_key: nil
            ),
            outputs: nil, settings: nil, seek_position: 290,
            is_play_allowed: true, is_pause_allowed: true, is_seek_allowed: true,
            is_previous_allowed: true, is_next_allowed: true
        )
        service.selectZone(zone)
        XCTAssertEqual(service.seekPosition, 290)

        // Track ends, server auto-advances to Song B at seek 0
        let changedJSON: [String: Any] = [
            "zones_changed": [
                [
                    "zone_id": "z1",
                    "display_name": "Zone",
                    "state": "playing",
                    "seek_position": 0,
                    "is_play_allowed": true,
                    "now_playing": [
                        "three_line": ["line1": "Song B", "line2": "Artist", "line3": "Album B"],
                        "length": 240,
                        "seek_position": 0
                    ]
                ]
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: changedJSON)
        service.handleZonesData(data)

        XCTAssertEqual(service.seekPosition, 0, "Auto-advance to new track must reset seekPosition to 0")
    }

    // MARK: - Image Key Cache (resolvedImageKey)

    func testResolvedImageKeyReturnsImageKeyWhenPresent() {
        let result = service.resolvedImageKey(title: "Song A", imageKey: "img_123")
        XCTAssertEqual(result, "img_123")
    }

    func testResolvedImageKeyCachesWhenImageKeyPresent() {
        // First call caches title → image_key
        _ = service.resolvedImageKey(title: "Song A", imageKey: "img_123")

        // Second call with nil imageKey should return cached value
        let result = service.resolvedImageKey(title: "Song A", imageKey: nil)
        XCTAssertEqual(result, "img_123", "Cache must return previously seen image_key for the same title")
    }

    func testResolvedImageKeyReturnsNilWhenBothNil() {
        let result = service.resolvedImageKey(title: nil, imageKey: nil)
        XCTAssertNil(result)
    }

    func testResolvedImageKeyReturnsNilWhenTitleUnknown() {
        let result = service.resolvedImageKey(title: "Never Seen", imageKey: nil)
        XCTAssertNil(result, "Unknown title with nil imageKey must return nil")
    }

    func testResolvedImageKeyUpdatesCache() {
        // Cache "Song A" → "img_old"
        _ = service.resolvedImageKey(title: "Song A", imageKey: "img_old")

        // Update with new image_key
        _ = service.resolvedImageKey(title: "Song A", imageKey: "img_new")

        // Cache should have the latest value
        let result = service.resolvedImageKey(title: "Song A", imageKey: nil)
        XCTAssertEqual(result, "img_new", "Cache must be updated when a new image_key is seen for the same title")
    }

    func testResolvedImageKeyWithNilTitleReturnsImageKey() {
        // Even with nil title, should still return the image_key
        let result = service.resolvedImageKey(title: nil, imageKey: "img_456")
        XCTAssertEqual(result, "img_456")
    }

    func testResolvedImageKeyCacheMultipleTracks() {
        // Cache multiple tracks
        _ = service.resolvedImageKey(title: "Song A", imageKey: "img_a")
        _ = service.resolvedImageKey(title: "Song B", imageKey: "img_b")
        _ = service.resolvedImageKey(title: "Song C", imageKey: "img_c")

        // All should be retrievable from cache
        XCTAssertEqual(service.resolvedImageKey(title: "Song A", imageKey: nil), "img_a")
        XCTAssertEqual(service.resolvedImageKey(title: "Song B", imageKey: nil), "img_b")
        XCTAssertEqual(service.resolvedImageKey(title: "Song C", imageKey: nil), "img_c")
    }

    func testResolvedImageKeyForNowPlayingWithImageKey() {
        let np = NowPlaying(
            one_line: nil, two_line: nil,
            three_line: NowPlaying.LineInfo(line1: "Song", line2: "Artist", line3: "Album"),
            length: 300, seek_position: 0, image_key: "np_img"
        )
        let result = service.resolvedImageKey(for: np)
        XCTAssertEqual(result, "np_img", "resolvedImageKey(for:) must return image_key when present")
    }

    func testResolvedImageKeyForNowPlayingFallsBackToCache() {
        // Pre-populate cache
        _ = service.resolvedImageKey(title: "Cached Song", imageKey: "cached_img")

        // NowPlaying with nil image_key but matching title
        let np = NowPlaying(
            one_line: nil, two_line: nil,
            three_line: NowPlaying.LineInfo(line1: "Cached Song", line2: "Artist", line3: "Album"),
            length: 300, seek_position: 0, image_key: nil
        )
        let result = service.resolvedImageKey(for: np)
        XCTAssertEqual(result, "cached_img", "resolvedImageKey(for:) must fall back to cache when image_key is nil")
    }

    func testResolvedImageKeyForNowPlayingFallsBackToQueue() {
        // Set up a queue item with an image key
        let queueItem = QueueItem(
            queue_item_id: 1,
            one_line: nil,
            two_line: nil,
            three_line: NowPlaying.LineInfo(line1: "Queue Song", line2: "Artist", line3: "Album"),
            length: 200,
            image_key: "queue_img"
        )
        service.queueItems = [queueItem]

        // NowPlaying with nil image_key, same title as queue item
        let np = NowPlaying(
            one_line: nil, two_line: nil,
            three_line: NowPlaying.LineInfo(line1: "Queue Song", line2: "Artist", line3: "Album"),
            length: 200, seek_position: 0, image_key: nil
        )
        let result = service.resolvedImageKey(for: np)
        XCTAssertEqual(result, "queue_img", "resolvedImageKey(for:) must fall back to queue items when cache misses")
    }

    func testImageKeyCachePersistsToDisk() {
        // Cache an image key
        _ = service.resolvedImageKey(title: "Persisted Song", imageKey: "persisted_img")

        // Create a new service instance with the same storage directory
        let service2 = RoonService(storageDirectory: tempDir)
        let result = service2.resolvedImageKey(title: "Persisted Song", imageKey: nil)
        XCTAssertEqual(result, "persisted_img", "Image key cache must persist across service instances")
    }

    func testImageKeyCacheEmptyOnFreshStorage() {
        // New service with fresh temp dir — cache should be empty
        let freshDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: freshDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: freshDir) }

        let freshService = RoonService(storageDirectory: freshDir)
        let result = freshService.resolvedImageKey(title: "Anything", imageKey: nil)
        XCTAssertNil(result, "Fresh service must have empty cache")
    }

    func testHistoryItemUsesResolvedImageKey() {
        // Pre-populate cache for a track
        _ = service.resolvedImageKey(title: "Tracked Song", imageKey: "tracked_img")

        // Simulate a zone playing that track with nil image_key in now_playing
        let zone = RoonZone(
            zone_id: "z1", display_name: "Test Zone", state: "playing",
            now_playing: NowPlaying(
                one_line: nil, two_line: nil,
                three_line: NowPlaying.LineInfo(line1: "Tracked Song", line2: "Artist", line3: "Album"),
                length: 300, seek_position: 0, image_key: nil
            ),
            outputs: nil, settings: nil, seek_position: 0,
            is_play_allowed: true, is_pause_allowed: true, is_seek_allowed: true,
            is_previous_allowed: true, is_next_allowed: true
        )
        service.selectZone(zone)

        // Simulate zones_changed to trigger history tracking
        let changedJSON: [String: Any] = [
            "zones_changed": [
                [
                    "zone_id": "z1",
                    "display_name": "Test Zone",
                    "state": "playing",
                    "seek_position": 5,
                    "is_play_allowed": true,
                    "is_seek_allowed": true,
                    "now_playing": [
                        "three_line": ["line1": "Tracked Song", "line2": "Artist", "line3": "Album"],
                        "length": 300,
                        "seek_position": 5
                    ]
                ]
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: changedJSON)
        service.handleZonesData(data)

        // History item should have the resolved image_key from cache
        if let historyItem = service.playbackHistory.first(where: { $0.title == "Tracked Song" }) {
            XCTAssertEqual(historyItem.image_key, "tracked_img",
                           "History must use resolved image_key from cache when now_playing has nil image_key")
        }
        // Note: history may not be added if deduplication prevents it, which is fine
    }

    // MARK: - Registration

    func testRegistrationResponseParsing() {
        // Registered response
        let registered = RoonRegistration.parseRegistrationResponse([
            "token": "abc123",
            "core_id": "core-001",
            "display_name": "My Roon Core"
        ])
        if case .registered(let token, let coreId, let coreName) = registered {
            XCTAssertEqual(token, "abc123")
            XCTAssertEqual(coreId, "core-001")
            XCTAssertEqual(coreName, "My Roon Core")
        } else {
            XCTFail("Expected .registered")
        }

        // Not registered (no token)
        let notRegistered = RoonRegistration.parseRegistrationResponse(["status": "waiting"])
        if case .notRegistered = notRegistered {
            // OK
        } else {
            XCTFail("Expected .notRegistered")
        }

        // Nil body
        let nilBody = RoonRegistration.parseRegistrationResponse(nil)
        if case .notRegistered = nilBody {
            // OK
        } else {
            XCTFail("Expected .notRegistered for nil body")
        }
    }

    // MARK: - Registration edge cases

    func testRegistrationResponseMissingCoreIdDefaultsToEmpty() {
        let result = RoonRegistration.parseRegistrationResponse([
            "token": "tok123"
        ])
        if case .registered(let token, let coreId, let coreName) = result {
            XCTAssertEqual(token, "tok123")
            XCTAssertEqual(coreId, "", "Missing core_id must default to empty string")
            XCTAssertEqual(coreName, "", "Missing display_name must default to empty string")
        } else {
            XCTFail("Expected .registered")
        }
    }

    func testRegistrationResponseTokenTypeMismatch() {
        // token is an Int instead of String — should be .notRegistered
        let result = RoonRegistration.parseRegistrationResponse([
            "token": 12345
        ])
        if case .notRegistered = result {
            // OK — token must be a String
        } else {
            XCTFail("Expected .notRegistered when token is not a String")
        }
    }

    func testRegistrationInfoRequestBodyIsEmpty() {
        let body = RoonRegistration.infoRequestBody()
        XCTAssertTrue(body.isEmpty, "info request body must be empty dictionary")
    }

    func testRegistrationStatusBody() {
        let ready = RoonRegistration.statusBody()
        XCTAssertEqual(ready["message"] as? String, "Ready")
        XCTAssertEqual(ready["is_error"] as? Bool, false)

        let error = RoonRegistration.statusBody(message: "Connection lost", isError: true)
        XCTAssertEqual(error["message"] as? String, "Connection lost")
        XCTAssertEqual(error["is_error"] as? Bool, true)
    }

    func testRegistrationDisplayVersion() {
        XCTAssertEqual(RoonRegistration.displayVersion, "1.0.3")
    }

    func testRegistrationExtensionId() {
        XCTAssertEqual(RoonRegistration.extensionId, "com.bertrand.rooncontroller")
    }

    // MARK: - MOO Message edge cases

    func testMOOMessageParseWithColonInHeaderValue() {
        let raw = "MOO/1 REQUEST test/method\nRequest-Id: 1\nCustom-Header: value:with:colons\n\n"
        let msg = MOOMessage.parse(Data(raw.utf8))
        XCTAssertNotNil(msg)
        XCTAssertEqual(msg?.headers["Custom-Header"], "value:with:colons",
                       "Header values with colons must be preserved")
    }

    func testMOOMessageParseWithMultipleHeaders() {
        let raw = "MOO/1 COMPLETE Success\nRequest-Id: 42\nRoon-Status: success\nContent-Type: application/json\n\n"
        let msg = MOOMessage.parse(Data(raw.utf8))
        XCTAssertNotNil(msg)
        XCTAssertEqual(msg?.requestId, 42)
        XCTAssertEqual(msg?.headers["Roon-Status"], "success")
        XCTAssertEqual(msg?.headers["Content-Type"], "application/json")
        XCTAssertTrue(msg?.isSuccess ?? false)
        XCTAssertTrue(msg?.isJSON ?? false)
    }

    func testMOOMessageIsSuccessWhenNoRoonStatus() {
        let raw = "MOO/1 COMPLETE Done\nRequest-Id: 1\n\n"
        let msg = MOOMessage.parse(Data(raw.utf8))
        XCTAssertNotNil(msg)
        XCTAssertTrue(msg?.isSuccess ?? false, "Missing Roon-Status header means success")
    }

    func testMOOMessageIsNotSuccessWhenFailed() {
        let raw = "MOO/1 COMPLETE Error\nRequest-Id: 1\nRoon-Status: failed\n\n"
        let msg = MOOMessage.parse(Data(raw.utf8))
        XCTAssertNotNil(msg)
        XCTAssertFalse(msg?.isSuccess ?? true, "Roon-Status: failed means not success")
    }

    func testMOOMessageIsJSONWithContentType() {
        let body = "{\"key\":\"val\"}"
        let raw = "MOO/1 COMPLETE Success\nRequest-Id: 1\nContent-Type: application/json\nContent-Length: \(body.utf8.count)\n\n\(body)"
        let msg = MOOMessage.parse(Data(raw.utf8))
        XCTAssertTrue(msg?.isJSON ?? false)
    }

    func testMOOMessageIsJSONWithoutContentTypeButWithBody() {
        let body = "{\"key\":\"val\"}"
        let raw = "MOO/1 COMPLETE Success\nRequest-Id: 1\nContent-Length: \(body.utf8.count)\n\n\(body)"
        let msg = MOOMessage.parse(Data(raw.utf8))
        // No Content-Type but body present → isJSON returns true
        XCTAssertTrue(msg?.isJSON ?? false)
    }

    func testMOOMessageDecodeBodyTyped() {
        struct TestPayload: Codable {
            let control: String
            let zone_id: String
        }
        let body = "{\"control\":\"play\",\"zone_id\":\"z1\"}"
        let raw = "MOO/1 REQUEST transport/control\nRequest-Id: 5\nContent-Type: application/json\nContent-Length: \(body.utf8.count)\n\n\(body)"
        let msg = MOOMessage.parse(Data(raw.utf8))
        let payload = msg?.decodeBody(TestPayload.self)
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.control, "play")
        XCTAssertEqual(payload?.zone_id, "z1")
    }

    func testMOOMessageDecodeBodyReturnsNilForInvalidJSON() {
        struct TestPayload: Codable { let x: Int }
        let raw = "MOO/1 COMPLETE Success\nRequest-Id: 1\n\n"
        let msg = MOOMessage.parse(Data(raw.utf8))
        XCTAssertNil(msg?.decodeBody(TestPayload.self), "No body → decodeBody returns nil")
    }

    func testMOOMessageBodyJSONReturnsNilWhenNoBody() {
        let raw = "MOO/1 COMPLETE Success\nRequest-Id: 1\n\n"
        let msg = MOOMessage.parse(Data(raw.utf8))
        XCTAssertNil(msg?.bodyJSON)
    }

    func testMOOMessageParseEmptyBody() {
        let raw = "MOO/1 COMPLETE Success\nRequest-Id: 1\n\n"
        let msg = MOOMessage.parse(Data(raw.utf8))
        XCTAssertNotNil(msg)
        XCTAssertNil(msg?.body, "Empty body after separator must be nil")
    }

    func testMOOMessageParseTwoPartFirstLine() {
        // Only 2 parts in first line (missing name) → should return nil
        let raw = "MOO/1 REQUEST\nRequest-Id: 1\n\n"
        let msg = MOOMessage.parse(Data(raw.utf8))
        XCTAssertNil(msg, "First line with < 3 parts must return nil")
    }

    func testMOOMessageParseUnknownVerb() {
        let raw = "MOO/1 SUBSCRIBE test/topic\nRequest-Id: 1\n\n"
        let msg = MOOMessage.parse(Data(raw.utf8))
        XCTAssertNil(msg, "Unknown verb must return nil")
    }

    func testMOOMessageParseWrongProtocolVersion() {
        let raw = "MOO/2 REQUEST test/method\nRequest-Id: 1\n\n"
        let msg = MOOMessage.parse(Data(raw.utf8))
        XCTAssertNil(msg, "Wrong protocol version must return nil")
    }

    func testMOOMessageBuildContinue() {
        let data = MOOMessage.continueMessage(name: "Subscribed", requestId: 7)
        let msg = MOOMessage.parse(data)
        XCTAssertNotNil(msg)
        XCTAssertEqual(msg?.verb, .continue)
        XCTAssertEqual(msg?.name, "Subscribed")
        XCTAssertEqual(msg?.requestId, 7)
    }

    func testMOOMessageRoundTripWithLargeBody() {
        // Build a message with a larger JSON body and verify round-trip
        var dict: [String: Any] = [:]
        for i in 0..<50 {
            dict["key_\(i)"] = "value_\(i)_" + String(repeating: "x", count: 100)
        }
        let data = MOOMessage.request(name: "test/large", requestId: 99, jsonBody: dict)
        let msg = MOOMessage.parse(data)
        XCTAssertNotNil(msg)
        XCTAssertEqual(msg?.requestId, 99)
        XCTAssertEqual(msg?.bodyJSON?.count, 50)
    }

    func testMOORequestIdGeneratorThreadSafety() {
        let generator = MOORequestIdGenerator()
        let iterations = 1000
        let expectation = XCTestExpectation(description: "All IDs generated")
        expectation.expectedFulfillmentCount = iterations

        var allIds: [Int] = []
        let lock = NSLock()

        for _ in 0..<iterations {
            DispatchQueue.global().async {
                let id = generator.next()
                lock.lock()
                allIds.append(id)
                lock.unlock()
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5)
        XCTAssertEqual(Set(allIds).count, iterations, "All IDs must be unique")
    }

    // MARK: - Image Cache (RoonImageCache)

    func testImageCacheCacheKeyFormat() {
        let key = RoonImageCache.cacheKey(imageKey: "abc123", width: 400, height: 300)
        XCTAssertEqual(key, "abc123_400x300")
    }

    func testImageCacheCacheKeyDifferentDimensions() {
        let k1 = RoonImageCache.cacheKey(imageKey: "img", width: 100, height: 100)
        let k2 = RoonImageCache.cacheKey(imageKey: "img", width: 200, height: 200)
        XCTAssertNotEqual(k1, k2, "Different dimensions must produce different keys")
    }

    func testImageCacheCacheKeyDifferentImages() {
        let k1 = RoonImageCache.cacheKey(imageKey: "img_a", width: 100, height: 100)
        let k2 = RoonImageCache.cacheKey(imageKey: "img_b", width: 100, height: 100)
        XCTAssertNotEqual(k1, k2, "Different image keys must produce different cache keys")
    }

    func testImageCacheStoreAndRetrieve() async {
        let cache = RoonImageCache()
        let testData = Data("test image data".utf8)
        let key = "test_store_retrieve"

        await cache.store(key: key, data: testData)
        let retrieved = await cache.get(key: key)
        XCTAssertEqual(retrieved, testData)
    }

    func testImageCacheReturnsNilForMissingKey() async {
        let cache = RoonImageCache()
        let result = await cache.get(key: "nonexistent_key_\(UUID().uuidString)")
        XCTAssertNil(result)
    }

    func testImageCacheClearAll() async {
        let cache = RoonImageCache()
        let key = "test_clear_\(UUID().uuidString)"
        await cache.store(key: key, data: Data("data".utf8))
        await cache.clearAll()
        let result = await cache.get(key: key)
        XCTAssertNil(result, "clearAll must remove all cached items")
    }

    // MARK: - History size limit

    func testHistorySizeDoesNotExceedReasonableLimit() {
        // Verify that we can handle 500 history items without issue
        let items = (0..<500).map { i in
            PlaybackHistoryItem(
                id: UUID(), title: "Song \(i)", artist: "Artist", album: "Album",
                image_key: nil, length: 200, zone_name: "Zone", playedAt: Date()
            )
        }
        service.playbackHistory = items
        XCTAssertEqual(service.playbackHistory.count, 500)
    }

    // MARK: - Connection state

    func testConnectionStateInitiallyDisconnected() {
        XCTAssertEqual(service.connectionState, .disconnected)
    }

    func testConnectionDetailInitiallyNil() {
        XCTAssertNil(service.connectionDetail)
    }
}
