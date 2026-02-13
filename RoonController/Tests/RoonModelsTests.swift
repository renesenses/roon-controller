import XCTest
@testable import Roon_Controller

final class RoonModelsTests: XCTestCase {

    // MARK: - BrowseItem decoding

    func testBrowseItemDecodesInputPromptAsObject() throws {
        let json = """
        {
            "title": "Search",
            "subtitle": null,
            "image_key": null,
            "item_key": "150:0",
            "hint": "list",
            "input_prompt": {"prompt": "Search", "action": "Go"}
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(BrowseItem.self, from: json)
        XCTAssertEqual(item.title, "Search")
        XCTAssertEqual(item.item_key, "150:0")
        XCTAssertEqual(item.input_prompt?.prompt, "Search")
        XCTAssertEqual(item.input_prompt?.action, "Go")
    }

    func testBrowseItemDecodesWithoutInputPrompt() throws {
        let json = """
        {
            "title": "Artists",
            "subtitle": null,
            "image_key": null,
            "item_key": "150:1",
            "hint": "list"
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(BrowseItem.self, from: json)
        XCTAssertEqual(item.title, "Artists")
        XCTAssertNil(item.input_prompt)
    }

    func testBrowseItemIdUsesItemKey() {
        let json = """
        {"title": "Test", "item_key": "abc:123", "hint": "list"}
        """.data(using: .utf8)!

        let item = try! JSONDecoder().decode(BrowseItem.self, from: json)
        XCTAssertEqual(item.id, "abc:123")
    }

    func testBrowseItemIdFallsBackToTitle() {
        let json = """
        {"title": "Fallback", "hint": "list"}
        """.data(using: .utf8)!

        let item = try! JSONDecoder().decode(BrowseItem.self, from: json)
        XCTAssertEqual(item.id, "Fallback")
    }

    // MARK: - WSBrowseResultMessage decoding with mixed items

    func testWSBrowseResultDecodesWithInputPromptItems() throws {
        let json = """
        {
            "type": "browse_result",
            "action": "list",
            "list": {"title": "Library", "count": 6, "level": 1},
            "items": [
                {"title": "Search", "item_key": "150:0", "hint": "list", "input_prompt": {"prompt": "Search", "action": "Go"}},
                {"title": "Artists", "item_key": "150:1", "hint": "list"},
                {"title": "Albums", "item_key": "150:2", "hint": "list"},
                {"title": "Tracks", "item_key": "150:3", "hint": "list"},
                {"title": "Composers", "item_key": "150:4", "hint": "list"},
                {"title": "Tags", "item_key": "150:5", "hint": "list"}
            ],
            "offset": 0
        }
        """.data(using: .utf8)!

        let msg = try JSONDecoder().decode(WSBrowseResultMessage.self, from: json)
        XCTAssertEqual(msg.items?.count, 6)
        XCTAssertEqual(msg.items?[0].title, "Search")
        XCTAssertNotNil(msg.items?[0].input_prompt)
        XCTAssertEqual(msg.items?[3].title, "Tracks")
        XCTAssertNil(msg.items?[3].input_prompt)
    }

    // MARK: - BrowseResult pagination

    func testBrowseResultItemsAreMutable() {
        var result = BrowseResult(
            action: "list",
            list: BrowseList(title: "Tracks", count: 200, image_key: nil, level: 2),
            items: [BrowseItem](),
            offset: 0
        )

        let json = """
        {"title": "Track 1", "item_key": "1:0", "hint": "action_list"}
        """.data(using: .utf8)!
        let item = try! JSONDecoder().decode(BrowseItem.self, from: json)

        result.items.append(item)
        result.offset = 1
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.offset, 1)
    }

    // MARK: - PlaybackHistoryItem encoding/decoding

    func testPlaybackHistoryItemRoundTrip() throws {
        let item = PlaybackHistoryItem(
            id: UUID(),
            title: "1999",
            artist: "99 Frames for Prince",
            album: "Dirty Edits Vol. 1",
            image_key: "abc123",
            length: 174,
            zone_name: "Eversolo DMP-A8",
            playedAt: Date()
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(item)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PlaybackHistoryItem.self, from: data)

        XCTAssertEqual(decoded.title, item.title)
        XCTAssertEqual(decoded.artist, item.artist)
        XCTAssertEqual(decoded.album, item.album)
        XCTAssertEqual(decoded.image_key, item.image_key)
        XCTAssertEqual(decoded.length, item.length)
        XCTAssertEqual(decoded.zone_name, item.zone_name)
        XCTAssertEqual(decoded.id, item.id)
    }

    // MARK: - RoonZone equality

    func testRoonZoneEqualityIncludesNowPlaying() {
        let np1 = NowPlaying(one_line: nil, two_line: nil,
            three_line: NowPlaying.LineInfo(line1: "Song A", line2: "Artist", line3: "Album"),
            length: 200, seek_position: 10, image_key: "img1")
        let np2 = NowPlaying(one_line: nil, two_line: nil,
            three_line: NowPlaying.LineInfo(line1: "Song B", line2: "Artist", line3: "Album"),
            length: 300, seek_position: 0, image_key: "img2")

        let zone1 = RoonZone(zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: np1, outputs: nil, settings: nil, seek_position: 10,
            is_play_allowed: nil, is_pause_allowed: nil, is_seek_allowed: nil,
            is_previous_allowed: nil, is_next_allowed: nil)
        let zone2 = RoonZone(zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: np2, outputs: nil, settings: nil, seek_position: 10,
            is_play_allowed: nil, is_pause_allowed: nil, is_seek_allowed: nil,
            is_previous_allowed: nil, is_next_allowed: nil)

        XCTAssertNotEqual(zone1, zone2)
    }

    func testRoonZoneEqualityExcludesSeekPosition() {
        let np = NowPlaying(one_line: nil, two_line: nil,
            three_line: NowPlaying.LineInfo(line1: "Song", line2: "Artist", line3: "Album"),
            length: 200, seek_position: nil, image_key: "img")

        let zone1 = RoonZone(zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: np, outputs: nil, settings: nil, seek_position: 10,
            is_play_allowed: nil, is_pause_allowed: nil, is_seek_allowed: nil,
            is_previous_allowed: nil, is_next_allowed: nil)
        let zone2 = RoonZone(zone_id: "z1", display_name: "Zone", state: "playing",
            now_playing: np, outputs: nil, settings: nil, seek_position: 11,
            is_play_allowed: nil, is_pause_allowed: nil, is_seek_allowed: nil,
            is_previous_allowed: nil, is_next_allowed: nil)

        // seek_position is intentionally excluded from equality to avoid
        // re-rendering all views every second during playback
        XCTAssertEqual(zone1, zone2)
    }

    // MARK: - QueueItem decoding

    func testQueueItemDecoding() throws {
        let json = """
        {
            "queue_item_id": 42,
            "one_line": {"line1": "Song Title"},
            "three_line": {"line1": "Song Title", "line2": "Artist", "line3": "Album"},
            "length": 240,
            "image_key": "imgkey"
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(QueueItem.self, from: json)
        XCTAssertEqual(item.queue_item_id, 42)
        XCTAssertEqual(item.id, 42)
        XCTAssertEqual(item.three_line?.line1, "Song Title")
        XCTAssertEqual(item.length, 240)
    }

    // MARK: - InputPrompt

    func testInputPromptDecoding() throws {
        let json = """
        {"prompt": "Search", "action": "Go"}
        """.data(using: .utf8)!

        let prompt = try JSONDecoder().decode(InputPrompt.self, from: json)
        XCTAssertEqual(prompt.prompt, "Search")
        XCTAssertEqual(prompt.action, "Go")
    }

    // MARK: - RoonOutput / VolumeInfo decoding

    func testRoonOutputDecoding() throws {
        let json = """
        {
            "output_id": "o1",
            "display_name": "DAC USB",
            "zone_id": "z1",
            "volume": {
                "type": "number",
                "min": 0,
                "max": 100,
                "value": 65,
                "step": 1,
                "is_muted": false
            }
        }
        """.data(using: .utf8)!

        let output = try JSONDecoder().decode(RoonOutput.self, from: json)
        XCTAssertEqual(output.output_id, "o1")
        XCTAssertEqual(output.display_name, "DAC USB")
        XCTAssertEqual(output.id, "o1")
        XCTAssertEqual(output.volume?.type, "number")
        XCTAssertEqual(output.volume?.min, 0)
        XCTAssertEqual(output.volume?.max, 100)
        XCTAssertEqual(output.volume?.value, 65)
        XCTAssertEqual(output.volume?.step, 1)
        XCTAssertEqual(output.volume?.is_muted, false)
    }

    func testRoonOutputWithoutVolume() throws {
        let json = """
        {"output_id": "o2", "display_name": "Headphones"}
        """.data(using: .utf8)!

        let output = try JSONDecoder().decode(RoonOutput.self, from: json)
        XCTAssertEqual(output.output_id, "o2")
        XCTAssertNil(output.volume)
        XCTAssertNil(output.zone_id)
    }

    func testVolumeInfoMutedState() throws {
        let json = """
        {"type": "db", "min": -80, "max": 0, "value": -30, "step": 0.5, "is_muted": true}
        """.data(using: .utf8)!

        let volume = try JSONDecoder().decode(RoonOutput.VolumeInfo.self, from: json)
        XCTAssertEqual(volume.type, "db")
        XCTAssertEqual(volume.min, -80)
        XCTAssertEqual(volume.value, -30)
        XCTAssertEqual(volume.is_muted, true)
    }

    // MARK: - ZoneSettings decoding

    func testZoneSettingsDecoding() throws {
        let json = """
        {"shuffle": true, "loop": "loop_one", "auto_radio": false}
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(ZoneSettings.self, from: json)
        XCTAssertEqual(settings.shuffle, true)
        XCTAssertEqual(settings.loop, "loop_one")
        XCTAssertEqual(settings.auto_radio, false)
    }

    func testZoneSettingsPartialDecoding() throws {
        let json = """
        {"loop": "disabled"}
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(ZoneSettings.self, from: json)
        XCTAssertNil(settings.shuffle)
        XCTAssertEqual(settings.loop, "disabled")
        XCTAssertNil(settings.auto_radio)
    }

    // MARK: - RoonZone full decoding

    func testRoonZoneFullDecoding() throws {
        let json = """
        {
            "zone_id": "z1",
            "display_name": "Salon",
            "state": "playing",
            "now_playing": {
                "three_line": {"line1": "Song", "line2": "Artist", "line3": "Album"},
                "length": 240,
                "seek_position": 30,
                "image_key": "img1"
            },
            "seek_position": 30,
            "is_play_allowed": true,
            "is_pause_allowed": true,
            "is_seek_allowed": true,
            "is_previous_allowed": true,
            "is_next_allowed": true,
            "settings": {"shuffle": false, "loop": "disabled", "auto_radio": true}
        }
        """.data(using: .utf8)!

        let zone = try JSONDecoder().decode(RoonZone.self, from: json)
        XCTAssertEqual(zone.zone_id, "z1")
        XCTAssertEqual(zone.display_name, "Salon")
        XCTAssertEqual(zone.state, "playing")
        XCTAssertEqual(zone.now_playing?.three_line?.line1, "Song")
        XCTAssertEqual(zone.now_playing?.length, 240)
        XCTAssertEqual(zone.now_playing?.image_key, "img1")
        XCTAssertEqual(zone.settings?.auto_radio, true)
        XCTAssertEqual(zone.is_seek_allowed, true)
    }

    func testRoonZoneMinimalDecoding() throws {
        let json = """
        {"zone_id": "z2", "display_name": "Bureau"}
        """.data(using: .utf8)!

        let zone = try JSONDecoder().decode(RoonZone.self, from: json)
        XCTAssertEqual(zone.zone_id, "z2")
        XCTAssertNil(zone.state)
        XCTAssertNil(zone.now_playing)
        XCTAssertNil(zone.outputs)
        XCTAssertNil(zone.settings)
        XCTAssertNil(zone.seek_position)
    }

    // MARK: - BrowseResult / BrowseList

    func testBrowseResultDecoding() throws {
        let json = """
        {
            "action": "list",
            "list": {"title": "Albums", "count": 1520, "level": 2},
            "items": [
                {"title": "Abbey Road", "item_key": "a1", "hint": "action_list", "image_key": "img_abbey"}
            ],
            "offset": 0
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(BrowseResult.self, from: json)
        XCTAssertEqual(result.action, "list")
        XCTAssertEqual(result.list?.title, "Albums")
        XCTAssertEqual(result.list?.count, 1520)
        XCTAssertEqual(result.list?.level, 2)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].image_key, "img_abbey")
        XCTAssertEqual(result.offset, 0)
    }

    func testBrowseResultEmptyItems() throws {
        let json = """
        {"action": "list", "list": {"title": "Empty", "count": 0}, "items": []}
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(BrowseResult.self, from: json)
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.list?.count, 0)
    }

    // MARK: - WSMessage types decoding

    func testWSStateMessageDecoding() throws {
        let json = """
        {"type": "state", "state": "connected"}
        """.data(using: .utf8)!

        let msg = try JSONDecoder().decode(WSStateMessage.self, from: json)
        XCTAssertEqual(msg.type, "state")
        XCTAssertEqual(msg.state, "connected")
    }

    func testWSZonesMessageDecoding() throws {
        let json = """
        {
            "type": "zones",
            "zones": [
                {"zone_id": "z1", "display_name": "Salon", "state": "playing"},
                {"zone_id": "z2", "display_name": "Bureau", "state": "stopped"}
            ]
        }
        """.data(using: .utf8)!

        let msg = try JSONDecoder().decode(WSZonesMessage.self, from: json)
        XCTAssertEqual(msg.type, "zones")
        XCTAssertEqual(msg.zones.count, 2)
        XCTAssertEqual(msg.zones[0].display_name, "Salon")
    }

    func testWSQueueMessageDecoding() throws {
        let json = """
        {
            "type": "queue",
            "zone_id": "z1",
            "items": [
                {"queue_item_id": 1, "one_line": {"line1": "Track 1"}, "length": 180}
            ]
        }
        """.data(using: .utf8)!

        let msg = try JSONDecoder().decode(WSQueueMessage.self, from: json)
        XCTAssertEqual(msg.type, "queue")
        XCTAssertEqual(msg.zone_id, "z1")
        XCTAssertEqual(msg.items.count, 1)
        XCTAssertEqual(msg.items[0].queue_item_id, 1)
    }

    func testWSErrorMessageDecoding() throws {
        let json = """
        {"type": "error", "message": "Connection refused"}
        """.data(using: .utf8)!

        let msg = try JSONDecoder().decode(WSErrorMessage.self, from: json)
        XCTAssertEqual(msg.type, "error")
        XCTAssertEqual(msg.message, "Connection refused")
    }

    // MARK: - NowPlaying edge cases

    func testNowPlayingWithOnlyOneLine() throws {
        let json = """
        {"one_line": {"line1": "FIP Radio"}, "length": null, "seek_position": null}
        """.data(using: .utf8)!

        let np = try JSONDecoder().decode(NowPlaying.self, from: json)
        XCTAssertEqual(np.one_line?.line1, "FIP Radio")
        XCTAssertNil(np.three_line)
        XCTAssertNil(np.length)
        XCTAssertNil(np.image_key)
    }

    func testNowPlayingEquality() {
        let a = NowPlaying(
            one_line: nil, two_line: nil,
            three_line: NowPlaying.LineInfo(line1: "Song", line2: "Artist", line3: "Album"),
            length: 240, seek_position: 10, image_key: "img1"
        )
        let b = NowPlaying(
            one_line: nil, two_line: nil,
            three_line: NowPlaying.LineInfo(line1: "Song", line2: "Artist", line3: "Album"),
            length: 240, seek_position: 10, image_key: "img1"
        )
        let c = NowPlaying(
            one_line: nil, two_line: nil,
            three_line: NowPlaying.LineInfo(line1: "Different", line2: "Artist", line3: "Album"),
            length: 240, seek_position: 10, image_key: "img1"
        )
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - QueueItem edge cases

    func testQueueItemMinimalDecoding() throws {
        let json = """
        {"queue_item_id": 99}
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(QueueItem.self, from: json)
        XCTAssertEqual(item.queue_item_id, 99)
        XCTAssertEqual(item.id, 99)
        XCTAssertNil(item.one_line)
        XCTAssertNil(item.three_line)
        XCTAssertNil(item.length)
        XCTAssertNil(item.image_key)
    }

    // MARK: - RoonState enum

    func testRoonStateRawValues() {
        XCTAssertEqual(RoonState.connected.rawValue, "connected")
        XCTAssertEqual(RoonState.disconnected.rawValue, "disconnected")
        XCTAssertEqual(RoonState.connecting.rawValue, "connecting")
        XCTAssertEqual(RoonState.waitingForApproval.rawValue, "waitingForApproval")
    }

    func testRoonStateDecodable() throws {
        let json = "\"connected\"".data(using: .utf8)!
        let state = try JSONDecoder().decode(RoonState.self, from: json)
        XCTAssertEqual(state, .connected)
    }

    // MARK: - BrowseItem subtitle and image_key

    func testBrowseItemWithAllFields() throws {
        let json = """
        {
            "title": "Abbey Road",
            "subtitle": "The Beatles",
            "item_key": "a1",
            "hint": "action_list",
            "image_key": "img_abbey"
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(BrowseItem.self, from: json)
        XCTAssertEqual(item.subtitle, "The Beatles")
        XCTAssertEqual(item.image_key, "img_abbey")
        XCTAssertEqual(item.hint, "action_list")
    }
}
