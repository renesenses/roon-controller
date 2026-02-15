import Foundation

// MARK: - Lyric Line

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: TimeInterval // seconds
    let text: String
}

// MARK: - Lyrics Result

enum LyricsResult: Equatable {
    case synced([LyricLine])
    case plain(String)
    case instrumental
    case notFound
}

// MARK: - LRCLIB API Response

struct LRCLibResponse: Codable {
    let syncedLyrics: String?
    let plainLyrics: String?
    let instrumental: Bool?
}
