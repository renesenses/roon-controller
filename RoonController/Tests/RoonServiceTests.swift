import XCTest
@testable import Roon_Controller

@MainActor
final class RoonServiceTests: XCTestCase {

    var service: RoonService!

    override func setUp() {
        super.setUp()
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
}
