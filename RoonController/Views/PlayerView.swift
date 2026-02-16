import SwiftUI
import AppKit

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
                    albumArtBackground(imageKey: roonService.resolvedImageKey(for: nowPlaying))

                    playerContent(zone: zone, nowPlaying: nowPlaying)
                        .opacity(roonService.playbackTransitioning ? 0.4 : 1.0)
                        .animation(.easeInOut(duration: 0.3), value: roonService.playbackTransitioning)
                } else {
                    emptyState(zone: zone)
                }
            } else {
                noZoneSelected
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    togglePlayerSidebar()
                } label: {
                    Image(systemName: "sidebar.leading")
                        .foregroundStyle(Color.roonSecondary)
                }
                .help("Show/hide sidebar (⌘\\)")
                .keyboardShortcut("\\", modifiers: .command)
            }
        }
    }

    /// Toggle the sidebar, handling the case where the user dragged the divider to zero width.
    private func togglePlayerSidebar() {
        guard let window = NSApp.keyWindow,
              let splitVC = findSplitViewController(from: window.contentViewController),
              !splitVC.splitViewItems.isEmpty else {
            NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
            return
        }

        let sidebarItem = splitVC.splitViewItems[0]

        if sidebarItem.isCollapsed {
            sidebarItem.isCollapsed = false
        } else {
            let sidebarWidth = splitVC.splitView.subviews[0].frame.width
            if sidebarWidth < 1 {
                // Sidebar was dragged to zero — restore it
                splitVC.splitView.setPosition(250, ofDividerAt: 0)
            } else {
                sidebarItem.isCollapsed = true
            }
        }
    }

    private func findSplitViewController(from vc: NSViewController?) -> NSSplitViewController? {
        guard let vc = vc else { return nil }
        if let splitVC = vc as? NSSplitViewController { return splitVC }
        for child in vc.children {
            if let found = findSplitViewController(from: child) { return found }
        }
        return nil
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
            .id(imageKey)
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
            albumArt(imageKey: roonService.resolvedImageKey(for: nowPlaying))

            // Track Info
            trackInfo(nowPlaying: nowPlaying)

            // Seek Bar
            seekBar(zone: zone, nowPlaying: nowPlaying)

            // Transport Controls
            transportControls(zone: zone)

            // Shuffle / Repeat / Radio
            settingsControls(zone: zone)

            // Volume
            volumeControl(zone: zone)

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
                        .accentColor(.roonSecondary)
                        .frame(width: 400, height: 400)
                @unknown default:
                    artPlaceholder
                }
            }
            .id(imageKey)
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
        let title = nowPlaying.three_line?.line1 ?? "Unknown title"
        let artist = nowPlaying.three_line?.line2 ?? ""
        let album = nowPlaying.three_line?.line3 ?? ""

        VStack(spacing: 6) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(Color.roonText)
                .lineLimit(1)
                .id(title)

            Text(artist)
                .font(.title3)
                .foregroundStyle(Color.roonSecondary)
                .lineLimit(1)
                .id(artist)

            Text(album)
                .font(.body)
                .foregroundStyle(Color.roonTertiary)
                .lineLimit(1)
                .id(album)
        }
        .animation(.easeInOut(duration: 0.3), value: title)
    }

    // MARK: - Seek Bar

    @ViewBuilder
    private func seekBar(zone: RoonZone, nowPlaying: NowPlaying) -> some View {
        let position = Double(roonService.seekPosition)
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
        .animation(.linear(duration: 1.0), value: roonService.seekPosition)
    }

    // MARK: - Transport Controls

    @ViewBuilder
    private func transportControls(zone: RoonZone) -> some View {
        HStack(spacing: 40) {
            Button { roonService.previous() } label: {
                Image(systemName: "chevron.backward")
                    .font(.title2)
                    .foregroundStyle(Color.roonText)
            }
            .buttonStyle(.plain)
            .disabled(!(zone.is_previous_allowed ?? true))
            .opacity((zone.is_previous_allowed ?? true) ? 1 : 0.3)

            Button { roonService.playPause() } label: {
                Image(systemName: zone.state == "playing" ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Color.roonText)
            }
            .buttonStyle(.plain)

            Button { roonService.next() } label: {
                Image(systemName: "chevron.forward")
                    .font(.title2)
                    .foregroundStyle(Color.roonText)
            }
            .buttonStyle(.plain)
            .disabled(!(zone.is_next_allowed ?? true))
            .opacity((zone.is_next_allowed ?? true) ? 1 : 0.3)
        }
        .animation(.easeInOut(duration: 0.2), value: zone.state)
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

            if zone.is_seek_allowed == false {
                Button { roonService.saveRadioFavorite() } label: {
                    Image(systemName: roonService.isCurrentTrackFavorite() ? "heart.fill" : "heart")
                        .foregroundStyle(roonService.isCurrentTrackFavorite() ? .red : Color.roonTertiary)
                }
                .buttonStyle(.plain)
                .help("Save to radio favorites")
            }
        }
    }

    // MARK: - Volume Control

    @ViewBuilder
    private func volumeControl(zone: RoonZone) -> some View {
        if let output = zone.outputs?.first,
           let volume = output.volume,
           let value = volume.value,
           let min = volume.min,
           let max = volume.max {
            let step = Int(volume.step?.rounded(.up) ?? 1)
            let outputId = output.output_id
            let intValue = Int(value.rounded())
            HStack(spacing: 12) {
                Button {
                    roonService.toggleMute(outputId: outputId)
                } label: {
                    Image(systemName: volumeIcon(value: value, isMuted: volume.is_muted ?? false, max: max))
                        .font(.system(size: 16))
                        .foregroundStyle((volume.is_muted ?? false) ? Color.roonRed : Color.roonSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                VolumeRepeatButton(
                    systemName: "minus.circle.fill",
                    color: Color.roonSecondary
                ) {
                    roonService.adjustVolume(outputId: outputId, delta: Double(-step))
                }

                GeometryReader { geo in
                    let fraction = (value - min) / (max - min)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.roonTertiary.opacity(0.3))
                            .frame(height: 4)
                        Capsule()
                            .fill(Color.roonAccent)
                            .frame(width: geo.size.width * Swift.min(Swift.max(fraction, 0), 1), height: 4)
                    }
                    .frame(height: 4)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                let ratio = Swift.max(0, Swift.min(1, drag.location.x / geo.size.width))
                                let snapped = (ratio * (max - min) / Double(step)).rounded() * Double(step) + min
                                roonService.setVolume(outputId: outputId, value: Swift.max(min, Swift.min(max, snapped)))
                            }
                    )
                }
                .frame(maxWidth: 180, maxHeight: 28)

                VolumeRepeatButton(
                    systemName: "plus.circle.fill",
                    color: Color.roonSecondary
                ) {
                    roonService.adjustVolume(outputId: outputId, delta: Double(step))
                }

                Text("\(intValue) dB")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.roonSecondary)
                    .frame(width: 46, alignment: .trailing)
            }
            .frame(maxWidth: 380)
        }
    }

    private func volumeIcon(value: Double, isMuted: Bool, max: Double) -> String {
        if isMuted { return "speaker.slash.fill" }
        let ratio = value / max
        if ratio > 0.66 { return "speaker.wave.3.fill" }
        if ratio > 0.33 { return "speaker.wave.2.fill" }
        if ratio > 0 { return "speaker.wave.1.fill" }
        return "speaker.fill"
    }

    // MARK: - Empty States

    @ViewBuilder
    private func emptyState(zone: RoonZone) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 48))
                .foregroundStyle(Color.roonTertiary)
            Text("Nothing playing")
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
            Text("Select a zone")
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

// MARK: - Volume Repeat Button

/// A button that fires once on tap and repeats while held down.
private struct VolumeRepeatButton: View {
    let systemName: String
    let color: Color
    let action: () -> Void

    @State private var repeatTask: Task<Void, Never>?
    @State private var pressing = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 22))
            .foregroundStyle(color)
            .opacity(pressing ? 0.5 : 1.0)
            .frame(width: 36, height: 36)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressing else { return }
                        pressing = true
                        action()
                        repeatTask = Task { @MainActor in
                            while !Task.isCancelled {
                                try? await Task.sleep(nanoseconds: 200_000_000)
                                guard !Task.isCancelled else { break }
                                action()
                            }
                        }
                    }
                    .onEnded { _ in
                        pressing = false
                        repeatTask?.cancel()
                        repeatTask = nil
                    }
            )
    }
}
