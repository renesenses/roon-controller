import XCTest
@testable import Roon_Controller

final class LyricsServiceTests: XCTestCase {

    // MARK: - LRC Parsing

    func testParseLRCBasic() {
        let lrc = """
        [00:12.34] Hello world
        [00:15.67] Second line
        [01:00.00] One minute mark
        """
        let lines = LyricsService.parseLRC(lrc)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].time, 12.34, accuracy: 0.01)
        XCTAssertEqual(lines[0].text, "Hello world")
        XCTAssertEqual(lines[1].time, 15.67, accuracy: 0.01)
        XCTAssertEqual(lines[1].text, "Second line")
        XCTAssertEqual(lines[2].time, 60.0, accuracy: 0.01)
        XCTAssertEqual(lines[2].text, "One minute mark")
    }

    func testParseLRCWithMilliseconds() {
        let lrc = "[00:05.123] Three digit ms"
        let lines = LyricsService.parseLRC(lrc)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].time, 5.123, accuracy: 0.001)
        XCTAssertEqual(lines[0].text, "Three digit ms")
    }

    func testParseLRCEmptyLines() {
        let lrc = """
        [00:10.00] First
        [00:20.00]
        [00:30.00] After break
        """
        let lines = LyricsService.parseLRC(lrc)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].text, "First")
        XCTAssertEqual(lines[1].text, "")
        XCTAssertEqual(lines[2].text, "After break")
    }

    func testParseLRCSortsById() {
        // Lines should be sorted by time even if input is unordered
        let lrc = """
        [00:30.00] Third
        [00:10.00] First
        [00:20.00] Second
        """
        let lines = LyricsService.parseLRC(lrc)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].text, "First")
        XCTAssertEqual(lines[1].text, "Second")
        XCTAssertEqual(lines[2].text, "Third")
    }

    func testParseLRCIgnoresInvalidLines() {
        let lrc = """
        [00:10.00] Valid line
        This is not a valid LRC line
        [metadata:value]
        [00:20.00] Another valid line
        """
        let lines = LyricsService.parseLRC(lrc)
        XCTAssertEqual(lines.count, 2)
    }

    // MARK: - Cache Key

    func testCacheKeyIsStable() {
        let key1 = LyricsService.cacheKey(title: "Bohemian Rhapsody", artist: "Queen", album: "A Night at the Opera", duration: 354)
        let key2 = LyricsService.cacheKey(title: "Bohemian Rhapsody", artist: "Queen", album: "A Night at the Opera", duration: 354)
        XCTAssertEqual(key1, key2)
    }

    func testCacheKeyIsCaseInsensitive() {
        let key1 = LyricsService.cacheKey(title: "Hello", artist: "Adele", album: "25", duration: 295)
        let key2 = LyricsService.cacheKey(title: "hello", artist: "ADELE", album: "25", duration: 295)
        XCTAssertEqual(key1, key2)
    }

    func testCacheKeyDiffersForDifferentTracks() {
        let key1 = LyricsService.cacheKey(title: "Song A", artist: "Artist", album: "Album", duration: 200)
        let key2 = LyricsService.cacheKey(title: "Song B", artist: "Artist", album: "Album", duration: 200)
        XCTAssertNotEqual(key1, key2)
    }

    func testCacheKeyDiffersForDifferentDurations() {
        let key1 = LyricsService.cacheKey(title: "Song", artist: "Artist", album: "Album", duration: 200)
        let key2 = LyricsService.cacheKey(title: "Song", artist: "Artist", album: "Album", duration: 201)
        XCTAssertNotEqual(key1, key2)
    }

    func testCacheKeyIsSHA256Hex() {
        let key = LyricsService.cacheKey(title: "Test", artist: "Test", album: "Test", duration: 100)
        // SHA256 = 64 hex characters
        XCTAssertEqual(key.count, 64)
        XCTAssertTrue(key.allSatisfy { $0.isHexDigit })
    }

    // MARK: - Current Line Index

    func testCurrentLineIndexBeforeFirstLine() {
        let lines = [
            LyricLine(id: 0, time: 10.0, text: "First"),
            LyricLine(id: 1, time: 20.0, text: "Second"),
        ]
        XCTAssertNil(LyricsService.currentLineIndex(lines: lines, seekPosition: 5))
    }

    func testCurrentLineIndexAtFirstLine() {
        let lines = [
            LyricLine(id: 0, time: 10.0, text: "First"),
            LyricLine(id: 1, time: 20.0, text: "Second"),
        ]
        XCTAssertEqual(LyricsService.currentLineIndex(lines: lines, seekPosition: 10), 0)
    }

    func testCurrentLineIndexBetweenLines() {
        let lines = [
            LyricLine(id: 0, time: 10.0, text: "First"),
            LyricLine(id: 1, time: 20.0, text: "Second"),
            LyricLine(id: 2, time: 30.0, text: "Third"),
        ]
        XCTAssertEqual(LyricsService.currentLineIndex(lines: lines, seekPosition: 25), 1)
    }

    func testCurrentLineIndexAtLastLine() {
        let lines = [
            LyricLine(id: 0, time: 10.0, text: "First"),
            LyricLine(id: 1, time: 20.0, text: "Second"),
        ]
        XCTAssertEqual(LyricsService.currentLineIndex(lines: lines, seekPosition: 99), 1)
    }

    func testCurrentLineIndexEmptyLines() {
        let lines: [LyricLine] = []
        XCTAssertNil(LyricsService.currentLineIndex(lines: lines, seekPosition: 10))
    }

    // MARK: - LyricsResult Equality

    func testLyricsResultNotFoundEquality() {
        XCTAssertEqual(LyricsResult.notFound, LyricsResult.notFound)
    }

    func testLyricsResultInstrumentalEquality() {
        XCTAssertEqual(LyricsResult.instrumental, LyricsResult.instrumental)
    }

    func testLyricsResultPlainEquality() {
        XCTAssertEqual(LyricsResult.plain("hello"), LyricsResult.plain("hello"))
        XCTAssertNotEqual(LyricsResult.plain("hello"), LyricsResult.plain("world"))
    }

    func testLyricsResultSyncedEquality() {
        let lines = [LyricLine(id: 0, time: 10.0, text: "Hello")]
        XCTAssertEqual(LyricsResult.synced(lines), LyricsResult.synced(lines))
    }
}
