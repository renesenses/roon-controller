import SwiftUI

struct PlayerView: View {
    @EnvironmentObject var roonService: RoonService

    var body: some View {
        ZStack {
            // Base background
            Color.roonBackground
                .ignoresSafeArea()

            if let zone = roonService.currentZone {
                if let nowPlaying = zone.now_playing {
                    // Blurred album art background
                    albumArtBackground(imageKey: nowPlaying.image_key)

                    playerContent(zone: zone, nowPlaying: nowPlaying)
                } else {
                    emptyState(zone: zone)
                }
            } else {
                noZoneSelected
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Blurred Background

    @ViewBuilder
    private func albumArtBackground(imageKey: String?) -> some View {
        if let url = roonService.imageURL(key: imageKey, width: 600, height: 600) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 80)
                        .opacity(0.3)
                default:
                    EmptyView()
                }
            }
            .ignoresSafeArea()
            .overlay(Color.roonBackground.opacity(0.7))
        }
    }

    // MARK: - Player Content

    @ViewBuilder
    private func playerContent(zone: RoonZone, nowPlaying: NowPlaying) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 20)

            // Album Art
            albumArt(imageKey: nowPlaying.image_key)

            // Track Info
            trackInfo(nowPlaying: nowPlaying)

            // Seek Bar
            seekBar(zone: zone, nowPlaying: nowPlaying)

            // Transport Controls
            transportControls(zone: zone)

            // Shuffle / Repeat / Radio
            settingsControls(zone: zone)

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Album Art

    @ViewBuilder
    private func albumArt(imageKey: String?) -> some View {
        if let url = roonService.imageURL(key: imageKey, width: 800, height: 800) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                case .failure:
                    artPlaceholder
                case .empty:
                    ProgressView()
                        .tint(.roonSecondary)
                        .frame(width: 400, height: 400)
                @unknown default:
                    artPlaceholder
                }
            }
            .frame(maxWidth: 400, maxHeight: 400)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.6), radius: 24, x: 0, y: 8)
        } else {
            artPlaceholder
        }
    }

    private var artPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.roonSurface)
            .frame(width: 400, height: 400)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.roonTertiary)
            }
    }

    // MARK: - Track Info

    @ViewBuilder
    private func trackInfo(nowPlaying: NowPlaying) -> some View {
        VStack(spacing: 6) {
            Text(nowPlaying.three_line?.line1 ?? "Unknown Title")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(Color.roonText)
                .lineLimit(1)

            Text(nowPlaying.three_line?.line2 ?? "")
                .font(.title3)
                .foregroundStyle(Color.roonSecondary)
                .lineLimit(1)

            Text(nowPlaying.three_line?.line3 ?? "")
                .font(.body)
                .foregroundStyle(Color.roonTertiary)
                .lineLimit(1)
        }
    }

    // MARK: - Seek Bar

    @ViewBuilder
    private func seekBar(zone: RoonZone, nowPlaying: NowPlaying) -> some View {
        let position = Double(zone.seek_position ?? nowPlaying.seek_position ?? 0)
        let duration = Double(nowPlaying.length ?? 0)

        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track background
                    Capsule()
                        .fill(Color.roonTertiary.opacity(0.3))
                        .frame(height: 3)

                    // Progress
                    if duration > 0 {
                        Capsule()
                            .fill(Color.roonAccent)
                            .frame(width: geo.size.width * min(position / duration, 1.0), height: 3)
                    }
                }
                .frame(height: 3)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    if duration > 0 {
                        let fraction = location.x / geo.size.width
                        let seekTo = Int(fraction * duration)
                        roonService.seek(position: seekTo)
                    }
                }
            }
            .frame(height: 3)

            HStack {
                Text(formatTime(Int(position)))
                    .font(.caption2)
                    .foregroundStyle(Color.roonTertiary)
                    .monospacedDigit()

                Spacer()

                Text(formatTime(Int(duration)))
                    .font(.caption2)
                    .foregroundStyle(Color.roonTertiary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: 400)
    }

    // MARK: - Transport Controls

    @ViewBuilder
    private func transportControls(zone: RoonZone) -> some View {
        HStack(spacing: 40) {
            Button { roonService.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
                    .foregroundStyle(Color.roonText)
            }
            .buttonStyle(.plain)
            .disabled(!(zone.is_previous_allowed ?? false))
            .opacity((zone.is_previous_allowed ?? false) ? 1 : 0.3)

            Button { roonService.playPause() } label: {
                Image(systemName: zone.state == "playing" ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Color.roonText)
            }
            .buttonStyle(.plain)

            Button { roonService.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
                    .foregroundStyle(Color.roonText)
            }
            .buttonStyle(.plain)
            .disabled(!(zone.is_next_allowed ?? false))
            .opacity((zone.is_next_allowed ?? false) ? 1 : 0.3)
        }
    }

    // MARK: - Settings Controls (Shuffle/Repeat/Radio)

    @ViewBuilder
    private func settingsControls(zone: RoonZone) -> some View {
        HStack(spacing: 28) {
            Button {
                let current = zone.settings?.shuffle ?? false
                roonService.setShuffle(!current)
            } label: {
                Image(systemName: "shuffle")
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
                    .foregroundStyle(loop != "disabled" ? Color.roonAccent : Color.roonTertiary)
            }
            .buttonStyle(.plain)

            Button {
                let current = zone.settings?.auto_radio ?? false
                roonService.setAutoRadio(!current)
            } label: {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle((zone.settings?.auto_radio ?? false) ? Color.roonAccent : Color.roonTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Empty States

    @ViewBuilder
    private func emptyState(zone: RoonZone) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 48))
                .foregroundStyle(Color.roonTertiary)
            Text("Rien en lecture")
                .font(.title3)
                .foregroundStyle(Color.roonSecondary)
            Text(zone.display_name)
                .font(.caption)
                .foregroundStyle(Color.roonTertiary)
        }
    }

    private var noZoneSelected: some View {
        VStack(spacing: 12) {
            Image(systemName: "hifispeaker")
                .font(.system(size: 48))
                .foregroundStyle(Color.roonTertiary)
            Text("Selectionnez une zone")
                .font(.title3)
                .foregroundStyle(Color.roonSecondary)
        }
    }

    // MARK: - Helpers

    private func formatTime(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
