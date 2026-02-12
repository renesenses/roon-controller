import SwiftUI

struct RoonTransportBarView: View {
    @EnvironmentObject var roonService: RoonService
    var onNowPlayingTap: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            if let zone = roonService.currentZone, let np = zone.now_playing {
                // Left: album art + track info (clickable → Now Playing)
                Button {
                    onNowPlayingTap?()
                } label: {
                    HStack(spacing: 12) {
                        albumArt(imageKey: np.image_key)
                        trackInfo(nowPlaying: np)
                    }
                    .frame(width: 260, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)

                Spacer()

                // Center: transport controls + seek bar
                VStack(spacing: 4) {
                    transportControls(zone: zone)
                    seekBar(zone: zone, nowPlaying: np)
                }
                .frame(maxWidth: 500)

                Spacer()

                // Right: volume + zone
                HStack(spacing: 12) {
                    volumeControl(zone: zone)
                    zoneButton
                }
                .frame(width: 220, alignment: .trailing)
                .padding(.trailing, 16)
            } else if roonService.currentZone != nil {
                Spacer()
                Image(systemName: "music.note")
                    .foregroundStyle(Color.roonTertiary)
                Text("Rien en lecture")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.roonSecondary)
                Spacer()
            } else {
                Spacer()
                Text("Aucune zone selectionnee")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.roonSecondary)
                Spacer()
            }
        }
        .frame(height: 80)
        .background(Color.roonFooter)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.roonSeparator.opacity(0.3))
                .frame(height: 1)
        }
    }

    // MARK: - Album Art

    @ViewBuilder
    private func albumArt(imageKey: String?) -> some View {
        if let url = roonService.imageURL(key: imageKey, width: 120, height: 120) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    artPlaceholder
                }
            }
            .frame(width: 50, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            artPlaceholder
        }
    }

    private var artPlaceholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.roonGrey2)
            .frame(width: 50, height: 50)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.roonTertiary)
            }
    }

    // MARK: - Track Info

    private func trackInfo(nowPlaying: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(nowPlaying.three_line?.line1 ?? "")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.roonText)
                .lineLimit(1)
            Text(nowPlaying.three_line?.line2 ?? "")
                .font(.system(size: 11))
                .foregroundStyle(Color.roonSecondary)
                .lineLimit(1)
        }
    }

    // MARK: - Transport Controls

    private func transportControls(zone: RoonZone) -> some View {
        HStack(spacing: 24) {
            Button { roonService.previous() } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.roonText)
            }
            .buttonStyle(.plain)
            .disabled(!(zone.is_previous_allowed ?? false))
            .opacity((zone.is_previous_allowed ?? false) ? 1 : 0.3)

            Button { roonService.playPause() } label: {
                Image(systemName: zone.state == "playing" ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.roonText)
            }
            .buttonStyle(.plain)

            Button { roonService.next() } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.roonText)
            }
            .buttonStyle(.plain)
            .disabled(!(zone.is_next_allowed ?? false))
            .opacity((zone.is_next_allowed ?? false) ? 1 : 0.3)
        }
    }

    // MARK: - Seek Bar

    @ViewBuilder
    private func seekBar(zone: RoonZone, nowPlaying: NowPlaying) -> some View {
        let position = Double(roonService.seekPosition)
        let duration = Double(nowPlaying.length ?? 0)

        HStack(spacing: 8) {
            Text(formatTime(Int(position)))
                .font(.system(size: 10))
                .foregroundStyle(Color.roonSecondary)
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.roonSeparator.opacity(0.5))
                        .frame(height: 3)
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
                        roonService.seek(position: Int(fraction * duration))
                    }
                }
            }
            .frame(height: 3)

            Text(formatTime(Int(duration)))
                .font(.system(size: 10))
                .foregroundStyle(Color.roonSecondary)
                .monospacedDigit()
                .frame(width: 34, alignment: .leading)
        }
        .animation(.linear(duration: 1.0), value: roonService.seekPosition)
    }

    // MARK: - Volume

    @ViewBuilder
    private func volumeControl(zone: RoonZone) -> some View {
        if let output = zone.outputs?.first,
           let volume = output.volume,
           let value = volume.value,
           let min = volume.min,
           let max = volume.max {
            HStack(spacing: 6) {
                Button {
                    roonService.toggleMute(outputId: output.output_id)
                } label: {
                    Image(systemName: volumeIcon(value: value, isMuted: volume.is_muted ?? false, max: max))
                        .font(.system(size: 12))
                        .foregroundStyle((volume.is_muted ?? false) ? Color.roonRed : Color.roonSecondary)
                        .frame(width: 18)
                }
                .buttonStyle(.plain)

                Slider(
                    value: Binding(
                        get: { value },
                        set: { roonService.setVolume(outputId: output.output_id, value: $0) }
                    ),
                    in: min...max,
                    step: volume.step ?? 1
                )
                .controlSize(.mini)
                .tint(Color.roonAccent)
                .frame(width: 80)

                Text("\(Int(value))")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(Color.roonSecondary)
                    .frame(width: 26, alignment: .trailing)
            }
        }
    }

    // MARK: - Zone Button

    private var zoneButton: some View {
        Menu {
            ForEach(roonService.zones) { zone in
                Button {
                    roonService.selectZone(zone)
                } label: {
                    HStack {
                        Text(zone.display_name)
                        if zone.zone_id == roonService.currentZone?.zone_id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "hifispeaker.2")
                .font(.system(size: 14))
                .foregroundStyle(Color.roonSecondary)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.roonGrey2.opacity(0.5))
                )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Helpers

    private func formatTime(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func volumeIcon(value: Double, isMuted: Bool, max: Double) -> String {
        if isMuted { return "speaker.slash.fill" }
        let ratio = value / max
        if ratio > 0.66 { return "speaker.wave.3.fill" }
        if ratio > 0.33 { return "speaker.wave.2.fill" }
        if ratio > 0 { return "speaker.wave.1.fill" }
        return "speaker.fill"
    }
}
