import SwiftUI

struct RoonContentView: View {
    @EnvironmentObject var roonService: RoonService
    @Binding var selectedSection: RoonSection

    var body: some View {
        Group {
            switch selectedSection {
            case .home:
                homeContent
            case .browse:
                RoonBrowseContentView()
            case .queue:
                QueueView()
            case .radio:
                RoonBrowseContentView(startWithRadio: true)
            case .history:
                HistoryView()
            case .favorites:
                FavoritesView()
            case .nowPlaying:
                RoonNowPlayingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.roonBackground)
    }

    // MARK: - Home

    @State private var recentTab: RecentTab = .played
    private let pagePadding: CGFloat = 32

    private var homeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Greeting
                Text("Bonjour")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Color.roonText)
                    .padding(.horizontal, pagePadding)
                    .padding(.top, 28)
                    .padding(.bottom, 20)

                // Library stats cards (accent left border, like Roon native)
                libraryStats
                    .padding(.horizontal, pagePadding)
                    .padding(.bottom, 24)

                // "Dernièrement" section with LUS / AJOUTÉ tabs
                if !recentPlayedTiles.isEmpty || !upNextTiles.isEmpty {
                    recentSection
                        .padding(.bottom, 24)
                }

                // Other zones playing
                let otherZones = roonService.zones.filter {
                    $0.zone_id != roonService.currentZone?.zone_id && $0.now_playing != nil
                }
                if !otherZones.isEmpty {
                    zonesSection(zones: otherZones)
                        .padding(.bottom, 24)
                }

                Spacer(minLength: 40)
            }
        }
    }

    // MARK: - Library Stats (Roon-native style: icon + large number, accent left border)

    private var libraryStats: some View {
        HStack(spacing: 12) {
            statCard(icon: "music.mic", count: roonService.libraryCounts["artists"])
            statCard(icon: "opticaldisc", count: roonService.libraryCounts["albums"])
            statCard(icon: "music.note", count: roonService.libraryCounts["tracks"])
            statCard(icon: "music.quarternote.3", count: roonService.libraryCounts["composers"])
        }
    }

    private func statCard(icon: String, count: Int?) -> some View {
        HStack(spacing: 10) {
            // Accent left border
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.roonAccent)
                .frame(width: 3, height: 36)

            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.roonAccent)
                .frame(width: 22)

            if let count = count {
                Text("\(count)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.roonText)
            } else {
                Text("—")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.roonTertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.roonPanel)
        )
    }

    // MARK: - Recent Section (Dernièrement) with tabs

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header with tabs
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Dernièrement")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.roonText)
                    .padding(.trailing, 20)

                tabButton("LIRE", tab: .played)
                tabButton("AJOUTÉ", tab: .queue)

                Spacer()

                if recentTab == .played && !recentPlayedTiles.isEmpty {
                    moreButton { selectedSection = .history }
                }
                if recentTab == .queue && !upNextTiles.isEmpty {
                    moreButton { selectedSection = .queue }
                }
            }
            .padding(.horizontal, pagePadding)

            // Tiles
            let tiles = recentTab == .played ? recentPlayedTiles : upNextTiles
            if tiles.isEmpty {
                Text(recentTab == .played ? "Aucun historique de lecture" : "File d'attente vide")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.roonTertiary)
                    .padding(.horizontal, pagePadding)
                    .padding(.vertical, 16)
            } else {
                horizontalScroll(tiles: tiles)
            }
        }
        .padding(.vertical, 20)
        .background(Color.roonPanel.opacity(0.5))
    }

    private func tabButton(_ label: String, tab: RecentTab) -> some View {
        Button {
            recentTab = tab
        } label: {
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(recentTab == tab ? Color.roonAccent : Color.roonSecondary)
                Rectangle()
                    .fill(recentTab == tab ? Color.roonAccent : Color.clear)
                    .frame(height: 2)
            }
            .frame(width: label.count > 4 ? 56 : 36)
        }
        .buttonStyle(.plain)
    }

    private func moreButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("PLUS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.roonText)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .strokeBorder(Color.roonBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(Color.roonText)
            .padding(.horizontal, pagePadding)
            .padding(.bottom, 10)
    }

    // MARK: - Horizontal Scroll of Tiles

    private func horizontalScroll(tiles: [HomeTile]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(tiles, id: \.id) { tile in
                    albumCard(tile)
                }
            }
            .padding(.horizontal, pagePadding)
        }
    }

    // MARK: - Album Card

    private let cardSize: CGFloat = 160

    private func albumCard(_ tile: HomeTile) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            // Album art
            if let url = roonService.imageURL(key: tile.imageKey, width: 400, height: 400) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Color.roonGrey2
                    }
                }
                .frame(width: cardSize, height: cardSize)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.roonGrey2)
                    .frame(width: cardSize, height: cardSize)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 26))
                            .foregroundStyle(Color.roonTertiary)
                    }
            }

            // Title
            Text(tile.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.roonText)
                .lineLimit(1)

            // Subtitle
            if let subtitle = tile.subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.roonSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: cardSize)
    }

    // MARK: - Zones Section

    private func zonesSection(zones: [RoonZone]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("En lecture ailleurs")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(zones) { zone in
                        zoneCard(zone)
                    }
                }
                .padding(.horizontal, pagePadding)
            }
        }
    }

    private func zoneCard(_ zone: RoonZone) -> some View {
        Button {
            roonService.selectZone(zone)
        } label: {
            HStack(spacing: 12) {
                if let np = zone.now_playing,
                   let url = roonService.imageURL(key: np.image_key, width: 120, height: 120) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Color.roonGrey2
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(zone.display_name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.roonText)
                        .lineLimit(1)
                    if let np = zone.now_playing {
                        Text(np.three_line?.line1 ?? "")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.roonSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let state = zone.state {
                    stateIndicator(state)
                }
            }
            .padding(10)
            .frame(width: 240)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.roonPanel)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func stateIndicator(_ state: String) -> some View {
        switch state {
        case "playing":
            Image(systemName: "play.fill")
                .font(.system(size: 9))
                .foregroundStyle(Color.roonGreen)
        case "paused":
            Image(systemName: "pause.fill")
                .font(.system(size: 9))
                .foregroundStyle(Color.roonOrange)
        case "loading":
            ProgressView()
                .controlSize(.mini)
        default:
            Image(systemName: "stop.fill")
                .font(.system(size: 9))
                .foregroundStyle(Color.roonTertiary)
        }
    }

    // MARK: - Tile Data

    private var recentPlayedTiles: [HomeTile] {
        roonService.playbackHistory.prefix(20).map { item in
            HomeTile(
                id: item.id.uuidString,
                title: item.title,
                subtitle: item.artist.isEmpty ? nil : item.artist,
                imageKey: item.image_key
            )
        }
    }

    private var upNextTiles: [HomeTile] {
        roonService.queueItems.prefix(20).map { item in
            let title = item.three_line?.line1 ?? item.one_line?.line1 ?? ""
            let artist = item.three_line?.line2
            return HomeTile(
                id: String(item.queue_item_id),
                title: title,
                subtitle: (artist != nil && !artist!.isEmpty) ? artist : nil,
                imageKey: item.image_key
            )
        }
    }

}

// MARK: - Supporting Types

private enum RecentTab {
    case played, queue
}

private struct HomeTile {
    let id: String
    let title: String
    let subtitle: String?
    let imageKey: String?
}
