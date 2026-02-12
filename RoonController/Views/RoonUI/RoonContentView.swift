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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.roonBackground)
    }

    // MARK: - Home

    @State private var recentTab: RecentTab = .played

    private var homeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Greeting
                Text("Bonjour")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Color.roonText)
                    .padding(.horizontal, 32)
                    .padding(.top, 32)
                    .padding(.bottom, 24)

                // Library stats cards
                libraryStats
                    .padding(.horizontal, 32)
                    .padding(.bottom, 28)

                // "Dernièrement" section with panel background
                if !recentPlayedTiles.isEmpty || !upNextTiles.isEmpty {
                    recentSection
                }

                // Other zones playing
                let otherZones = roonService.zones.filter {
                    $0.zone_id != roonService.currentZone?.zone_id && $0.now_playing != nil
                }
                if !otherZones.isEmpty {
                    zonesRow(zones: otherZones)
                }

                Spacer(minLength: 40)
            }
        }
    }

    // MARK: - Library Stats

    private var libraryStats: some View {
        HStack(spacing: 12) {
            statCard(icon: "music.mic", count: roonService.libraryCounts["artists"], label: "ARTISTES")
            statCard(icon: "opticaldisc", count: roonService.libraryCounts["albums"], label: "ALBUMS")
            statCard(icon: "music.note", count: roonService.libraryCounts["tracks"], label: "MORCEAUX")
            statCard(icon: "music.quarternote.3", count: roonService.libraryCounts["composers"], label: "COMPOSITEURS")
        }
    }

    private func statCard(icon: String, count: Int?, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.roonSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                if let count = count {
                    Text("\(count)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.roonText)
                } else {
                    Text("—")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.roonTertiary)
                }
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.roonTertiary)
                    .tracking(0.8)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.roonPanel)
        )
    }

    // MARK: - Recent Section (Dernièrement)

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with tabs
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Dernièrement")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.roonText)
                    .padding(.trailing, 20)

                // Tab: LUS
                Button {
                    recentTab = .played
                } label: {
                    VStack(spacing: 4) {
                        Text("LUS")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(recentTab == .played ? Color.roonAccent : Color.roonSecondary)
                        Rectangle()
                            .fill(recentTab == .played ? Color.roonAccent : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(width: 40)
                }
                .buttonStyle(.plain)

                // Tab: FILE
                Button {
                    recentTab = .queue
                } label: {
                    VStack(spacing: 4) {
                        Text("FILE")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(recentTab == .queue ? Color.roonAccent : Color.roonSecondary)
                        Rectangle()
                            .fill(recentTab == .queue ? Color.roonAccent : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(width: 40)
                }
                .buttonStyle(.plain)

                Spacer()

                // "PLUS" button
                if recentTab == .played && !recentPlayedTiles.isEmpty {
                    Button {
                        selectedSection = .history
                    } label: {
                        Text("PLUS")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.roonText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .strokeBorder(Color.roonBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }

                if recentTab == .queue && !upNextTiles.isEmpty {
                    Button {
                        selectedSection = .queue
                    } label: {
                        Text("PLUS")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.roonText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .strokeBorder(Color.roonBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 28)

            // Album tiles horizontal scroll
            let tiles = recentTab == .played ? recentPlayedTiles : upNextTiles
            if tiles.isEmpty {
                Text(recentTab == .played ? "Aucun historique de lecture" : "File d'attente vide")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.roonTertiary)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(tiles, id: \.id) { tile in
                            albumTile(tile)
                        }
                    }
                    .padding(.horizontal, 28)
                }
            }
        }
        .padding(.vertical, 24)
        .background(Color.roonPanel.opacity(0.6))
    }

    // MARK: - Recent Played Tiles

    private var recentPlayedTiles: [HomeTile] {
        var tiles: [HomeTile] = []
        for item in roonService.playbackHistory {
            tiles.append(HomeTile(
                id: item.id.uuidString,
                title: item.title,
                albumLine: item.album.isEmpty ? nil : "sur \(item.album)",
                artistLine: item.artist.isEmpty ? nil : "par \(item.artist)",
                imageKey: item.image_key
            ))
            if tiles.count >= 20 { break }
        }
        return tiles
    }

    // MARK: - Up Next Tiles

    private var upNextTiles: [HomeTile] {
        roonService.queueItems.prefix(20).map { item in
            let title = item.three_line?.line1 ?? item.one_line?.line1 ?? ""
            let album = item.three_line?.line3
            let artist = item.three_line?.line2
            return HomeTile(
                id: String(item.queue_item_id),
                title: title,
                albumLine: (album != nil && !album!.isEmpty) ? "sur \(album!)" : nil,
                artistLine: (artist != nil && !artist!.isEmpty) ? "par \(artist!)" : nil,
                imageKey: item.image_key
            )
        }
    }

    // MARK: - Album Tile

    private func albumTile(_ tile: HomeTile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Album art with play overlay on hover
            ZStack(alignment: .topLeading) {
                if let url = roonService.imageURL(key: tile.imageKey, width: 400, height: 400) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Color.roonGrey2
                        }
                    }
                    .frame(width: 170, height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.roonGrey2)
                        .frame(width: 170, height: 170)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 28))
                                .foregroundStyle(Color.roonTertiary)
                        }
                }

                // Play button overlay
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.roonAccent)
                    .shadow(color: .black.opacity(0.3), radius: 4)
                    .padding(8)
            }

            // Title
            Text(tile.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.roonText)
                .lineLimit(1)

            // Album line ("sur ...")
            if let albumLine = tile.albumLine {
                Text(albumLine)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.roonSecondary)
                    .lineLimit(1)
            }

            // Artist line ("par ...")
            if let artistLine = tile.artistLine {
                Text(artistLine)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.roonSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 170)
    }

    // MARK: - Zones Row

    private func zonesRow(zones: [RoonZone]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EN LECTURE AILLEURS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.roonTertiary)
                .tracking(1.2)
                .padding(.horizontal, 32)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(zones) { zone in
                        zoneCard(zone)
                    }
                }
                .padding(.horizontal, 32)
            }
        }
        .padding(.top, 28)
    }

    private func zoneCard(_ zone: RoonZone) -> some View {
        Button {
            roonService.selectZone(zone)
        } label: {
            HStack(spacing: 12) {
                if let np = zone.now_playing,
                   let url = roonService.imageURL(key: np.image_key, width: 100, height: 100) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Color.roonGrey2
                        }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(zone.display_name)
                        .font(.system(size: 13, weight: .medium))
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
            .padding(12)
            .frame(width: 260)
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
                .font(.system(size: 10))
                .foregroundStyle(Color.roonGreen)
        case "paused":
            Image(systemName: "pause.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.roonOrange)
        case "loading":
            ProgressView()
                .controlSize(.mini)
        default:
            Image(systemName: "stop.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.roonTertiary)
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
    let albumLine: String?
    let artistLine: String?
    let imageKey: String?
}
