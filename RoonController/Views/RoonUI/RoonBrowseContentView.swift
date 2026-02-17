import SwiftUI

struct RoonBrowseContentView: View {
    @EnvironmentObject var roonService: RoonService
    var startWithRadio: Bool = false

    @State private var searchText: String = ""
    @State private var browseListId: UUID = UUID()
    @State private var showSearchPrompt: Bool = false
    @State private var roonSearchText: String = ""
    @State private var searchItemKey: String?
    @State private var didInitRadio: Bool = false
    @State private var streamingSections: [BrowseItem] = []
    @State private var activeStreamingTab: Int = 0

    private let gridCardSize: CGFloat = 200

    private static let genreTitles: Set<String> = [
        "Genres", "Generi", "Géneros", "ジャンル", "장르"
    ]
    private static let streamingTitles: Set<String> = ["TIDAL", "Qobuz", "KKBOX", "nugs.net"]
    private static let tracksTitles: Set<String> = [
        "Tracks", "Morceaux", "Titel", "Brani", "Canciones", "Faixas",
        "Spår", "Nummers", "トラック", "트랙"
    ]
    private static let composerTitles: Set<String> = [
        "Composers", "Compositeurs", "Komponisten", "Compositori", "Compositores",
        "Kompositörer", "Componisten", "作曲家", "작곡가"
    ]
    private static let radioTitles: Set<String> = ["My Live Radio", "Mes Live Radios"]

    private var filteredBrowseItems: [BrowseItem] {
        guard let result = roonService.browseResult else { return [] }
        let items = result.items
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if query.isEmpty { return items }
        if let total = result.list?.count, items.count < total {
            Task { roonService.browseLoad(offset: items.count) }
        }
        return items.filter { item in
            (item.title ?? "").localizedCaseInsensitiveContains(query) ||
            (item.subtitle ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    /// Detect playlist/album detail view: most items are tracks (action or action_list)
    /// Excludes the root Tracks category (flat track list without album context)
    private var isPlaylistView: Bool {
        guard roonService.browseResult?.list != nil else { return false }
        if let cat = roonService.browseCategory, Self.tracksTitles.contains(cat),
           roonService.browseStack.count <= 1 { return false }
        if let last = roonService.browseStack.last, Self.radioTitles.contains(last),
           roonService.browseStack.count <= 1 { return false }
        let items = filteredBrowseItems
        guard items.count >= 2 else { return false }
        let sample = items.prefix(20)
        let actionCount = sample.filter { $0.hint == "action" || $0.hint == "action_list" }.count
        return actionCount > sample.count / 2
    }

    /// Genre view: root grid OR genre detail (sub-genres + actions)
    private var isGenreView: Bool {
        guard let cat = roonService.browseCategory, Self.genreTitles.contains(cat) else { return false }
        return roonService.browseStack.count <= 2
    }

    /// Streaming service root (sections list, auto-navigates into first section)
    private var isStreamingServiceRoot: Bool {
        guard let cat = roonService.browseCategory, Self.streamingTitles.contains(cat) else { return false }
        // Only true when tabs haven't been stored yet (auto-nav not yet fired)
        return streamingSections.isEmpty
    }

    /// Inside a streaming service section (tab bar + content)
    private var isInsideStreamingService: Bool {
        guard let cat = roonService.browseCategory, Self.streamingTitles.contains(cat) else { return false }
        return !streamingSections.isEmpty || roonService.streamingAlbumDepth > 0
    }

    /// Root track list: flat list of playable tracks without album header
    private var isTrackListView: Bool {
        guard let cat = roonService.browseCategory, Self.tracksTitles.contains(cat) else { return false }
        guard roonService.browseStack.count <= 1 else { return false }
        let items = filteredBrowseItems
        guard items.count >= 2 else { return false }
        let sample = items.prefix(20)
        let actionCount = sample.filter { $0.hint == "action" || $0.hint == "action_list" }.count
        return actionCount > sample.count / 2
    }

    /// Composer root: list or grid of composers
    private var isComposerView: Bool {
        guard let cat = roonService.browseCategory, Self.composerTitles.contains(cat) else { return false }
        return roonService.browseStack.count <= 1
    }

    /// Radio stations view: grid of saved radio stations
    private var isRadioStationsView: Bool {
        guard let last = roonService.browseStack.last, Self.radioTitles.contains(last) else { return false }
        return roonService.browseStack.count <= 1
    }

    /// Detect artist detail view: first item(s) have no image, followed by navigable items with images
    private var isArtistDetailView: Bool {
        let items = filteredBrowseItems
        guard items.count >= 2,
              items.first?.image_key == nil else { return false }
        let sample = items.prefix(20)
        let listWithImage = sample.filter {
            $0.image_key != nil && ($0.hint == "list" || $0.hint == "action_list")
        }.count
        return listWithImage >= 1
    }

    /// Detect playlist container: items are navigable lists with duration subtitles
    private var isPlaylistListView: Bool {
        let items = filteredBrowseItems
        guard items.count >= 2 else { return false }
        let sample = items.prefix(20)
        let playlistLike = sample.filter { item in
            item.hint == "list" && item.subtitle != nil &&
            (item.subtitle!.contains("morceau") || item.subtitle!.contains("track") ||
             item.subtitle!.contains("minute") || item.subtitle!.contains("heure") ||
             item.subtitle!.contains("hour"))
        }.count
        return playlistLike > sample.count / 2
    }

    /// Show grid when most items have artwork (albums, artists) but not playlist containers
    private var shouldShowGrid: Bool {
        let items = filteredBrowseItems
        guard items.count >= 3 else { return false }
        // If most items are playable actions (tracks), show as list
        let actionCount = items.prefix(20).filter { $0.hint == "action" || $0.hint == "action_list" }.count
        if actionCount > items.prefix(20).count / 2 { return false }
        // Playlist containers use list view, not grid
        if isPlaylistListView { return false }
        let withImage = items.prefix(20).filter { $0.image_key != nil }.count
        return withImage > items.prefix(20).count / 2
    }

    var body: some View {
        VStack(spacing: 0) {
            // Navigation bar (hidden when inside streaming service — tabs replace it)
            if !isInsideStreamingService {
                navBar
            }

            // Streaming service nav bar + tab bar (hide tabs when inside an album)
            if isInsideStreamingService {
                streamingNavBar
                if roonService.streamingAlbumDepth == 0 {
                    streamingTabBar
                }
            }

            // Search field — show for composers, tracks, playlist lists & generic views
            // Hide for artist detail, playlist/album detail, streaming service, and genres
            if roonService.browseResult != nil &&
               !isArtistDetailView && !isPlaylistView && !isStreamingServiceRoot && !isInsideStreamingService && !isGenreView || isPlaylistListView || isTrackListView || isComposerView || isRadioStationsView {
                searchField
            }

            Divider()
                .overlay(Color.roonSeparator.opacity(0.3))

            // Browse items
            if roonService.browseResult != nil {
                let items = filteredBrowseItems
                if items.isEmpty && !searchText.isEmpty {
                    emptySearchState
                } else if isStreamingServiceRoot {
                    streamingServiceAutoNav(items: items)
                } else if isInsideStreamingService && isStreamingTabContent(items: items) {
                    streamingTabSectionsView(items: items)
                } else if isTrackListView {
                    trackListContent(items: items)
                } else if isGenreView {
                    genreContent(items: items)
                } else if isComposerView {
                    composerContent(items: items)
                } else if isRadioStationsView {
                    radioStationsContent(items: items)
                } else if isPlaylistView && searchText.isEmpty {
                    playlistContent(items: items)
                } else if isArtistDetailView && searchText.isEmpty {
                    artistDetailContent(items: items)
                } else if isPlaylistListView {
                    playlistListContent(items: items)
                } else if shouldShowGrid {
                    gridContent(items: items)
                } else {
                    listContent(items: items)
                }
            } else {
                emptyState
            }
        }
        .onAppear {
            if startWithRadio && !didInitRadio && roonService.browseResult == nil && !roonService.browseLoading {
                didInitRadio = true
                roonService.browse(hierarchy: "internet_radio")
            } else if !startWithRadio && roonService.browseResult == nil && !roonService.browseLoading {
                roonService.browse()
            }
        }
        .alert("Search", isPresented: $showSearchPrompt) {
            TextField("Search...", text: $roonSearchText)
            Button("Search") { submitSearch() }
            Button("Cancel", role: .cancel) {
                roonSearchText = ""
                searchItemKey = nil
            }
        }
        .onChangeCompat(of: roonService.browseStack) { (newStack: [String]) in
            if newStack.isEmpty {
                streamingSections = []
                activeStreamingTab = 0
            }
        }
    }

    // MARK: - Navigation Bar

    private var navBar: some View {
        HStack(spacing: 12) {
            if !roonService.browseStack.isEmpty {
                Button {
                    searchText = ""
                    browseListId = UUID()
                    roonService.browseBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.roonText)
                        .padding(6)
                        .background(
                            Circle()
                                .fill(Color.roonGrey2.opacity(0.5))
                        )
                }
                .buttonStyle(.plain)
            }

            Text(roonService.browseStack.isEmpty
                 ? (startWithRadio ? String(localized: "Radio") : String(localized: "Library"))
                 : (roonService.browseStack.last ?? ""))
                .font(.inter(28))
                .trackingCompat(-0.8)
                .foregroundStyle(Color.roonText)
                .lineLimit(1)

            if roonService.browseLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            if !roonService.browseStack.isEmpty {
                Button {
                    searchText = ""
                    streamingSections = []
                    browseListId = UUID()
                    roonService.browseHome()
                } label: {
                    Image(systemName: "house")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.roonSecondary)
                        .padding(6)
                        .background(
                            Circle()
                                .fill(Color.roonGrey2.opacity(0.5))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 52)  // clear the sidebar toggle burger overlay
        .padding(.trailing, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Color.roonTertiary)
            TextField("Search...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.lato(13))
                .foregroundStyle(Color.roonText)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.roonTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.roonGrey2.opacity(0.5))
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
    }

    // MARK: - Grid Content

    private func gridContent(items: [BrowseItem]) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: gridCardSize, maximum: gridCardSize + 40), spacing: 18)],
                spacing: 20
            ) {
                ForEach(items) { item in
                    gridCard(item)
                        .hoverScale()
                        .onAppear { loadMoreIfNeeded(item: item) }
                }
            }
            .padding(24)
        }
        .id(browseListId)
    }

    private func gridCard(_ item: BrowseItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Artwork
            ZStack(alignment: .bottomTrailing) {
                if let url = roonService.imageURL(key: item.image_key, width: 480, height: 480) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Color.roonGrey2
                        }
                    }
                    .frame(width: gridCardSize, height: gridCardSize)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.roonGrey2)
                        .frame(width: gridCardSize, height: gridCardSize)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.roonTertiary)
                        }
                }

                // Play button overlay for playable items
                if (item.hint == "action_list" || item.hint == "action"),
                   let itemKey = item.item_key {
                    Button {
                        roonService.playItem(itemKey: itemKey)
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.roonAccent)
                            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }
            }

            // Title — Roon: font-lato text-2xl
            Text(item.title ?? "")
                .font(.lato(15))
                .foregroundStyle(Color.roonText)
                .lineLimit(2)

            // Subtitle — Roon: font-lato text-xl text-gray-400
            if let subtitle = item.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.lato(13))
                    .foregroundStyle(Color.roonSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: gridCardSize)
        .contentShape(Rectangle())
        .onTapGesture {
            searchText = ""
            handleBrowseItemTap(item)
        }
    }

    // MARK: - List Content

    private func listContent(items: [BrowseItem]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    browseRow(item)
                }
            }
        }
        .id(browseListId)
    }

    // MARK: - Playlist List Content (Roon-style list of playlists)

    private func playlistListContent(items: [BrowseItem]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    playlistListRow(item)
                }
            }
        }
        .id(browseListId)
    }

    private func playlistListRow(_ item: BrowseItem) -> some View {
        HStack(spacing: 16) {
            // Thumbnail (larger, Roon-style)
            if let url = roonService.imageURL(key: item.image_key, width: 240, height: 240) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Color.roonGrey2
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.roonGrey2)
                    .frame(width: 64, height: 64)
                    .overlay {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.roonTertiary)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title ?? "")
                    .font(.lato(15))
                    .foregroundStyle(Color.roonText)
                    .lineLimit(1)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.lato(13))
                        .foregroundStyle(Color.roonSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            searchText = ""
            handleBrowseItemTap(item)
        }
        .hoverHighlight()
        .onAppear {
            loadMoreIfNeeded(item: item)
        }
    }

    // MARK: - Browse Row (list mode)

    private func browseRow(_ item: BrowseItem) -> some View {
        HStack(spacing: 14) {
            if let url = roonService.imageURL(key: item.image_key, width: 160, height: 160) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Color.roonGrey2
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title ?? "")
                    .font(.lato(15))
                    .foregroundStyle(Color.roonText)
                    .lineLimit(1)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.lato(13))
                        .foregroundStyle(Color.roonSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if (item.hint == "action_list" || item.hint == "action"),
               let itemKey = item.item_key {
                Button {
                    roonService.playItem(itemKey: itemKey)
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.roonAccent)
                }
                .buttonStyle(.plain)
            }

            if item.hint == "list" || item.hint == "action_list" {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.roonTertiary)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            searchText = ""
            handleBrowseItemTap(item)
        }
        .hoverHighlight()
        .onAppear {
            loadMoreIfNeeded(item: item)
        }
    }

    // MARK: - Empty States

    private var emptySearchState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(Color.roonTertiary)
            Text("No results for \"\(searchText)\"")
                .font(.lato(13))
                .foregroundStyle(Color.roonSecondary)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: startWithRadio ? "dot.radiowaves.left.and.right" : "square.grid.2x2")
                .font(.system(size: 40))
                .foregroundStyle(Color.roonTertiary)
            Button(startWithRadio ? String(localized: "Browse radios") : String(localized: "Browse library")) {
                if startWithRadio {
                    roonService.browse(hierarchy: "internet_radio")
                } else {
                    roonService.browse()
                }
            }
            .buttonStyle(.bordered)
            .accentColor(Color.roonAccent)
            Spacer()
        }
    }

    // MARK: - Playlist / Album Detail View

    /// Splits "Artist - Album" subtitle into (artist, album). Falls back gracefully.
    private func parseSubtitle(_ subtitle: String?) -> (artist: String, album: String) {
        guard let subtitle = subtitle, !subtitle.isEmpty else { return ("", "") }
        // Roon uses " / " or " - " as artist/album separator depending on context
        for separator in [" / ", " - "] {
            if let range = subtitle.range(of: separator) {
                let artist = String(subtitle[subtitle.startIndex..<range.lowerBound])
                let album = String(subtitle[range.upperBound...])
                return (artist, album)
            }
        }
        return (subtitle, "")
    }

    private func playlistHeader(items: [BrowseItem]) -> some View {
        let list = roonService.browseResult?.list
        // Fallback: use first track's resolved image (cache-aware) if list has no artwork
        let coverKey = list?.image_key ?? items.lazy.compactMap { roonService.resolvedImageKey(title: $0.title, imageKey: $0.image_key) }.first
        return HStack(alignment: .top, spacing: 24) {
            // Large artwork (or placeholder)
            if let url = roonService.imageURL(key: coverKey, width: 480, height: 480) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Color.roonGrey2
                    }
                }
                .frame(width: 180, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.roonGrey2)
                    .frame(width: 180, height: 180)
                    .overlay {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.roonTertiary)
                    }
            }

            VStack(alignment: .leading, spacing: 10) {
                Spacer().frame(height: 8)

                // Title
                Text(list?.title ?? "")
                    .font(.inter(28))
                    .trackingCompat(-0.8)
                    .foregroundStyle(Color.roonText)
                    .lineLimit(2)

                // Artist name (extracted from first track with a subtitle)
                if let firstTrack = items.first(where: { $0.subtitle != nil && !$0.subtitle!.isEmpty }) {
                    let parsed = parseSubtitle(firstTrack.subtitle)
                    if !parsed.artist.isEmpty {
                        Text(parsed.artist)
                            .font(.lato(16))
                            .foregroundStyle(Color.roonSecondary)
                            .lineLimit(1)
                    }
                }

                // Track count
                if let count = list?.count {
                    Text("\(count) tracks")
                        .font(.lato(14))
                        .foregroundStyle(Color.roonSecondary)
                }

                // "Play now" button
                if let firstItem = items.first, let itemKey = firstItem.item_key {
                    Button {
                        roonService.playInCurrentSession(itemKey: itemKey)
                    } label: {
                        Text("Play now")
                            .font(.latoBold(13))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.roonAccent)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }

                Spacer()
            }

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private func trackTableHeader(showAlbumColumn: Bool = true) -> some View {
        HStack(spacing: 0) {
            Text("#")
                .frame(width: 36, alignment: .trailing)
            Spacer().frame(width: 14)
            // thumbnail placeholder
            Spacer().frame(width: 40)
            Spacer().frame(width: 12)
            Text("Track")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Artist")
                .frame(maxWidth: .infinity, alignment: .leading)
            if showAlbumColumn {
                Text("Album")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.latoBold(11))
        .foregroundStyle(Color.roonTertiary)
        .textCase(.uppercase)
        .padding(.horizontal, 28)
        .padding(.vertical, 6)
    }

    private func playlistTrackRow(_ item: BrowseItem, index: Int, showAlbumColumn: Bool = true) -> some View {
        let parsed = parseSubtitle(item.subtitle)
        return HStack(spacing: 0) {
            Text("\(index + 1)")
                .font(.lato(13))
                .foregroundStyle(Color.roonTertiary)
                .frame(width: 36, alignment: .trailing)

            Spacer().frame(width: 14)

            // Thumbnail — use prefetched NSImage if available, else AsyncImage fallback
            let imageKey = roonService.resolvedImageKey(title: item.title, imageKey: item.image_key) ?? roonService.browseResult?.list?.image_key
            if let nsImage = roonService.cachedImage(key: imageKey, width: 120, height: 120) {
                Image(nsImage: nsImage)
                    .resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else if let url = roonService.imageURL(key: imageKey, width: 120, height: 120) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Color.roonGrey2
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.roonGrey2)
                    .frame(width: 40, height: 40)
            }

            Spacer().frame(width: 12)

            // Title
            Text(item.title ?? "")
                .font(.lato(14))
                .foregroundStyle(Color.roonText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Artist
            Text(parsed.artist)
                .font(.lato(13))
                .foregroundStyle(Color.roonSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Album
            if showAlbumColumn {
                Text(parsed.album)
                    .font(.lato(13))
                    .foregroundStyle(Color.roonSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if let itemKey = item.item_key {
                roonService.playInCurrentSession(itemKey: itemKey)
            }
        }
        .hoverHighlight()
        .onAppear {
            loadMoreIfNeeded(item: item)
        }
    }

    private func playlistContent(items: [BrowseItem]) -> some View {
        let tracks = items.filter { $0.hint == "action_list" && $0.subtitle != nil && !$0.subtitle!.isEmpty }
        // Hide album column when all tracks share the same album (album detail view)
        let albums = Set(tracks.map { parseSubtitle($0.subtitle).album })
        let showAlbum = albums.count > 1 || albums.first?.isEmpty == true

        return ScrollView {
            playlistHeader(items: items)

            Divider()
                .overlay(Color.roonSeparator.opacity(0.3))
                .padding(.horizontal, 28)

            trackTableHeader(showAlbumColumn: showAlbum)

            Divider()
                .overlay(Color.roonSeparator.opacity(0.3))
                .padding(.horizontal, 28)

            LazyVStack(spacing: 0) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, item in
                    playlistTrackRow(item, index: index, showAlbumColumn: showAlbum)
                }
            }
        }
        .id(browseListId)
    }

    // MARK: - Artist Detail View

    private func artistHeroHeader(actions: [BrowseItem]) -> some View {
        let list = roonService.browseResult?.list
        return HStack(alignment: .top, spacing: 24) {
            // Artist photo
            if let url = roonService.imageURL(key: list?.image_key, width: 480, height: 480) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Color.roonGrey2
                    }
                }
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 10) {
                Spacer().frame(height: 8)

                // Artist name
                Text(list?.title ?? "")
                    .font(.grifoM(36))
                    .foregroundStyle(Color.roonText)
                    .lineLimit(2)

                // Element count
                if let count = list?.count {
                    Text("\(count) items")
                        .font(.lato(14))
                        .foregroundStyle(Color.roonSecondary)
                }

                // Action buttons
                HStack(spacing: 10) {
                    ForEach(actions) { item in
                        Button {
                            if let itemKey = item.item_key {
                                roonService.playInCurrentSession(itemKey: itemKey)
                            }
                        } label: {
                            Text(item.title ?? "")
                                .font(.latoBold(13))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(Color.roonAccent)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)

                Spacer()
            }

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private func artistDetailContent(items: [BrowseItem]) -> some View {
        let actions = items.filter { $0.image_key == nil }
        let albums = items.filter { $0.image_key != nil }

        return ScrollView {
            artistHeroHeader(actions: actions)

            Divider()
                .overlay(Color.roonSeparator.opacity(0.3))
                .padding(.horizontal, 28)

            // Discography section
            VStack(alignment: .leading, spacing: 16) {
                Text("Discography")
                    .font(.inter(20))
                    .trackingCompat(-0.5)
                    .foregroundStyle(Color.roonText)
                    .padding(.horizontal, 28)
                    .padding(.top, 12)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: gridCardSize, maximum: gridCardSize + 40), spacing: 18)],
                    spacing: 20
                ) {
                    ForEach(albums) { item in
                        gridCard(item)
                            .hoverScale()
                            .onAppear { loadMoreIfNeeded(item: item) }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 24)
        }
        .id(browseListId)
    }

    // MARK: - Genre Content

    private static let genreGradients: [LinearGradient] = [
        LinearGradient(colors: [Color(red: 0.55, green: 0.22, blue: 0.42), Color(red: 0.30, green: 0.10, blue: 0.25)], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(red: 0.20, green: 0.35, blue: 0.55), Color(red: 0.10, green: 0.18, blue: 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(red: 0.45, green: 0.30, blue: 0.18), Color(red: 0.25, green: 0.15, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(red: 0.18, green: 0.42, blue: 0.38), Color(red: 0.08, green: 0.22, blue: 0.20)], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(red: 0.50, green: 0.20, blue: 0.20), Color(red: 0.28, green: 0.10, blue: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [Color(red: 0.25, green: 0.25, blue: 0.50), Color(red: 0.12, green: 0.12, blue: 0.28)], startPoint: .topLeading, endPoint: .bottomTrailing),
    ]

    private func genreGradient(for title: String) -> LinearGradient {
        let hash = abs(title.hashValue)
        return Self.genreGradients[hash % Self.genreGradients.count]
    }

    private func genreContent(items: [BrowseItem]) -> some View {
        let isDetail = roonService.browseStack.count == 2
        // In detail view, separate top actions (Play Genre, Artists, Albums) from sub-genres
        let topActions = isDetail ? items.filter { $0.subtitle == nil || $0.subtitle!.isEmpty } : []
        let subGenres = isDetail ? items.filter { $0.subtitle != nil && !$0.subtitle!.isEmpty } : items

        return ScrollView {
            // Genre detail: header with action buttons
            if isDetail && !topActions.isEmpty {
                HStack(spacing: 10) {
                    ForEach(topActions) { item in
                        if item.hint == "action" || item.hint == "action_list", let itemKey = item.item_key {
                            // Play Genre button
                            Button {
                                roonService.playInCurrentSession(itemKey: itemKey)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 11))
                                    Text(item.title ?? "")
                                        .font(.latoBold(13))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.roonAccent))
                            }
                            .buttonStyle(.plain)
                        } else {
                            // Navigation items (Artists, Albums)
                            Button {
                                searchText = ""
                                handleBrowseItemTap(item)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(item.title ?? "")
                                        .font(.latoBold(13))
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10))
                                }
                                .foregroundStyle(Color.roonText)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(Color.roonGrey2.opacity(0.5))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)],
                spacing: 16
            ) {
                ForEach(subGenres) { item in
                    genreCard(item)
                        .hoverScale()
                        .onAppear { loadMoreIfNeeded(item: item) }
                }
            }
            .padding(24)
        }
        .id(browseListId)
    }

    private func genreCard(_ item: BrowseItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let url = roonService.imageURL(key: item.image_key, width: 480, height: 480) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    default:
                        genreGradient(for: item.title ?? "")
                    }
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                )
            } else {
                genreGradient(for: item.title ?? "")
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Text(item.title ?? "")
                .font(.grifoM(18))
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(12)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            searchText = ""
            handleBrowseItemTap(item)
        }
    }

    // MARK: - Streaming Service Content (TIDAL, Qobuz, etc.)

    /// Auto-navigate into first section when streaming root is loaded
    private func streamingServiceAutoNav(items: [BrowseItem]) -> some View {
        Color.clear
            .onAppear {
                streamingSections = items
                activeStreamingTab = 0
                if let first = items.first {
                    browseListId = UUID()
                    handleBrowseItemTap(first)
                }
            }
    }

    /// Nav bar for streaming service (replaces standard navBar)
    private var streamingNavBar: some View {
        HStack(spacing: 12) {
            Button {
                searchText = ""
                browseListId = UUID()
                if roonService.streamingAlbumDepth > 0 {
                    // Pop back to tab content level, restore carousel view
                    roonService.browseBackFromStreamingAlbum()
                } else {
                    streamingSections = []
                    roonService.browseHome()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.roonText)
                    .padding(6)
                    .background(
                        Circle()
                            .fill(Color.roonGrey2.opacity(0.5))
                    )
            }
            .buttonStyle(.plain)

            Text(roonService.browseCategory ?? "")
                .font(.inter(28))
                .trackingCompat(-0.8)
                .foregroundStyle(Color.roonText)
                .lineLimit(1)

            if roonService.browseLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            Button {
                searchText = ""
                streamingSections = []
                browseListId = UUID()
                roonService.browseHome()
            } label: {
                Image(systemName: "house")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.roonSecondary)
                    .padding(6)
                    .background(
                        Circle()
                            .fill(Color.roonGrey2.opacity(0.5))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 52)
        .padding(.trailing, 24)
        .padding(.vertical, 14)
    }

    /// Tab bar matching Roon native style
    private var streamingTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(streamingSections.enumerated()), id: \.element.id) { index, section in
                    Button {
                        switchStreamingTab(to: index)
                    } label: {
                        Text((section.title ?? "").uppercased())
                            .font(.latoBold(11))
                            .trackingCompat(0.5)
                            .foregroundStyle(index == activeStreamingTab ? Color.roonAccent : Color.roonSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) {
                                if index == activeStreamingTab {
                                    Rectangle()
                                        .fill(Color.roonAccent)
                                        .frame(height: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 28)
        }
    }

    private func switchStreamingTab(to index: Int) {
        guard index != activeStreamingTab,
              index < streamingSections.count,
              let itemKey = streamingSections[index].item_key else { return }
        let title = streamingSections[index].title ?? ""
        activeStreamingTab = index
        roonService.prepareStreamingTabSwitch(tabTitle: title)
        browseListId = UUID()
        roonService.browseSwitchSibling(itemKey: itemKey, title: title)
    }

    /// Detect if streaming tab content is a list of navigable sub-sections (not actual content)
    private func isStreamingTabContent(items: [BrowseItem]) -> Bool {
        guard items.count >= 2 else { return false }
        let sample = items.prefix(10)
        let listCount = sample.filter { $0.hint == "list" }.count
        return listCount > sample.count / 2
    }

    /// Rich sectioned view: pre-fetch each sub-section and show inline with carousels
    private func streamingTabSectionsView(items: [BrowseItem]) -> some View {
        let sections = roonService.streamingSections
        return ScrollView {
            if sections.isEmpty {
                // Loading state — trigger fetch
                VStack(spacing: 16) {
                    Spacer().frame(height: 40)
                    ProgressView()
                        .controlSize(.regular)
                    Text("Loading sections...")
                        .font(.lato(13))
                        .foregroundStyle(Color.roonSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .onAppear {
                    roonService.fetchStreamingSections(items: items)
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(sections) { section in
                        streamingSectionRow(section)
                    }
                }
                .padding(.vertical, 16)
            }
        }
        .id(browseListId)
    }

    private func streamingSectionRow(_ section: StreamingSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text(section.title)
                    .font(.inter(20))
                    .trackingCompat(-0.5)
                    .foregroundStyle(Color.roonText)
                Spacer()
            }
            .padding(.horizontal, 28)

            // Horizontal carousel of items
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(section.items) { item in
                        streamingCarouselCard(item, sectionTitles: section.navigationTitles)
                    }
                }
                .padding(.horizontal, 28)
            }
        }
    }

    private func streamingCarouselCard(_ item: BrowseItem, sectionTitles: [String]) -> some View {
        let cardWidth: CGFloat = 180
        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                if let url = roonService.imageURL(key: item.image_key, width: 360, height: 360) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Color.roonGrey2
                        }
                    }
                    .frame(width: cardWidth, height: cardWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.roonGrey2)
                        .frame(width: cardWidth, height: cardWidth)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.roonTertiary)
                        }
                }

                if (item.hint == "action_list" || item.hint == "action"),
                   let itemKey = item.item_key {
                    Button {
                        roonService.playItem(itemKey: itemKey)
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.roonAccent)
                            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }
            }

            Text(item.title ?? "")
                .font(.lato(13))
                .foregroundStyle(Color.roonText)
                .lineLimit(2)

            if let subtitle = item.subtitle, !subtitle.isEmpty {
                Text(cleanRoonMarkup(subtitle))
                    .font(.lato(11))
                    .foregroundStyle(Color.roonSecondary)
                    .lineLimit(2)
            }
        }
        .frame(width: cardWidth)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let albumTitle = item.title else { return }
            searchText = ""
            // Keep streamingSections cached for instant back navigation
            browseListId = UUID()
            roonService.browseStreamingItem(
                albumTitle: albumTitle,
                sectionTitles: sectionTitles
            )
        }
    }

    // MARK: - Radio Stations Grid

    private func radioStationsContent(items: [BrowseItem]) -> some View {
        ScrollView {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.roonAccent)
                if let count = roonService.browseResult?.list?.count {
                    Text("\(count) stations")
                        .font(.lato(14))
                        .foregroundStyle(Color.roonSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 8)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 18)],
                spacing: 20
            ) {
                ForEach(items) { item in
                    radioStationCard(item)
                        .hoverScale()
                        .onAppear { loadMoreIfNeeded(item: item) }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .id(browseListId)
    }

    private func radioStationCard(_ item: BrowseItem) -> some View {
        let cardSize: CGFloat = 180
        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                if let url = roonService.imageURL(key: item.image_key, width: 480, height: 480) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Color.roonGrey2
                        }
                    }
                    .frame(width: cardSize, height: cardSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.roonGrey2)
                        .frame(width: cardSize, height: cardSize)
                        .overlay {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.system(size: 28))
                                .foregroundStyle(Color.roonTertiary)
                        }
                }

                if let title = item.title {
                    Button {
                        roonService.playMyLiveRadioStation(stationName: title)
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.roonAccent)
                            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }
            }

            Text(item.title ?? "")
                .font(.lato(15))
                .foregroundStyle(Color.roonText)
                .lineLimit(2)

            if let subtitle = item.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.lato(13))
                    .foregroundStyle(Color.roonSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: cardSize)
        .contentShape(Rectangle())
        .onTapGesture {
            if let title = item.title {
                roonService.playMyLiveRadioStation(stationName: title)
            }
        }
    }

    // MARK: - Track List Content (flat track list without album header)

    private func trackListContent(items: [BrowseItem]) -> some View {
        ScrollView {
            // Lightweight header
            HStack(spacing: 10) {
                Image(systemName: "music.note")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.roonAccent)
                if let count = roonService.browseResult?.list?.count {
                    Text("\(count) tracks")
                        .font(.lato(14))
                        .foregroundStyle(Color.roonSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 4)

            trackTableHeader()

            Divider()
                .overlay(Color.roonSeparator.opacity(0.3))
                .padding(.horizontal, 28)

            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    playlistTrackRow(item, index: index, showAlbumColumn: true)
                        .onAppear { prefetchCovers(items: items, from: index, ahead: 100) }
                }
            }
        }
        .id(browseListId)
        .onAppear { prefetchCovers(items: items, from: -1, ahead: 100) }
    }

    /// Prefetch cover images into memory for upcoming rows so they render instantly.
    private func prefetchCovers(items: [BrowseItem], from index: Int, ahead: Int) {
        let start = index + 1
        let end = min(items.count, index + ahead)
        guard start < end else { return }
        let keys: [String?] = (start..<end).map { i in
            roonService.resolvedImageKey(title: items[i].title, imageKey: items[i].image_key)
                ?? roonService.browseResult?.list?.image_key
        }
        roonService.prefetchImages(keys: keys, width: 120, height: 120)
    }

    // MARK: - Composer Content

    private let composerCircleSize: CGFloat = 160

    private func composerContent(items: [BrowseItem]) -> some View {
        let list = roonService.browseResult?.list

        return ScrollView {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "music.quarternote.3")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.roonAccent)
                if let count = list?.count {
                    Text("\(count) composers")
                        .font(.lato(14))
                        .foregroundStyle(Color.roonSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 8)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: composerCircleSize, maximum: composerCircleSize + 30), spacing: 20)],
                spacing: 24
            ) {
                ForEach(items) { item in
                    composerGridCard(item)
                        .hoverScale()
                        .onAppear { loadMoreIfNeeded(item: item) }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .id(browseListId)
    }

    private func composerGridCard(_ item: BrowseItem) -> some View {
        VStack(spacing: 8) {
            if let url = roonService.imageURL(key: item.image_key, width: 320, height: 320) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    default:
                        composerInitialsCircle(name: item.title ?? "")
                    }
                }
                .frame(width: composerCircleSize, height: composerCircleSize)
                .clipShape(Circle())
            } else {
                composerInitialsCircle(name: item.title ?? "")
            }

            Text(item.title ?? "")
                .font(.lato(14))
                .foregroundStyle(Color.roonText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: composerCircleSize)
        .contentShape(Rectangle())
        .onTapGesture {
            searchText = ""
            handleBrowseItemTap(item)
        }
    }

    /// Circle with initials for composers without photos (like Roon's "FA", "DA")
    private func composerInitialsCircle(name: String) -> some View {
        let initials = composerInitials(name)
        return Circle()
            .fill(Color.roonGrey2)
            .frame(width: composerCircleSize, height: composerCircleSize)
            .overlay {
                Text(initials)
                    .font(.system(size: composerCircleSize * 0.3, weight: .light))
                    .foregroundStyle(Color.roonTertiary)
            }
    }

    /// Extract initials from a name: "Fabrice Aboulker" → "FA", "Ad-Rock" → "AR"
    private func composerInitials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" })
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        } else if let first = words.first {
            return String(first.prefix(2)).uppercased()
        }
        return ""
    }

    // MARK: - Helpers

    /// Strip Roon markup like `[[12345|Artist Name]]` → `Artist Name`
    private func cleanRoonMarkup(_ text: String) -> String {
        text.replacingOccurrences(of: "\\[\\[(\\d+\\|)?([^\\]]+)\\]\\]", with: "$2", options: .regularExpression)
    }

    private func loadMoreIfNeeded(item: BrowseItem) {
        guard let result = roonService.browseResult,
              let totalCount = result.list?.count else { return }
        let loadedCount = result.items.count
        guard loadedCount < totalCount else { return }
        let thresholdIndex = max(0, loadedCount - 10)
        if let index = result.items.firstIndex(where: { $0.id == item.id }),
           index >= thresholdIndex {
            roonService.browseLoad(offset: loadedCount)
        }
    }

    private func handleBrowseItemTap(_ item: BrowseItem) {
        guard let itemKey = item.item_key else { return }
        if item.input_prompt != nil {
            searchItemKey = itemKey
            roonSearchText = ""
            showSearchPrompt = true
        } else {
            browseListId = UUID()
            roonService.browse(itemKey: itemKey)
        }
    }

    private func submitSearch() {
        guard let itemKey = searchItemKey,
              !roonSearchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        browseListId = UUID()
        roonService.browse(itemKey: itemKey, input: roonSearchText)
        roonSearchText = ""
        searchItemKey = nil
    }

}
