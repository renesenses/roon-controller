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
        .animation(.easeInOut(duration: 0.2), value: selectedSection)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.roonBackground)
    }

    // MARK: - Home Constants (matching Roon native)

    private let pagePadding: CGFloat = 40
    private let sectionSpacing: CGFloat = 48
    private let cardSize: CGFloat = 280
    private let cardGap: CGFloat = 24
    private let cardImageRes: Int = 640

    // MARK: - Home

    private var homeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 40)

                // Recently Played
                if !recentPlayedTiles.isEmpty {
                    homeSection(
                        title: "Ecoutes recemment",
                        tiles: recentPlayedTiles
                    )
                    .padding(.bottom, sectionSpacing)
                }

                // Up Next (Queue)
                if !upNextTiles.isEmpty {
                    homeSection(
                        title: "A suivre",
                        tiles: upNextTiles
                    )
                    .padding(.bottom, sectionSpacing)
                }

                // Other zones playing
                let otherZones = roonService.zones.filter {
                    $0.zone_id != roonService.currentZone?.zone_id && $0.now_playing != nil
                }
                if !otherZones.isEmpty {
                    zonesSection(zones: otherZones)
                        .padding(.bottom, sectionSpacing)
                }

                Spacer().frame(height: 40)
            }
        }
    }

    // MARK: - Home Section (title + horizontal scroll — Roon native style)

    private func homeSection(title: LocalizedStringKey, tiles: [HomeTile]) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header — Roon uses font-inter text-6xl tracking-tighter
            Text(title)
                .font(.inter(40))
                .foregroundStyle(Color.roonText)
                .tracking(-1.5)
                .padding(.horizontal, pagePadding)

            // Horizontal scroll of cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: cardGap) {
                    ForEach(tiles, id: \.id) { tile in
                        albumCard(tile)
                            .hoverScale()
                    }
                }
                .padding(.horizontal, pagePadding)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Album Card (Roon native: w-80 aspect-square + text-2xl lato)

    private func albumCard(_ tile: HomeTile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Album art
            if let url = roonService.imageURL(key: tile.imageKey, width: cardImageRes, height: cardImageRes) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Color.roonGrey2
                    }
                }
                .frame(width: cardSize, height: cardSize)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.roonGrey2)
                    .frame(width: cardSize, height: cardSize)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.roonTertiary)
                    }
            }

            // Title — Roon: font-lato text-2xl line-clamp-1 text-white
            Text(tile.title)
                .font(.lato(18))
                .foregroundStyle(Color.roonText)
                .lineLimit(1)

            // Subtitle — Roon: font-lato text-xl text-gray-400
            if let subtitle = tile.subtitle {
                Text(subtitle)
                    .font(.lato(15))
                    .foregroundStyle(Color.roonSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: cardSize)
    }

    // MARK: - Zones Section

    private func zonesSection(zones: [RoonZone]) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("En lecture ailleurs")
                .font(.inter(40))
                .foregroundStyle(Color.roonText)
                .tracking(-1.5)
                .padding(.horizontal, pagePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(zones) { zone in
                        zoneCard(zone)
                            .hoverScale()
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
            HStack(spacing: 14) {
                if let np = zone.now_playing,
                   let url = roonService.imageURL(key: np.image_key, width: 160, height: 160) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Color.roonGrey2
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(zone.display_name)
                        .font(.latoBold(15))
                        .foregroundStyle(Color.roonText)
                        .lineLimit(1)
                    if let np = zone.now_playing {
                        Text(np.three_line?.line1 ?? "")
                            .font(.lato(13))
                            .foregroundStyle(Color.roonSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let state = zone.state {
                    stateIndicator(state)
                }
            }
            .padding(14)
            .frame(width: 300)
            .background(
                RoundedRectangle(cornerRadius: 8)
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
                .font(.system(size: 11))
                .foregroundStyle(Color.roonGreen)
        case "paused":
            Image(systemName: "pause.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.roonOrange)
        case "loading":
            ProgressView()
                .controlSize(.mini)
        default:
            Image(systemName: "stop.fill")
                .font(.system(size: 11))
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

private struct HomeTile {
    let id: String
    let title: String
    let subtitle: String?
    let imageKey: String?
}
