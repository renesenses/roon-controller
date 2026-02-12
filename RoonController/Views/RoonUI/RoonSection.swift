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
    case home, browse, queue, radio, history, favorites

    var label: String {
        switch self {
        case .home: "Accueil"
        case .browse: "Bibliotheque"
        case .queue: "File d'attente"
        case .radio: "Radio"
        case .history: "Historique"
        case .favorites: "Favoris"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .browse: "square.grid.2x2"
        case .queue: "list.number"
        case .radio: "dot.radiowaves.left.and.right"
        case .history: "clock"
        case .favorites: "heart"
        }
    }
}
