import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var roonService: RoonService

    var body: some View {
        VStack(spacing: 0) {
            if roonService.playbackHistory.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "clock")
                        .font(.title2)
                        .foregroundStyle(Color.roonTertiary)
                    Text("Aucun historique")
                        .font(.caption)
                        .foregroundStyle(Color.roonSecondary)
                    Spacer()
                }
            } else {
                HStack {
                    Text("\(roonService.playbackHistory.count) morceaux")
                        .font(.caption)
                        .foregroundStyle(Color.roonSecondary)
                    Spacer()
                    Button {
                        roonService.clearHistory()
                    } label: {
                        Text("Effacer")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Divider()
                    .overlay(Color.roonTertiary.opacity(0.3))

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(roonService.playbackHistory) { item in
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
                                } else {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.roonSurface)
                                        .frame(width: 40, height: 40)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .foregroundStyle(Color.roonText)
                                        .lineLimit(1)
                                    if !item.artist.isEmpty {
                                        Text(item.artist)
                                            .font(.caption)
                                            .foregroundStyle(Color.roonSecondary)
                                            .lineLimit(1)
                                    }
                                    HStack(spacing: 4) {
                                        Text(item.zone_name)
                                            .font(.caption2)
                                            .foregroundStyle(Color.roonTertiary)
                                        Text("·")
                                            .font(.caption2)
                                            .foregroundStyle(Color.roonTertiary)
                                        Text(timeAgo(item.playedAt))
                                            .font(.caption2)
                                            .foregroundStyle(Color.roonTertiary)
                                    }
                                }

                                Spacer()

                                if let length = item.length {
                                    Text(formatDuration(length))
                                        .font(.caption2)
                                        .monospacedDigit()
                                        .foregroundStyle(Color.roonTertiary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "maintenant" }
        if interval < 3600 { return "il y a \(Int(interval / 60)) min" }
        if interval < 86400 { return "il y a \(Int(interval / 3600))h" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
