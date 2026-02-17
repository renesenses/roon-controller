import SwiftUI

enum UIMode: String, CaseIterable {
    case player, roon

    var label: String {
        switch self {
        case .player: "Player"
        case .roon: "Roon"
        }
    }
}

enum RoonSection: String, CaseIterable {
    case home, browse, queue, radio, history, radioFavorites, nowPlaying

    var label: String {
        switch self {
        case .home: String(localized: "Home")
        case .browse: String(localized: "Library")
        case .queue: String(localized: "Queue")
        case .radio: String(localized: "Radio")
        case .history: String(localized: "History")
        case .radioFavorites: String(localized: "Radio Favorites")
        case .nowPlaying: String(localized: "Now Playing")
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .browse: "square.grid.2x2"
        case .queue: "list.number"
        case .radio: "dot.radiowaves.left.and.right"
        case .history: "clock"
        case .radioFavorites: "heart.circle"
        case .nowPlaying: "music.note"
        }
    }
}
