import SwiftUI

struct RoonQueueView: View {
    @EnvironmentObject var roonService: RoonService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if roonService.queueItems.isEmpty {
                emptyState
            } else {
                header
                Divider().overlay(Color.roonSeparator.opacity(0.3))
                queueList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text("Queue")
                .font(.inter(28))
                .trackingCompat(-0.8)
                .foregroundStyle(Color.roonText)

            Text("\(roonService.queueItems.count) tracks")
                .font(.lato(12))
                .foregroundStyle(Color.roonSecondary)

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .padding(.bottom, 16)
    }

    // MARK: - Queue List

    private var queueList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(roonService.queueItems) { item in
                    queueRow(item)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Queue Row

    private func queueRow(_ item: QueueItem) -> some View {
        let isCurrent = isCurrentlyPlaying(item)
        return Button {
            roonService.playFromHere(queueItemId: item.queue_item_id)
        } label: {
            HStack(spacing: 14) {
                // Now-playing accent border
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isCurrent ? Color.roonAccent : Color.clear)
                    .frame(width: 3, height: 40)

                // Album art
                albumArt(imageKey: roonService.resolvedImageKey(title: item.three_line?.line1, imageKey: item.image_key))

                // Track info
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.three_line?.line1 ?? item.one_line?.line1 ?? "")
                        .font(.latoBold(14))
                        .foregroundStyle(isCurrent ? Color.roonAccent : Color.roonText)
                        .lineLimit(1)
                    if let artist = item.three_line?.line2, !artist.isEmpty {
                        Text(artist)
                            .font(.lato(13))
                            .foregroundStyle(Color.roonSecondary)
                            .lineLimit(1)
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
            .background(isCurrent ? Color.roonAccent.opacity(0.08) : Color.clear)
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
                Image(systemName: "music.note")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.roonTertiary)
            }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundStyle(Color.roonTertiary)
            Text("Queue is empty")
                .font(.inter(24))
                .foregroundStyle(Color.roonSecondary)
            Text("Play a track to fill the queue")
                .font(.lato(13))
                .foregroundStyle(Color.roonTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func isCurrentlyPlaying(_ item: QueueItem) -> Bool {
        guard let nowPlaying = roonService.currentZone?.now_playing else { return false }
        if let queueLine = item.three_line?.line1, let npLine = nowPlaying.three_line?.line1 {
            return queueLine == npLine
        }
        return roonService.queueItems.first?.queue_item_id == item.queue_item_id
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
