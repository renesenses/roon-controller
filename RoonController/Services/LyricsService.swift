import Foundation
import CryptoKit

actor LyricsService {
    static let shared = LyricsService()

    private let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RoonController/lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Public API

    func fetchLyrics(title: String, artist: String, album: String, duration: Int) async -> LyricsResult {
        let cacheKey = self.cacheKey(title: title, artist: artist, album: album, duration: duration)
        let cacheFile = cacheDir.appendingPathComponent(cacheKey + ".json")

        // Check disk cache
        if let cached = loadFromCache(file: cacheFile) {
            return cached
        }

        // Build API URL
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(duration)),
        ]

        guard let url = components.url else { return .notFound }

        var request = URLRequest(url: url)
        request.setValue("RoonController/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let result = LyricsResult.notFound
                saveToCache(file: cacheFile, result: result)
                return result
            }

            let apiResponse = try JSONDecoder().decode(LRCLibResponse.self, from: data)
            let result = parseResponse(apiResponse)
            saveToCache(file: cacheFile, result: result)
            return result
        } catch {
            return .notFound
        }
    }

    // MARK: - LRC Parsing

    static func parseLRC(_ lrc: String) -> [LyricLine] {
        let pattern = #"\[(\d{2}):(\d{2})\.(\d{2,3})\]\s*(.*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        var lines: [LyricLine] = []

        for (index, line) in lrc.components(separatedBy: .newlines).enumerated() {
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)

            guard let match = regex.firstMatch(in: line, range: range) else { continue }

            let minutes = Double(nsLine.substring(with: match.range(at: 1))) ?? 0
            let seconds = Double(nsLine.substring(with: match.range(at: 2))) ?? 0
            let centiseconds = nsLine.substring(with: match.range(at: 3))
            let text = nsLine.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespaces)

            // Handle both 2-digit (centiseconds) and 3-digit (milliseconds) formats
            let fractional: Double
            if centiseconds.count == 3 {
                fractional = (Double(centiseconds) ?? 0) / 1000.0
            } else {
                fractional = (Double(centiseconds) ?? 0) / 100.0
            }

            let time = minutes * 60.0 + seconds + fractional
            lines.append(LyricLine(id: index, time: time, text: text))
        }

        return lines.sorted { $0.time < $1.time }
    }

    /// Find the current line index for a given seek position (seconds)
    static func currentLineIndex(lines: [LyricLine], seekPosition: Int) -> Int? {
        let position = TimeInterval(seekPosition)
        var result: Int? = nil
        for (index, line) in lines.enumerated() {
            if line.time <= position {
                result = index
            } else {
                break
            }
        }
        return result
    }

    // MARK: - Cache Key

    static func cacheKey(title: String, artist: String, album: String, duration: Int) -> String {
        let input = "\(title.lowercased())|\(artist.lowercased())|\(album.lowercased())|\(duration)"
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    // Instance method forwarding to static
    private func cacheKey(title: String, artist: String, album: String, duration: Int) -> String {
        Self.cacheKey(title: title, artist: artist, album: album, duration: duration)
    }

    // MARK: - Response Parsing

    private func parseResponse(_ response: LRCLibResponse) -> LyricsResult {
        if let synced = response.syncedLyrics, !synced.isEmpty {
            let lines = Self.parseLRC(synced)
            if !lines.isEmpty {
                return .synced(lines)
            }
        }

        if let plain = response.plainLyrics, !plain.isEmpty {
            return .plain(plain)
        }

        if response.instrumental == true {
            return .instrumental
        }

        return .notFound
    }

    // MARK: - Disk Cache

    private struct CachedLyrics: Codable {
        let type: String // "synced", "plain", "instrumental", "notFound"
        let syncedLines: [CachedLine]?
        let plainText: String?

        struct CachedLine: Codable {
            let id: Int
            let time: Double
            let text: String
        }
    }

    private func loadFromCache(file: URL) -> LyricsResult? {
        guard let data = try? Data(contentsOf: file),
              let cached = try? JSONDecoder().decode(CachedLyrics.self, from: data) else {
            return nil
        }
        switch cached.type {
        case "synced":
            guard let lines = cached.syncedLines else { return nil }
            return .synced(lines.map { LyricLine(id: $0.id, time: $0.time, text: $0.text) })
        case "plain":
            return .plain(cached.plainText ?? "")
        case "instrumental":
            return .instrumental
        case "notFound":
            return .notFound
        default:
            return nil
        }
    }

    private func saveToCache(file: URL, result: LyricsResult) {
        let cached: CachedLyrics
        switch result {
        case .synced(let lines):
            cached = CachedLyrics(
                type: "synced",
                syncedLines: lines.map { .init(id: $0.id, time: $0.time, text: $0.text) },
                plainText: nil
            )
        case .plain(let text):
            cached = CachedLyrics(type: "plain", syncedLines: nil, plainText: text)
        case .instrumental:
            cached = CachedLyrics(type: "instrumental", syncedLines: nil, plainText: nil)
        case .notFound:
            cached = CachedLyrics(type: "notFound", syncedLines: nil, plainText: nil)
        }
        if let data = try? JSONEncoder().encode(cached) {
            try? data.write(to: file, options: .atomic)
        }
    }
}
