import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject var roonService: RoonService

    var body: some View {
        VStack(spacing: 0) {
            if roonService.radioFavorites.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "heart")
                        .font(.title2)
                        .foregroundStyle(Color.roonTertiary)
                    Text("No favorites")
                        .font(.caption)
                        .foregroundStyle(Color.roonSecondary)
                    Text("Listen to a radio station and click the heart")
                        .font(.caption2)
                        .foregroundStyle(Color.roonTertiary)
                    Spacer()
                }
            } else {
                // Header
                HStack {
                    Text("\(roonService.radioFavorites.count) favorites")
                        .font(.caption)
                        .foregroundStyle(Color.roonSecondary)
                    Spacer()
                    Button {
                        roonService.exportFavoritesCSV()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export")
                        }
                        .font(.caption)
                        .foregroundStyle(Color.roonAccent)
                    }
                    .buttonStyle(.plain)

                    Button {
                        roonService.clearRadioFavorites()
                    } label: {
                        Text("Clear")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                // Playlist creation status
                if let status = roonService.playlistCreationStatus {
                    HStack {
                        ProgressView()
                            .controlSize(.mini)
                        Text(status)
                            .font(.caption2)
                            .foregroundStyle(Color.roonSecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }

                Divider()
                    .overlay(Color.roonTertiary.opacity(0.3))

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(roonService.radioFavorites) { fav in
                            HStack(spacing: 10) {
                                if let url = roonService.imageURL(key: fav.image_key, width: 80, height: 80) {
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
                                    Text(fav.title)
                                        .foregroundStyle(Color.roonText)
                                        .lineLimit(1)
                                    if !fav.artist.isEmpty {
                                        Text(fav.artist)
                                            .font(.caption)
                                            .foregroundStyle(Color.roonSecondary)
                                            .lineLimit(1)
                                    }
                                    Text(formatDate(fav.savedAt))
                                        .font(.caption2)
                                        .foregroundStyle(Color.roonTertiary)
                                }

                                Spacer()

                                Button {
                                    roonService.removeRadioFavorite(id: fav.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundStyle(Color.roonTertiary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                let station = fav.stationName.isEmpty ? fav.title : fav.stationName
                                roonService.searchAndPlay(
                                    title: station,
                                    isRadio: true
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
