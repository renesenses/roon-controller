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

    private var homeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Now playing hero
                if let zone = roonService.currentZone, let np = zone.now_playing {
                    nowPlayingHero(zone: zone, nowPlaying: np)
                }

                // Zones overview
                zonesOverview
            }
            .padding(24)
        }
    }

    // MARK: - Now Playing Hero

    @ViewBuilder
    private func nowPlayingHero(zone: RoonZone, nowPlaying: NowPlaying) -> some View {
        HStack(spacing: 20) {
            // Album art
            if let url = roonService.imageURL(key: nowPlaying.image_key, width: 400, height: 400) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    default:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.roonGrey2)
                            .overlay {
                                Image(systemName: "music.note")
                                    .font(.system(size: 32))
                                    .foregroundStyle(Color.roonTertiary)
                            }
                    }
                }
                .frame(width: 160, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("EN LECTURE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.roonTertiary)
                    .tracking(1.2)

                Text(nowPlaying.three_line?.line1 ?? "")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.roonText)
                    .lineLimit(2)

                Text(nowPlaying.three_line?.line2 ?? "")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.roonSecondary)
                    .lineLimit(1)

                Text(nowPlaying.three_line?.line3 ?? "")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.roonTertiary)
                    .lineLimit(1)

                // Settings row
                HStack(spacing: 16) {
                    settingsControls(zone: zone)
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.roonPanel)
        )
    }

    // MARK: - Settings Controls

    @ViewBuilder
    private func settingsControls(zone: RoonZone) -> some View {
        Button {
            let current = zone.settings?.shuffle ?? false
            roonService.setShuffle(!current)
        } label: {
            Image(systemName: "shuffle")
                .font(.system(size: 13))
                .foregroundStyle((zone.settings?.shuffle ?? false) ? Color.roonAccent : Color.roonTertiary)
        }
        .buttonStyle(.plain)

        Button {
            let current = zone.settings?.loop ?? "disabled"
            let next: String
            switch current {
            case "disabled": next = "loop"
            case "loop": next = "loop_one"
            default: next = "disabled"
            }
            roonService.setLoop(next)
        } label: {
            let loop = zone.settings?.loop ?? "disabled"
            Image(systemName: loop == "loop_one" ? "repeat.1" : "repeat")
                .font(.system(size: 13))
                .foregroundStyle(loop != "disabled" ? Color.roonAccent : Color.roonTertiary)
        }
        .buttonStyle(.plain)

        Button {
            let current = zone.settings?.auto_radio ?? false
            roonService.setAutoRadio(!current)
        } label: {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 13))
                .foregroundStyle((zone.settings?.auto_radio ?? false) ? Color.roonAccent : Color.roonTertiary)
        }
        .buttonStyle(.plain)

        if zone.is_seek_allowed == false {
            Button { roonService.saveRadioFavorite() } label: {
                Image(systemName: roonService.isCurrentTrackFavorite() ? "heart.fill" : "heart")
                    .font(.system(size: 13))
                    .foregroundStyle(roonService.isCurrentTrackFavorite() ? Color.roonRed : Color.roonTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Zones Overview

    private var zonesOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ZONES")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.roonTertiary)
                .tracking(1.2)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                ForEach(roonService.zones) { zone in
                    zoneCard(zone)
                }
            }
        }
    }

    private func zoneCard(_ zone: RoonZone) -> some View {
        Button {
            roonService.selectZone(zone)
        } label: {
            HStack(spacing: 12) {
                // Mini art
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
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.roonGrey2)
                        .frame(width: 48, height: 48)
                        .overlay {
                            Image(systemName: "hifispeaker")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.roonTertiary)
                        }
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
                    } else {
                        Text("Aucune lecture")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.roonTertiary)
                    }
                }

                Spacer()

                if let state = zone.state {
                    stateIndicator(state)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(zone.zone_id == roonService.currentZone?.zone_id
                          ? Color.roonAccent.opacity(0.12)
                          : Color.roonPanel)
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
