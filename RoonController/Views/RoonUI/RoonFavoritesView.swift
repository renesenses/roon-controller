import SwiftUI

struct RoonFavoritesView: View {
    @EnvironmentObject var roonService: RoonService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if roonService.radioFavorites.isEmpty {
                emptyState
            } else {
                header

                // Playlist creation status
                if let status = roonService.playlistCreationStatus {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.mini)
                        Text(status)
                            .font(.lato(12))
                            .foregroundStyle(Color.roonSecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                }

                Divider().overlay(Color.roonSeparator.opacity(0.3))
                favoritesList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text("Favoris")
                .font(.inter(28))
                .trackingCompat(-0.8)
                .foregroundStyle(Color.roonText)

            Text("\(roonService.radioFavorites.count) morceaux")
                .font(.lato(12))
                .foregroundStyle(Color.roonSecondary)

            Spacer()

            Button {
                roonService.exportFavoritesCSV()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11))
                    Text("Exporter")
                        .font(.latoBold(12))
                }
                .foregroundStyle(Color.roonAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.roonAccent.opacity(0.1))
                )
            }
            .buttonStyle(.plain)

            Button {
                roonService.clearRadioFavorites()
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

    // MARK: - Favorites List

    private var favoritesList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(roonService.radioFavorites) { fav in
                    favoriteRow(fav)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Favorite Row

    private func favoriteRow(_ fav: RadioFavorite) -> some View {
        HStack(spacing: 14) {
            // Album art
            albumArt(imageKey: roonService.resolvedImageKey(title: fav.title, imageKey: fav.image_key))

            // Track info
            VStack(alignment: .leading, spacing: 3) {
                Text(fav.title)
                    .font(.latoBold(14))
                    .foregroundStyle(Color.roonText)
                    .lineLimit(1)
                if !fav.artist.isEmpty {
                    Text(fav.artist)
                        .font(.lato(13))
                        .foregroundStyle(Color.roonSecondary)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    if !fav.stationName.isEmpty {
                        Text(fav.stationName)
                            .font(.lato(11))
                            .foregroundStyle(Color.roonTertiary)
                        Text("\u{00B7}")
                            .font(.lato(11))
                            .foregroundStyle(Color.roonTertiary)
                    }
                    Text(formatDate(fav.savedAt))
                        .font(.lato(11))
                        .foregroundStyle(Color.roonTertiary)
                }
            }

            Spacer()

            // Delete button
            DeleteButton {
                roonService.removeRadioFavorite(id: fav.id)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            let station = fav.stationName.isEmpty ? fav.title : fav.stationName
            roonService.searchAndPlay(title: station, isRadio: true)
        }
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
                Image(systemName: "heart")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.roonTertiary)
            }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "heart")
                .font(.system(size: 40))
                .foregroundStyle(Color.roonTertiary)
            Text("Aucun favori")
                .font(.inter(24))
                .foregroundStyle(Color.roonSecondary)
            Text("Ecoutez une radio et cliquez sur le coeur")
                .font(.lato(13))
                .foregroundStyle(Color.roonTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Delete Button with hover effect

private struct DeleteButton: View {
    @State private var isHovered = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 13))
                .foregroundStyle(isHovered ? Color.roonRed : Color.roonTertiary)
                .frame(width: 28, height: 28)
                .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
