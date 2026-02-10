import Foundation

// MARK: - Connection State

enum RoonState: String, Codable {
    case connected
    case disconnected
    case connecting
}

// MARK: - Zone

struct RoonZone: Codable, Identifiable, Equatable {
    let zone_id: String
    let display_name: String
    let state: String? // "playing", "paused", "loading", "stopped"
    let now_playing: NowPlaying?
    let outputs: [RoonOutput]?
    let settings: ZoneSettings?
    let seek_position: Int?
    let is_play_allowed: Bool?
    let is_pause_allowed: Bool?
    let is_seek_allowed: Bool?
    let is_previous_allowed: Bool?
    let is_next_allowed: Bool?

    var id: String { zone_id }

    static func == (lhs: RoonZone, rhs: RoonZone) -> Bool {
        lhs.zone_id == rhs.zone_id
            && lhs.display_name == rhs.display_name
            && lhs.state == rhs.state
            && lhs.seek_position == rhs.seek_position
            && lhs.now_playing == rhs.now_playing
            && lhs.settings == rhs.settings
    }
}

// MARK: - Now Playing

struct NowPlaying: Codable, Equatable {
    let one_line: LineInfo?
    let two_line: LineInfo?
    let three_line: LineInfo?
    let length: Int?
    let seek_position: Int?
    let image_key: String?

    struct LineInfo: Codable, Equatable {
        let line1: String?
        let line2: String?
        let line3: String?
    }
}

// MARK: - Output

struct RoonOutput: Codable, Identifiable, Equatable {
    let output_id: String
    let display_name: String
    let zone_id: String?
    let volume: VolumeInfo?

    var id: String { output_id }

    struct VolumeInfo: Codable, Equatable {
        let type: String? // "number", "db", "incremental"
        let min: Double?
        let max: Double?
        let value: Double?
        let step: Double?
        let is_muted: Bool?
    }
}

// MARK: - Zone Settings

struct ZoneSettings: Codable, Equatable {
    let shuffle: Bool?
    let loop: String? // "disabled", "loop", "loop_one"
    let auto_radio: Bool?
}

// MARK: - Queue

struct QueueItem: Codable, Identifiable, Equatable {
    let queue_item_id: Int
    let one_line: NowPlaying.LineInfo?
    let two_line: NowPlaying.LineInfo?
    let three_line: NowPlaying.LineInfo?
    let length: Int?
    let image_key: String?

    var id: Int { queue_item_id }
}

// MARK: - Browse

struct BrowseItem: Codable, Identifiable, Equatable {
    let title: String?
    let subtitle: String?
    let item_key: String?
    let hint: String? // "action", "list", "action_list"
    let image_key: String?
    let input_prompt: InputPrompt?

    var id: String { item_key ?? title ?? UUID().uuidString }
}

struct InputPrompt: Codable, Equatable {
    let prompt: String?
    let action: String?
}

struct BrowseList: Codable, Equatable {
    let title: String?
    let count: Int?
    let image_key: String?
    let level: Int?
}

struct BrowseResult: Codable, Equatable {
    let action: String?
    let list: BrowseList?
    let items: [BrowseItem]
    let offset: Int?
}

// MARK: - WebSocket Messages

struct WSMessage: Codable {
    let type: String
}

struct WSStateMessage: Codable {
    let type: String
    let state: String
}

struct WSZonesMessage: Codable {
    let type: String
    let zones: [RoonZone]
}

struct WSBrowseResultMessage: Codable {
    let type: String
    let action: String?
    let list: BrowseList?
    let items: [BrowseItem]?
    let offset: Int?
}

struct WSQueueMessage: Codable {
    let type: String
    let zone_id: String
    let items: [QueueItem]
}

struct WSErrorMessage: Codable {
    let type: String
    let message: String
}
