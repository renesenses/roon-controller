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

    private let gridCardSize: CGFloat = 200

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

    /// Detect playlist/album detail view: list has artwork and most items are tracks
    private var isPlaylistView: Bool {
        guard let list = roonService.browseResult?.list,
              list.image_key != nil else { return false }
        let items = filteredBrowseItems
        guard items.count >= 2 else { return false }
        let sample = items.prefix(20)
        let actionCount = sample.filter { $0.hint == "action" || $0.hint == "action_list" }.count
        return actionCount > sample.count / 2
    }

    /// Show grid when most items have artwork (albums, artists, playlists)
    private var shouldShowGrid: Bool {
        let items = filteredBrowseItems
        guard items.count >= 3 else { return false }
        // If most items are playable actions (tracks), show as list
        let actionCount = items.prefix(20).filter { $0.hint == "action" || $0.hint == "action_list" }.count
        if actionCount > items.prefix(20).count / 2 { return false }
        let withImage = items.prefix(20).filter { $0.image_key != nil }.count
        return withImage > items.prefix(20).count / 2
    }

    var body: some View {
        VStack(spacing: 0) {
            // Navigation bar
            navBar

            // Search field
            if roonService.browseResult != nil {
                searchField
            }

            Divider()
                .overlay(Color.roonSeparator.opacity(0.3))

            // Browse items
            if roonService.browseResult != nil {
                let items = filteredBrowseItems
                if items.isEmpty && !searchText.isEmpty {
                    emptySearchState
                } else if isPlaylistView && searchText.isEmpty {
                    playlistContent(items: items)
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
            if startWithRadio && !didInitRadio && roonService.browseResult == nil {
                didInitRadio = true
                roonService.browse(hierarchy: "internet_radio")
            }
        }
        .alert("Recherche", isPresented: $showSearchPrompt) {
            TextField("Rechercher...", text: $roonSearchText)
            Button("Rechercher") { submitSearch() }
            Button("Annuler", role: .cancel) {
                roonSearchText = ""
                searchItemKey = nil
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
                 ? (startWithRadio ? String(localized: "Radio") : String(localized: "Bibliotheque"))
                 : (roonService.browseStack.last ?? ""))
                .font(.inter(28))
                .foregroundStyle(Color.roonText)
                .tracking(-0.8)
                .lineLimit(1)

            if roonService.browseLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            if !roonService.browseStack.isEmpty {
                Button {
                    searchText = ""
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
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Color.roonTertiary)
            TextField("Rechercher...", text: $searchText)
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
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.roonAccent)
                    .onTapGesture {
                        roonService.playItem(itemKey: itemKey)
                    }
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
            Text("Aucun resultat pour \"\(searchText)\"")
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
            Button(startWithRadio ? String(localized: "Parcourir les radios") : String(localized: "Parcourir la bibliotheque")) {
                if startWithRadio {
                    roonService.browse(hierarchy: "internet_radio")
                } else {
                    roonService.browse()
                }
            }
            .buttonStyle(.bordered)
            .tint(Color.roonAccent)
            Spacer()
        }
    }

    // MARK: - Playlist / Album Detail View

    /// Splits "Artist - Album" subtitle into (artist, album). Falls back gracefully.
    private func parseSubtitle(_ subtitle: String?) -> (artist: String, album: String) {
        guard let subtitle = subtitle, !subtitle.isEmpty else { return ("", "") }
        if let range = subtitle.range(of: " - ") {
            let artist = String(subtitle[subtitle.startIndex..<range.lowerBound])
            let album = String(subtitle[range.upperBound...])
            return (artist, album)
        }
        return (subtitle, "")
    }

    private func playlistHeader(items: [BrowseItem]) -> some View {
        let list = roonService.browseResult?.list
        return HStack(alignment: .top, spacing: 24) {
            // Large artwork
            if let url = roonService.imageURL(key: list?.image_key, width: 480, height: 480) {
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
            }

            VStack(alignment: .leading, spacing: 10) {
                Spacer().frame(height: 8)

                // Title
                Text(list?.title ?? "")
                    .font(.inter(28))
                    .foregroundStyle(Color.roonText)
                    .tracking(-0.8)
                    .lineLimit(2)

                // Track count
                if let count = list?.count {
                    Text("\(count) morceaux")
                        .font(.lato(14))
                        .foregroundStyle(Color.roonSecondary)
                }

                // "Lire maintenant" button
                if let firstItem = items.first, let itemKey = firstItem.item_key {
                    Button {
                        roonService.playInCurrentSession(itemKey: itemKey)
                    } label: {
                        Text("Lire maintenant")
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

    private var trackTableHeader: some View {
        HStack(spacing: 0) {
            Text("#")
                .frame(width: 36, alignment: .trailing)
            Spacer().frame(width: 14)
            // thumbnail placeholder
            Spacer().frame(width: 40)
            Spacer().frame(width: 12)
            Text("Morceau")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Artiste")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Album")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.latoBold(11))
        .foregroundStyle(Color.roonTertiary)
        .textCase(.uppercase)
        .padding(.horizontal, 28)
        .padding(.vertical, 6)
    }

    private func playlistTrackRow(_ item: BrowseItem, index: Int) -> some View {
        let parsed = parseSubtitle(item.subtitle)
        return HStack(spacing: 0) {
            Text("\(index + 1)")
                .font(.lato(13))
                .foregroundStyle(Color.roonTertiary)
                .frame(width: 36, alignment: .trailing)

            Spacer().frame(width: 14)

            // Thumbnail — fall back to cache then playlist artwork if track has no image
            let imageKey = roonService.resolvedImageKey(title: item.title, imageKey: item.image_key) ?? roonService.browseResult?.list?.image_key
            if let url = roonService.imageURL(key: imageKey, width: 120, height: 120) {
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
            Text(parsed.album)
                .font(.lato(13))
                .foregroundStyle(Color.roonSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
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
        ScrollView {
            playlistHeader(items: items)

            Divider()
                .overlay(Color.roonSeparator.opacity(0.3))
                .padding(.horizontal, 28)

            trackTableHeader

            Divider()
                .overlay(Color.roonSeparator.opacity(0.3))
                .padding(.horizontal, 28)

            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    playlistTrackRow(item, index: index)
                }
            }
        }
        .id(browseListId)
    }

    // MARK: - Helpers

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
