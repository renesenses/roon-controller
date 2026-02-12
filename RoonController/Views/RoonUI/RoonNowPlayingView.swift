import SwiftUI

struct RoonNowPlayingView: View {
    @EnvironmentObject var roonService: RoonService

    var body: some View {
        ZStack {
            if let zone = roonService.currentZone, let np = zone.now_playing {
                // Blurred album art background
                blurredBackground(imageKey: np.image_key)

                GeometryReader { geo in
                    let isWide = geo.size.width > 700

                    if isWide {
                        wideLayout(zone: zone, nowPlaying: np, size: geo.size)
                    } else {
                        compactLayout(zone: zone, nowPlaying: np, size: geo.size)
                    }
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.roonBackground)
    }

    // MARK: - Wide Layout (art left, info right)

    private func wideLayout(zone: RoonZone, nowPlaying: NowPlaying, size: CGSize) -> some View {
        HStack(spacing: 40) {
            Spacer(minLength: 20)

            // Album art
            albumArt(imageKey: nowPlaying.image_key, size: artSize(for: size))

            // Track info + settings
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 20)

                trackInfo(nowPlaying: nowPlaying)

                Spacer().frame(height: 28)

                settingsRow(zone: zone)

                Spacer().frame(height: 28)

                // Up next mini-queue
                upNextSection

                Spacer(minLength: 20)
            }
            .frame(maxWidth: 360)

            Spacer(minLength: 20)
        }
        .padding(.vertical, 30)
    }

    // MARK: - Compact Layout (stacked)

    private func compactLayout(zone: RoonZone, nowPlaying: NowPlaying, size: CGSize) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 10)

                albumArt(imageKey: nowPlaying.image_key, size: artSize(for: size))

                trackInfo(nowPlaying: nowPlaying)

                settingsRow(zone: zone)

                upNextSection

                Spacer(minLength: 20)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Blurred Background

    @ViewBuilder
    private func blurredBackground(imageKey: String?) -> some View {
        if let url = roonService.imageURL(key: imageKey, width: 600, height: 600) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 100)
                        .opacity(0.25)
                }
            }
            .id(imageKey)
            .transition(.opacity)
            .ignoresSafeArea()
            .overlay(Color.roonBackground.opacity(0.65))
        }
    }

    // MARK: - Album Art

    private func artSize(for viewSize: CGSize) -> CGFloat {
        let maxArt = min(viewSize.height * 0.6, viewSize.width * 0.4)
        return min(max(maxArt, 200), 480)
    }

    @ViewBuilder
    private func albumArt(imageKey: String?, size: CGFloat) -> some View {
        if let url = roonService.imageURL(key: imageKey, width: 800, height: 800) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fit)
                default:
                    artPlaceholder(size: size)
                }
            }
            .id(imageKey)
            .transition(.opacity)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 10)
        } else {
            artPlaceholder(size: size)
        }
    }

    private func artPlaceholder(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.roonPanel)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.15))
                    .foregroundStyle(Color.roonTertiary)
            }
    }

    // MARK: - Track Info

    private func trackInfo(nowPlaying: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title — large, brand serif
            Text(nowPlaying.three_line?.line1 ?? "")
                .font(.grifoM(28))
                .foregroundStyle(Color.roonText)
                .lineLimit(2)

            // Artist — serif subtitle
            if let artist = nowPlaying.three_line?.line2, !artist.isEmpty {
                Text(artist)
                    .font(.grifoS(18))
                    .foregroundStyle(Color.roonSecondary)
                    .lineLimit(1)
            }

            // Album
            if let album = nowPlaying.three_line?.line3, !album.isEmpty {
                Text(album)
                    .font(.lato(14))
                    .foregroundStyle(Color.roonTertiary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Settings Row

    private func settingsRow(zone: RoonZone) -> some View {
        HStack(spacing: 20) {
            settingButton(
                icon: "shuffle",
                isActive: zone.settings?.shuffle ?? false,
                action: { roonService.setShuffle(!(zone.settings?.shuffle ?? false)) }
            )

            settingButton(
                icon: (zone.settings?.loop ?? "disabled") == "loop_one" ? "repeat.1" : "repeat",
                isActive: (zone.settings?.loop ?? "disabled") != "disabled",
                action: {
                    let current = zone.settings?.loop ?? "disabled"
                    let next: String
                    switch current {
                    case "disabled": next = "loop"
                    case "loop": next = "loop_one"
                    default: next = "disabled"
                    }
                    roonService.setLoop(next)
                }
            )

            settingButton(
                icon: "antenna.radiowaves.left.and.right",
                isActive: zone.settings?.auto_radio ?? false,
                action: { roonService.setAutoRadio(!(zone.settings?.auto_radio ?? false)) }
            )

            if zone.is_seek_allowed == false {
                settingButton(
                    icon: roonService.isCurrentTrackFavorite() ? "heart.fill" : "heart",
                    isActive: roonService.isCurrentTrackFavorite(),
                    activeColor: Color.roonRed,
                    action: { roonService.saveRadioFavorite() }
                )
            }
        }
    }

    private func settingButton(icon: String, isActive: Bool, activeColor: Color = Color.roonAccent, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(isActive ? activeColor : Color.roonTertiary)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(isActive ? activeColor.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Up Next

    private var upNextSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !roonService.queueItems.isEmpty {
                Text("A SUIVRE")
                    .font(.latoBold(10))
                    .foregroundStyle(Color.roonTertiary)
                    .tracking(1.2)

                VStack(spacing: 0) {
                    ForEach(roonService.queueItems.prefix(5), id: \.queue_item_id) { item in
                        queueRow(item)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.roonPanel.opacity(0.6))
                )
            }
        }
    }

    private func queueRow(_ item: QueueItem) -> some View {
        HStack(spacing: 10) {
            if let url = roonService.imageURL(key: item.image_key, width: 80, height: 80) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.roonGrey2
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.roonGrey2)
                    .frame(width: 36, height: 36)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.three_line?.line1 ?? item.one_line?.line1 ?? "")
                    .font(.latoBold(12))
                    .foregroundStyle(Color.roonText)
                    .lineLimit(1)
                if let artist = item.three_line?.line2, !artist.isEmpty {
                    Text(artist)
                        .font(.lato(11))
                        .foregroundStyle(Color.roonSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let length = item.length, length > 0 {
                Text(formatTime(length))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.roonTertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            roonService.playFromHere(queueItemId: item.queue_item_id)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 48))
                .foregroundStyle(Color.roonTertiary)
            Text("Rien en lecture")
                .font(.grifoM(18))
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
