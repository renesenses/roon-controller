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

    func testRoonZoneEqualityIncludesSeekPosition() {
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

        XCTAssertNotEqual(zone1, zone2)
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
}
