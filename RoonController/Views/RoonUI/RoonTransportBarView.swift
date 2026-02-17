import SwiftUI

struct RoonTransportBarView: View {
    @EnvironmentObject var roonService: RoonService
    @AppStorage("uiMode") private var uiMode = "roon"
    var onNowPlayingTap: (() -> Void)?

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                if let zone = roonService.currentZone, let np = zone.now_playing {
                    // Left: album art + track info (clickable → Now Playing)
                    Button {
                        onNowPlayingTap?()
                    } label: {
                        HStack(spacing: 14) {
                            albumArt(imageKey: roonService.resolvedImageKey(for: np))
                            trackInfo(nowPlaying: np)
                        }
                        .frame(minWidth: 180, maxWidth: 280, alignment: .leading)
                        .opacity(roonService.playbackTransitioning ? 0.4 : 1.0)
                        .animation(.easeInOut(duration: 0.3), value: roonService.playbackTransitioning)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 18)

                    Spacer(minLength: 8)

                    // Center: transport controls + seek bar
                    VStack(spacing: 6) {
                        transportControls(zone: zone)
                        seekBar(zone: zone, nowPlaying: np)
                    }
                    .frame(maxWidth: 520)

                    Spacer(minLength: 8)

                    // Right: zone selector + volume + mode toggle
                    HStack(spacing: 14) {
                        zoneButton
                        if geo.size.width >= 950 {
                            volumeControl(zone: zone)
                        }
                        modeToggleButton
                    }
                    .frame(minWidth: 80, maxWidth: 290, alignment: .trailing)
                    .padding(.trailing, 18)
            } else if roonService.currentZone != nil {
                Spacer()
                Image(systemName: "music.note")
                    .foregroundStyle(Color.roonTertiary)
                Text("Nothing playing")
                    .font(.lato(14))
                    .foregroundStyle(Color.roonSecondary)
                Spacer()
                HStack(spacing: 14) {
                    zoneButton
                    modeToggleButton
                }
                .padding(.trailing, 18)
            } else {
                Spacer()
                Text("No zone selected")
                    .font(.lato(14))
                    .foregroundStyle(Color.roonSecondary)
                Spacer()
                HStack(spacing: 14) {
                    zoneButton
                    modeToggleButton
                }
                .padding(.trailing, 18)
            }
            }
        }
        .frame(height: 90)
        .background(Color.roonFooter)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.roonSeparator.opacity(0.3))
                .frame(height: 1)
        }
    }

    // MARK: - Album Art

    private let artSize: CGFloat = 56

    @ViewBuilder
    private func albumArt(imageKey: String?) -> some View {
        if let url = roonService.imageURL(key: imageKey, width: 160, height: 160) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    artPlaceholder
                }
            }
            .frame(width: artSize, height: artSize)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            artPlaceholder
        }
    }

    private var artPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.roonGrey2)
            .frame(width: artSize, height: artSize)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.roonTertiary)
            }
    }

    // MARK: - Track Info

    private func trackInfo(nowPlaying: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(nowPlaying.three_line?.line1 ?? "")
                .font(.latoBold(14))
                .foregroundStyle(Color.roonText)
                .lineLimit(1)
            Text(nowPlaying.three_line?.line2 ?? "")
                .font(.lato(13))
                .foregroundStyle(Color.roonSecondary)
                .lineLimit(1)
        }
    }

    // MARK: - Transport Controls

    private func transportControls(zone: RoonZone) -> some View {
        HStack(spacing: 24) {
            // Settings indicators (compact, only shown when active)
            settingsIndicators(zone: zone)

            // Roon: w-24 h-24 rounded-full bg-zinc-800/60
            Button { roonService.previous() } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.roonText)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(!(zone.is_previous_allowed ?? true))
            .opacity((zone.is_previous_allowed ?? true) ? 1 : 0.3)

            // Roon: bg-roon-primary rounded-full
            Button { roonService.playPause() } label: {
                ZStack {
                    Circle()
                        .fill(Color.roonAccent)
                        .frame(width: 40, height: 40)
                    Image(systemName: zone.state == "playing" ? "pause.fill" : "play.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .offset(x: zone.state == "playing" ? 0 : 1)
                }
            }
            .buttonStyle(.plain)

            Button { roonService.next() } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.roonText)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(!(zone.is_next_allowed ?? true))
            .opacity((zone.is_next_allowed ?? true) ? 1 : 0.3)
        }
    }

    // MARK: - Settings Indicators

    private func settingsIndicators(zone: RoonZone) -> some View {
        HStack(spacing: 6) {
            if zone.settings?.shuffle ?? false {
                Button { roonService.setShuffle(false) } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.roonAccent)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Shuffle")
            }

            if let loop = zone.settings?.loop, loop != "disabled" {
                Button {
                    let next: String = loop == "loop" ? "loop_one" : "disabled"
                    roonService.setLoop(next)
                } label: {
                    Image(systemName: loop == "loop_one" ? "repeat.1" : "repeat")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.roonAccent)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Repeat")
            }

            if zone.settings?.auto_radio ?? false {
                Button { roonService.setAutoRadio(false) } label: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.roonAccent)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Auto radio")
            }
        }
    }

    // MARK: - Seek Bar

    @ViewBuilder
    private func seekBar(zone: RoonZone, nowPlaying: NowPlaying) -> some View {
        let position = Double(roonService.seekPosition)
        let duration = Double(nowPlaying.length ?? 0)

        HStack(spacing: 8) {
            Text(formatTime(Int(position)))
                .font(.lato(10))
                .foregroundStyle(Color.roonSecondary)
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.roonSeparator.opacity(0.5))
                        .frame(height: 4)
                    if duration > 0 {
                        Capsule()
                            .fill(Color.roonAccent)
                            .frame(width: geo.size.width * min(position / duration, 1.0), height: 4)
                    }
                }
                .frame(height: 4)
                .contentShape(Rectangle().size(width: geo.size.width, height: 20).offset(y: -8))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if duration > 0 {
                                let fraction = max(0, min(1, value.location.x / geo.size.width))
                                roonService.seek(position: Int(fraction * duration))
                            }
                        }
                )
            }
            .frame(height: 4)

            Text(formatTime(Int(duration)))
                .font(.lato(10))
                .foregroundStyle(Color.roonSecondary)
                .monospacedDigit()
                .frame(width: 38, alignment: .leading)
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
                        .font(.system(size: 13))
                        .foregroundStyle((volume.is_muted ?? false) ? Color.roonRed : Color.roonSecondary)
                        .frame(width: 20)
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
                .accentColor(Color.roonAccent)
                .frame(width: 90)

                Text("\(Int(value))")
                    .font(.lato(10))
                    .monospacedDigit()
                    .foregroundStyle(Color.roonSecondary)
                    .frame(width: 26, alignment: .trailing)
            }
        }
    }

    // MARK: - Mode Toggle

    private var modeToggleButton: some View {
        Button {
            uiMode = uiMode == "roon" ? "player" : "roon"
        } label: {
            Image(systemName: "rectangle.2.swap")
                .font(.system(size: 14))
                .foregroundStyle(Color.roonSecondary)
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.roonGrey2.opacity(0.5))
                )
        }
        .buttonStyle(.plain)
        .help(uiMode == "roon" ? "Mode Player" : "Mode Roon")
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
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
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
