import SwiftUI

struct RoonContentView: View {
    @EnvironmentObject var roonService: RoonService
    @Binding var selectedSection: RoonSection
    var toggleSidebar: () -> Void = {}

    @State private var dernierementTab: DernierementTab = .lus

    var body: some View {
        Group {
            switch selectedSection {
            case .home:
                homeContent
            case .browse:
                RoonBrowseContentView()
            case .queue:
                QueueView()
            case .radio:
                RoonBrowseContentView(startWithRadio: true)
            case .history:
                HistoryView()
            case .favorites:
                FavoritesView()
            case .nowPlaying:
                RoonNowPlayingView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedSection)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            Button(action: toggleSidebar) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.roonSecondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .padding(.leading, 12)
            .keyboardShortcut("\\", modifiers: .command)
        }
        .background(Color.roonBackground)
    }

    // MARK: - Home Constants (matching Roon native)

    private let pagePadding: CGFloat = 40
    private let sectionSpacing: CGFloat = 48
    private let cardSize: CGFloat = 280
    private let cardGap: CGFloat = 24
    private let cardImageRes: Int = 640
    private let dernierementCardSize: CGFloat = 180

    // MARK: - Tab Enum

    private enum DernierementTab {
        case lus, ajoute
    }

    // MARK: - Home

    private var homeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 40)

                // Greeting
                greetingHeader
                    .padding(.bottom, 32)

                // Library stats
                if !roonService.libraryCounts.isEmpty {
                    libraryStatsRow
                        .padding(.bottom, sectionSpacing)
                }

                // Dernierement (recently played / recently added)
                if !recentPlayedTiles.isEmpty || !recentlyAddedTiles.isEmpty {
                    dernierementSection
                        .padding(.bottom, sectionSpacing)
                }

                Spacer().frame(height: 40)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Greeting Header

    private var greetingHeader: some View {
        let fullName = NSFullUserName()
        let firstName = fullName.components(separatedBy: " ").first ?? fullName
        return Text("Bonjour, \(firstName)")
            .font(.grifoM(48))
            .foregroundStyle(Color.roonText)
            .padding(.horizontal, pagePadding)
    }

    // MARK: - Library Stats Row

    private var libraryStatsRow: some View {
        HStack(spacing: 16) {
            statCard(icon: "person.2", count: roonService.libraryCounts["artists"] ?? 0, label: "ARTISTES")
            statCard(icon: "opticaldisc", count: roonService.libraryCounts["albums"] ?? 0, label: "ALBUMS")
            statCard(icon: "music.note", count: roonService.libraryCounts["tracks"] ?? 0, label: "MORCEAUX")
            statCard(icon: "music.quarternote.3", count: roonService.libraryCounts["composers"] ?? 0, label: "COMPOSITEURS")
        }
        .padding(.horizontal, pagePadding)
    }

    private func statCard(icon: String, count: Int, label: LocalizedStringKey) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(Color.roonAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(formatCount(count))
                    .font(.latoBold(30))
                    .foregroundStyle(Color.roonText)
                Text(label)
                    .font(.lato(11))
                    .foregroundStyle(Color.roonSecondary)
                    .tracking(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.roonPanel)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.roonSeparator, lineWidth: 0.5)
                )
        )
        .hoverScale()
    }

    private func formatCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    // MARK: - Dernierement Section (blue accent background)

    private var dernierementSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header row
            HStack(spacing: 16) {
                Text("Dernierement")
                    .font(.inter(28))
                    .foregroundStyle(.white)

                Spacer()

                // Tabs
                HStack(spacing: 0) {
                    dernierementTabButton("LUS", isSelected: dernierementTab == .lus) {
                        dernierementTab = .lus
                    }
                    dernierementTabButton("AJOUTÉS", isSelected: dernierementTab == .ajoute) {
                        dernierementTab = .ajoute
                    }
                }

                // Nav arrows
                HStack(spacing: 8) {
                    Button { } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(.white.opacity(0.15)))
                    }
                    .buttonStyle(.plain)

                    Button { } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(.white.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                }

                // PLUS button
                Button {
                    selectedSection = .history
                } label: {
                    Text("PLUS")
                        .font(.latoBold(11))
                        .foregroundStyle(.white.opacity(0.9))
                        .tracking(1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(.white.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)

            // Horizontal scroll of album cards
            let tiles = dernierementTab == .lus ? recentPlayedTiles : recentlyAddedTiles
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(tiles, id: \.id) { tile in
                        dernierementCard(tile)
                            .hoverScale()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.roonAccent)
        )
        .padding(.horizontal, pagePadding)
    }

    private func dernierementTabButton(_ title: LocalizedStringKey, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.latoBold(12))
                .foregroundStyle(.white)
                .tracking(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? .white.opacity(0.2) : .clear)
                )
        }
        .buttonStyle(.plain)
    }

    private func dernierementCard(_ tile: HomeTile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let url = roonService.imageURL(key: tile.imageKey, width: 320, height: 320) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Color.white.opacity(0.1)
                    }
                }
                .frame(width: dernierementCardSize, height: dernierementCardSize)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.1))
                    .frame(width: dernierementCardSize, height: dernierementCardSize)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.4))
                    }
            }

            Text(tile.title)
                .font(.lato(13))
                .foregroundStyle(.white)
                .lineLimit(1)

            if let subtitle = tile.subtitle {
                Text(subtitle)
                    .font(.lato(11))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .frame(width: dernierementCardSize)
    }

    // MARK: - Tile Data

    private var recentPlayedTiles: [HomeTile] {
        roonService.playbackHistory.prefix(20).map { item in
            HomeTile(
                id: item.id.uuidString,
                title: item.title,
                subtitle: item.artist.isEmpty ? nil : item.artist,
                imageKey: item.image_key
            )
        }
    }

    private var recentlyAddedTiles: [HomeTile] {
        roonService.recentlyAdded.prefix(20).map { item in
            HomeTile(
                id: item.item_key ?? item.title ?? UUID().uuidString,
                title: item.title ?? "",
                subtitle: item.subtitle,
                imageKey: item.image_key
            )
        }
    }

}

// MARK: - Supporting Types

private struct HomeTile {
    let id: String
    let title: String
    let subtitle: String?
    let imageKey: String?
}
