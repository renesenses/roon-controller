import SwiftUI

struct RoonHistoryView: View {
    @EnvironmentObject var roonService: RoonService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if roonService.playbackHistory.isEmpty {
                emptyState
            } else {
                header
                Divider().overlay(Color.roonSeparator.opacity(0.3))
                historyList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text("Historique")
                .font(.inter(28))
                .foregroundStyle(Color.roonText)
                .tracking(-0.8)

            Text("\(roonService.playbackHistory.count) morceaux")
                .font(.lato(12))
                .foregroundStyle(Color.roonSecondary)

            Spacer()

            Button {
                roonService.clearHistory()
            } label: {
                Text("Effacer")
                    .font(.latoBold(12))
                    .foregroundStyle(Color.roonRed)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.roonRed.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .padding(.bottom, 16)
    }

    // MARK: - History List

    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(roonService.playbackHistory) { item in
                    historyRow(item)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - History Row

    private func historyRow(_ item: PlaybackHistoryItem) -> some View {
        Button {
            roonService.searchAndPlay(title: item.title, artist: item.artist, album: item.album, isRadio: item.isRadio)
        } label: {
            HStack(spacing: 14) {
                // Album art
                albumArt(imageKey: roonService.resolvedImageKey(title: item.title, imageKey: item.image_key))

                // Track info
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.latoBold(14))
                        .foregroundStyle(Color.roonText)
                        .lineLimit(1)
                    if !item.artist.isEmpty {
                        Text(item.artist)
                            .font(.lato(13))
                            .foregroundStyle(Color.roonSecondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 4) {
                        Text(item.zone_name)
                            .font(.lato(11))
                            .foregroundStyle(Color.roonTertiary)
                        Text("\u{00B7}")
                            .font(.lato(11))
                            .foregroundStyle(Color.roonTertiary)
                        Text(timeAgo(item.playedAt))
                            .font(.lato(11))
                            .foregroundStyle(Color.roonTertiary)
                    }
                }

                Spacer()

                // Duration
                if let length = item.length {
                    Text(formatDuration(length))
                        .font(.lato(11))
                        .monospacedDigit()
                        .foregroundStyle(Color.roonTertiary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight()
    }

    // MARK: - Album Art

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
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            artPlaceholder
        }
    }

    private var artPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.roonGrey2)
            .frame(width: 48, height: 48)
            .overlay {
                Image(systemName: "clock")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.roonTertiary)
            }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock")
                .font(.system(size: 40))
                .foregroundStyle(Color.roonTertiary)
            Text("Aucun historique")
                .font(.inter(24))
                .foregroundStyle(Color.roonSecondary)
            Text("Les morceaux ecoutes apparaitront ici")
                .font(.lato(13))
                .foregroundStyle(Color.roonTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return String(localized: "maintenant") }
        if interval < 3600 { return String(localized: "il y a \(Int(interval / 60)) min") }
        if interval < 86400 { return String(localized: "il y a \(Int(interval / 3600))h") }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
