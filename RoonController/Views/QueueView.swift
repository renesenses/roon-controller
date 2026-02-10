import SwiftUI

struct QueueView: View {
    @EnvironmentObject var roonService: RoonService

    var body: some View {
        if roonService.queueItems.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "music.note.list")
                    .font(.title2)
                    .foregroundStyle(Color.roonTertiary)
                Text("File d'attente vide")
                    .font(.caption)
                    .foregroundStyle(Color.roonSecondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List(roonService.queueItems) { item in
                Button {
                    roonService.playFromHere(queueItemId: item.queue_item_id)
                } label: {
                    HStack(spacing: 10) {
                        if let url = roonService.imageURL(key: item.image_key, width: 80, height: 80) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().aspectRatio(contentMode: .fill)
                                default:
                                    Color.roonSurface
                                }
                            }
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.three_line?.line1 ?? item.one_line?.line1 ?? "")
                                .foregroundStyle(Color.roonText)
                                .lineLimit(1)
                            Text(item.three_line?.line2 ?? "")
                                .font(.caption)
                                .foregroundStyle(Color.roonSecondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if let length = item.length {
                            Text(formatDuration(length))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(Color.roonTertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isCurrentlyPlaying(item) ? Color.roonAccent.opacity(0.15) : Color.clear)
                        .padding(.horizontal, 4)
                )
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

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
