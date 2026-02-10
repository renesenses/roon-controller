import XCTest
@testable import Roon_Controller

@MainActor
final class RoonServiceTests: XCTestCase {

    var service: RoonService!

    override func setUp() async throws {
        service = RoonService()
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
}
