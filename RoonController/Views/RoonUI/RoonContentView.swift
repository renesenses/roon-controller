import SwiftUI

struct RoonContentView: View {
    @EnvironmentObject var roonService: RoonService
    @Binding var selectedSection: RoonSection
    var toggleSidebar: () -> Void = {}

    @State private var dernierementTab: DernierementTab = .lus
    @State private var scrollTarget: String?
    @State private var homeSearchText: String = ""

    var body: some View {
        Group {
            switch selectedSection {
            case .home:
                homeContent
            case .browse:
                RoonBrowseContentView()
            case .queue:
                RoonQueueView()
            case .radio:
                RoonBrowseContentView(startWithRadio: true)
            case .history:
                RoonHistoryView()
            case .favorites:
                RoonFavoritesView()
            case .nowPlaying:
                RoonNowPlayingView(onDismiss: {
                    selectedSection = .home
                })
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
        .background(Color.roonBackground, ignoresSafeAreaEdges: [])
    }

    // MARK: - Home Constants (matching Roon native)

    private let pagePadding: CGFloat = 40
    private let sectionSpacing: CGFloat = 48
    private let cardGap: CGFloat = 24
    private let dernierementCardSize: CGFloat = 180
    private let scrollStep: Int = 4

    // MARK: - Tab Enum

    private enum DernierementTab: Equatable {
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
                if !activeTiles.isEmpty {
                    dernierementSection
                        .padding(.bottom, sectionSpacing)
                }

                Spacer().frame(height: 40)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            // #3: Auto-switch to AJOUTÉS when LUS is empty
            if recentPlayedTiles.isEmpty && !recentlyAddedTiles.isEmpty {
                dernierementTab = .ajoute
            }
        }
    }

    // MARK: - Active tiles for current tab

    private var activeTiles: [HomeTile] {
        dernierementTab == .lus ? recentPlayedTiles : recentlyAddedTiles
    }

    // MARK: - Greeting Header

    private var greetingHeader: some View {
        let name: String
        if let profile = roonService.profileName {
            name = profile
        } else {
            let fullName = NSFullUserName()
            name = fullName.components(separatedBy: " ").first ?? fullName
        }
        return Text("Bonjour, \(name)")
            .font(.grifoM(48))
            .foregroundStyle(Color.roonText)
            .padding(.horizontal, pagePadding)
    }

    // MARK: - Home Search Bar

    private var homeSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(Color.roonSecondary)
            TextField("Rechercher...", text: $homeSearchText)
                .textFieldStyle(.plain)
                .font(.lato(15))
                .foregroundStyle(Color.roonText)
                .onSubmit {
                    let query = homeSearchText.trimmingCharacters(in: .whitespaces)
                    guard !query.isEmpty else { return }
                    roonService.browseSearch(query: query)
                    selectedSection = .browse
                    homeSearchText = ""
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.roonPanel)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.roonSeparator, lineWidth: 0.5)
                )
        )
        .padding(.horizontal, pagePadding)
    }

    // MARK: - Library Stats Row

    // Mapping from countKey to possible Roon category titles (FR/EN)
    private static let categoryTitlesForKey: [String: [String]] = [
        "artists": ["Artistes", "Artists"],
        "albums": ["Albums"],
        "tracks": ["Morceaux", "Tracks"],
        "composers": ["Compositeurs", "Composers"]
    ]

    private func browseCategoryTitle(forKey key: String) -> String? {
        guard let candidates = Self.categoryTitlesForKey[key] else { return nil }
        let sidebarTitles = roonService.sidebarCategories.compactMap(\.title)
        return candidates.first { sidebarTitles.contains($0) } ?? candidates.first
    }

    private var libraryStatsRow: some View {
        HStack(spacing: 16) {
            statCard(icon: "person.2", count: roonService.libraryCounts["artists"] ?? 0, label: "ARTISTES", countKey: "artists")
            statCard(icon: "opticaldisc", count: roonService.libraryCounts["albums"] ?? 0, label: "ALBUMS", countKey: "albums")
            statCard(icon: "music.note", count: roonService.libraryCounts["tracks"] ?? 0, label: "MORCEAUX", countKey: "tracks")
            statCard(icon: "music.quarternote.3", count: roonService.libraryCounts["composers"] ?? 0, label: "COMPOSITEURS", countKey: "composers")
        }
        .padding(.horizontal, pagePadding)
    }

    private func statCard(icon: String, count: Int, label: LocalizedStringKey, countKey: String) -> some View {
        Button {
            if let title = browseCategoryTitle(forKey: countKey) {
                selectedSection = .browse
                roonService.browseToLibraryCategory(title: title)
            }
        } label: {
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
                        .trackingCompat(1)
                        .foregroundStyle(Color.roonSecondary)
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
        }
        .buttonStyle(.plain)
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
                        withAnimation(.easeInOut(duration: 0.2)) {
                            dernierementTab = .lus
                        }
                    }
                    dernierementTabButton("AJOUTÉS", isSelected: dernierementTab == .ajoute) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            dernierementTab = .ajoute
                        }
                    }
                }

                // #1: Nav arrows (functional scroll)
                HStack(spacing: 8) {
                    Button {
                        scrollByStep(forward: false)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(.white.opacity(0.15)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        scrollByStep(forward: true)
                    } label: {
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
                        .trackingCompat(1)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(.white.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)

            // #9: Animated horizontal scroll of album cards
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(activeTiles, id: \.id) { tile in
                            // #4: Click to play
                            Button {
                                playTile(tile)
                            } label: {
                                dernierementCard(tile)
                            }
                            .buttonStyle(.plain)
                            .hoverScale()
                            .id(tile.id)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 4)
                }
                .onChangeCompat(of: scrollTarget) { (newTarget: String?) in
                    guard let target = newTarget else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(target, anchor: .leading)
                    }
                    scrollTarget = nil
                }
            }
            // #9: Animate tab switch
            .animation(.easeInOut(duration: 0.25), value: dernierementTab)
        }
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.roonAccent)
        )
        .padding(.horizontal, pagePadding)
    }

    // #1: Scroll by N cards
    private func scrollByStep(forward: Bool) {
        let tiles = activeTiles
        guard !tiles.isEmpty else { return }

        // Find approximate current visible index based on scrollTarget or default
        let currentIndex: Int
        if let target = scrollTarget, let idx = tiles.firstIndex(where: { $0.id == target }) {
            currentIndex = idx
        } else {
            currentIndex = forward ? 0 : tiles.count - 1
        }

        let nextIndex = forward
            ? min(currentIndex + scrollStep, tiles.count - 1)
            : max(currentIndex - scrollStep, 0)

        scrollTarget = tiles[nextIndex].id
    }

    // #4: Play a tile and navigate to Now Playing
    private func playTile(_ tile: HomeTile) {
        if dernierementTab == .lus {
            // History item: search and play by title/artist
            roonService.searchAndPlay(
                title: tile.title,
                artist: tile.subtitle ?? "",
                album: tile.album ?? ""
            )
        } else {
            // Recently added: browse into the album via item_key
            if let itemKey = tile.itemKey {
                roonService.playRecentlyAddedItem(itemKey: itemKey)
            }
        }
        selectedSection = .nowPlaying
    }

    private func dernierementTabButton(_ title: LocalizedStringKey, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.latoBold(12))
                .trackingCompat(1)
                .foregroundStyle(.white)
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
            if let url = roonService.imageURL(key: tile.imageKey, width: 360, height: 360) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Color.white.opacity(0.1)
                    }
                }
                .id(tile.imageKey ?? "")
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
                imageKey: roonService.resolvedImageKey(title: item.title, imageKey: item.image_key),
                itemKey: nil,
                album: item.album
            )
        }
    }

    private var recentlyAddedTiles: [HomeTile] {
        roonService.recentlyAdded.prefix(20).map { item in
            HomeTile(
                id: item.item_key ?? item.title ?? UUID().uuidString,
                title: item.title ?? "",
                subtitle: item.subtitle,
                imageKey: roonService.resolvedImageKey(title: item.title, imageKey: item.image_key),
                itemKey: item.item_key,
                album: nil
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
    let itemKey: String?  // browse item_key for recently added
    let album: String?    // album name for history playback
}
