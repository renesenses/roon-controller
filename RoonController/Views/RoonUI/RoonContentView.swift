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

    // MARK: - Home

    private let pagePadding: CGFloat = 32
    private let sectionSpacing: CGFloat = 36
    private let cardSize: CGFloat = 180

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 6 { return "Bonne nuit" }
        if hour < 12 { return "Bonjour" }
        if hour < 18 { return "Bon apres-midi" }
        return "Bonsoir"
    }

    private var homeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Greeting
                Text(greeting)
                    .font(.grifoM(36))
                    .foregroundStyle(Color.roonText)
                    .padding(.horizontal, pagePadding)
                    .padding(.top, 32)
                    .padding(.bottom, sectionSpacing)

                // Recently Played
                if !recentPlayedTiles.isEmpty {
                    homeSection(
                        title: "Ecoutés récemment",
                        tiles: recentPlayedTiles,
                        moreAction: { selectedSection = .history }
                    )
                    .padding(.bottom, sectionSpacing)
                }

                // Up Next (Queue)
                if !upNextTiles.isEmpty {
                    homeSection(
                        title: "File d'attente",
                        tiles: upNextTiles,
                        moreAction: { selectedSection = .queue }
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

                // Library stats (subtle, at bottom)
                libraryStats
                    .padding(.horizontal, pagePadding)
                    .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Home Section (title + horizontal scroll)

    private func homeSection(title: String, tiles: [HomeTile], moreAction: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.grifoM(24))
                    .foregroundStyle(Color.roonText)

                Spacer()

                moreButton(action: moreAction)
            }
            .padding(.horizontal, pagePadding)

            // Horizontal scroll of cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(tiles, id: \.id) { tile in
                        albumCard(tile)
                            .hoverScale()
                    }
                }
                .padding(.horizontal, pagePadding)
            }
        }
    }

    // MARK: - "More" Button

    private func moreButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("PLUS")
                .font(.latoBold(10))
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

    // MARK: - Album Card

    private func albumCard(_ tile: HomeTile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
                            .font(.system(size: 28))
                            .foregroundStyle(Color.roonTertiary)
                    }
            }

            // Title
            Text(tile.title)
                .font(.latoBold(13))
                .foregroundStyle(Color.roonText)
                .lineLimit(1)

            // Subtitle
            if let subtitle = tile.subtitle {
                Text(subtitle)
                    .font(.lato(12))
                    .foregroundStyle(Color.roonSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: cardSize)
    }

    // MARK: - Library Stats (compact inline)

    private var libraryStats: some View {
        HStack(spacing: 12) {
            statCard(icon: "music.mic", label: "Artistes", count: roonService.libraryCounts["artists"])
            statCard(icon: "opticaldisc", label: "Albums", count: roonService.libraryCounts["albums"])
            statCard(icon: "music.note", label: "Morceaux", count: roonService.libraryCounts["tracks"])
            statCard(icon: "music.quarternote.3", label: "Compositeurs", count: roonService.libraryCounts["composers"])
        }
    }

    private func statCard(icon: String, label: String, count: Int?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.roonAccent)

            if let count = count {
                Text("\(count)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.roonText)
            } else {
                Text("—")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.roonTertiary)
            }

            Text(label)
                .font(.lato(10))
                .foregroundStyle(Color.roonTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.roonPanel)
        )
    }

    // MARK: - Zones Section

    private func zonesSection(zones: [RoonZone]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("En lecture ailleurs")
                .font(.grifoM(24))
                .foregroundStyle(Color.roonText)
                .padding(.horizontal, pagePadding)

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
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(zone.display_name)
                        .font(.latoBold(13))
                        .foregroundStyle(Color.roonText)
                        .lineLimit(1)
                    if let np = zone.now_playing {
                        Text(np.three_line?.line1 ?? "")
                            .font(.lato(12))
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
