import SwiftUI

struct RoonSidebarView: View {
    @EnvironmentObject var roonService: RoonService
    @Binding var selectedSection: RoonSection
    @State private var activeCategoryKey: String?
    @State private var hoveredSection: RoonSection?
    @State private var hoveredCategoryKey: String?
    @AppStorage("sidebar_playlist_count") private var sidebarPlaylistCount = 10
    @AppStorage("uiMode") private var uiMode = "roon"
    @State private var searchText: String = ""

    // Classification des items par titre
    private static let explorerTitles = Set([
        "TIDAL", "Qobuz", "KKBOX", "nugs.net",
        "Live Radio", "Mes Live Radios", "My Live Radio",
        "Écouter plus tard", "Étiquettes", "Tags",
        "Historique", "History", "Verlauf", "Cronologia", "Historial", "履歴", "기록"
    ])
    private static let libraryTitles = Set([
        "Genres", "Generi", "Géneros", "ジャンル", "장르",
        "Albums", "Alben", "アルバム", "앨범",
        "Artistes", "Artists", "Künstler", "Artisti", "Artistas", "アーティスト", "아티스트",
        "Morceaux", "Tracks", "Titel", "Brani", "Canciones", "Faixas", "Spår", "Nummers", "トラック", "트랙",
        "Compositeurs", "Composers", "Komponisten", "Compositori", "Compositores", "Kompositörer", "Componisten", "作曲家", "작곡가",
        "Compositions", "Kompositionen", "Composizioni", "Composiciones",
        "Répertoires", "Folders", "Ordner", "Cartelle", "Carpetas", "フォルダ", "폴더"
    ])

    private var explorerItems: [BrowseItem] {
        roonService.sidebarCategories.filter {
            let title = $0.title ?? ""
            return Self.explorerTitles.contains(title)
                || !Self.libraryTitles.contains(title)
        }
    }

    private var libraryItems: [BrowseItem] {
        roonService.sidebarCategories.filter {
            Self.libraryTitles.contains($0.title ?? "")
        }
    }

    private var filteredPlaylists: [BrowseItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            if sidebarPlaylistCount == 0 { return roonService.sidebarPlaylists }
            return Array(roonService.sidebarPlaylists.prefix(sidebarPlaylistCount))
        }
        return roonService.sidebarPlaylists.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {

                    // MARK: - EXPLORER
                    HStack {
                        sectionHeader("BROWSE")
                        Spacer()

                        Group {
                            if #available(macOS 14, *) {
                                SettingsLink {
                                    Image(systemName: "gearshape")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.roonSecondary)
                                        .padding(5)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color.roonGrey2.opacity(0.5))
                                        )
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button {
                                    openSettingsLegacy()
                                } label: {
                                    Image(systemName: "gearshape")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.roonSecondary)
                                        .padding(5)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color.roonGrey2.opacity(0.5))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .help("Settings")

                        Button {
                            uiMode = "player"
                        } label: {
                            Image(systemName: "rectangle.2.swap")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.roonSecondary)
                                .padding(5)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.roonGrey2.opacity(0.5))
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Mode Player")
                        .padding(.trailing, 12)
                    }

                    // Accueil (always present)
                    sidebarItem(.home)

                    // Dynamic explorer items
                    ForEach(explorerItems) { item in
                        dynamicSidebarItem(item)
                    }

                    // MARK: - MA BIBLIOTHEQUE MUSICALE
                    sectionHeader("MY MUSIC LIBRARY")

                    // Dynamic library items
                    ForEach(libraryItems) { item in
                        dynamicSidebarItem(item)
                    }

                    // Fixed items
                    sidebarItem(.queue)
                    sidebarItem(.radioFavorites)

                    // MARK: - LISTES DE LECTURE
                    if !roonService.sidebarPlaylists.isEmpty {
                        sectionHeader("PLAYLISTS")

                        sidebarSearchField

                        ForEach(filteredPlaylists) { item in
                            playlistSidebarItem(item)
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 220)
        .background(Color.roonSidebar)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.inter(10))
            .trackingCompat(1.5)
            .foregroundStyle(Color.roonTertiary)
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 6)
    }

    // MARK: - Zone Selector

    private var zoneSelector: some View {
        Menu {
            ForEach(roonService.zones) { zone in
                Button {
                    roonService.selectZone(zone)
                } label: {
                    HStack {
                        Text(zone.display_name)
                        if zone.zone_id == roonService.currentZone?.zone_id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                // Zone icon (matching Roon's atom_zone_icon)
                Image(systemName: "hifispeaker.2")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.roonAccent)

                VStack(alignment: .leading, spacing: 1) {
                    Text(roonService.currentZone?.display_name ?? String(localized: "No zone"))
                        .font(.latoBold(13))
                        .foregroundStyle(Color.roonText)
                        .lineLimit(1)
                    if let state = roonService.currentZone?.state {
                        Text(stateLabel(state))
                            .font(.lato(10))
                            .foregroundStyle(stateColor(state))
                    }
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.roonTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.roonGrey2.opacity(0.5))
            )
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Sidebar Item (fixed sections)

    private func sidebarItem(_ section: RoonSection) -> some View {
        let isSelected = selectedSection == section && activeCategoryKey == nil
        let isHovered = hoveredSection == section
        return Button {
            activeCategoryKey = nil
            selectedSection = section
        } label: {
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(.system(size: 15))
                    .frame(width: 22)
                    .foregroundStyle(isSelected ? Color.roonText : Color.roonSecondary)

                Text(section.label)
                    .font(.lato(13))
                    .foregroundStyle(isSelected ? Color.roonText : Color.roonSecondary)

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .background(
                isSelected
                    ? Color.roonGrey2.opacity(0.6)
                    : (isHovered ? Color.roonGrey2.opacity(0.3) : Color.clear)
            )
            .animation(.easeOut(duration: 0.15), value: selectedSection)
            .animation(.easeOut(duration: 0.15), value: activeCategoryKey)
            .animation(.easeOut(duration: 0.12), value: hoveredSection)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredSection = hovering ? section : nil
        }
    }

    // MARK: - Dynamic Sidebar Item (browse categories)

    private func dynamicSidebarItem(_ item: BrowseItem) -> some View {
        let isSelected = activeCategoryKey == item.item_key && selectedSection == .browse
        let isHovered = hoveredCategoryKey == item.item_key
        return Button {
            activeCategoryKey = item.item_key
            selectedSection = .browse
            if let title = item.title {
                roonService.browseToCategory(title: title)
            }
        } label: {
            HStack(spacing: 12) {
                if let custom = customIconForTitle(item.title ?? "") {
                    Image(custom)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 15, height: 15)
                        .frame(width: 22)
                        .foregroundStyle(isSelected ? Color.roonText : Color.roonSecondary)
                } else {
                    Image(systemName: iconForTitle(item.title ?? ""))
                        .font(.system(size: 15))
                        .frame(width: 22)
                        .foregroundStyle(isSelected ? Color.roonText : Color.roonSecondary)
                }

                Text(displayTitle(item.title ?? ""))
                    .font(.lato(13))
                    .foregroundStyle(isSelected ? Color.roonText : Color.roonSecondary)

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .background(
                isSelected
                    ? Color.roonGrey2.opacity(0.6)
                    : (isHovered ? Color.roonGrey2.opacity(0.3) : Color.clear)
            )
            .animation(.easeOut(duration: 0.15), value: activeCategoryKey)
            .animation(.easeOut(duration: 0.12), value: hoveredCategoryKey)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredCategoryKey = hovering ? item.item_key : nil
        }
    }

    // MARK: - Playlist Sidebar Item (browse into playlist)

    private func playlistSidebarItem(_ item: BrowseItem) -> some View {
        let isSelected = activeCategoryKey == item.item_key && selectedSection == .browse
        let isHovered = hoveredCategoryKey == item.item_key
        return Button {
            activeCategoryKey = item.item_key
            selectedSection = .browse
            if let title = item.title {
                roonService.browsePlaylist(title: title)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 15))
                    .frame(width: 22)
                    .foregroundStyle(isSelected ? Color.roonText : Color.roonSecondary)

                Text(item.title ?? "")
                    .font(.lato(13))
                    .foregroundStyle(isSelected ? Color.roonText : Color.roonSecondary)

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .background(
                isSelected
                    ? Color.roonGrey2.opacity(0.6)
                    : (isHovered ? Color.roonGrey2.opacity(0.3) : Color.clear)
            )
            .animation(.easeOut(duration: 0.15), value: activeCategoryKey)
            .animation(.easeOut(duration: 0.12), value: hoveredCategoryKey)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredCategoryKey = hovering ? item.item_key : nil
        }
    }

    // MARK: - Sidebar Search

    private var sidebarSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Color.roonSecondary)
            TextField("Filter...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.lato(13))
                .foregroundStyle(Color.roonText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.roonPanel)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.roonSeparator, lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    // MARK: - Icon Mapping

    private static let genreNames: Set<String> = ["Genres", "Generi", "Géneros", "ジャンル", "장르"]
    private static let streamingNames: Set<String> = ["TIDAL", "Qobuz", "KKBOX", "nugs.net"]
    private static let trackNames: Set<String> = ["Tracks", "Morceaux", "Titel", "Brani", "Canciones", "Faixas", "Spår", "Nummers", "トラック", "트랙"]
    private static let composerNames: Set<String> = ["Composers", "Compositeurs", "Komponisten", "Compositori", "Compositores", "Kompositörer", "Componisten", "作曲家", "작곡가"]
    private static let artistNames: Set<String> = ["Artists", "Artistes", "Künstler", "Artisti", "Artistas", "アーティスト", "아티스트"]
    private static let albumNames: Set<String> = ["Albums", "Alben", "アルバム", "앨범"]
    private static let folderNames: Set<String> = ["Folders", "Répertoires", "Ordner", "Cartelle", "Carpetas", "フォルダ", "폴더"]
    private static let historyNames: Set<String> = ["Historique", "History", "Verlauf", "Cronologia", "Historial", "履歴", "기록"]

    private func iconForTitle(_ title: String) -> String {
        if Self.genreNames.contains(title) { return "guitars" }
        if Self.streamingNames.contains(title) { return "waveform" }
        if Self.albumNames.contains(title) { return "opticaldisc" }
        if Self.artistNames.contains(title) { return "music.mic" }
        if Self.trackNames.contains(title) { return "music.note" }
        if Self.composerNames.contains(title) { return "music.quarternote.3" }
        if Self.folderNames.contains(title) { return "folder" }
        if Self.historyNames.contains(title) { return "clock" }
        if title.contains("Composition") || title.contains("Komposition") || title.contains("Composizion") { return "music.note.list" }
        if title.contains("Radio") { return "antenna.radiowaves.left.and.right" }
        if title.contains("plus tard") { return "bookmark" }
        if title.contains("tiquette") || title == "Tags" { return "tag" }
        return "music.note.list"
    }

    /// Display name override for API titles that need translation.
    /// Roon Core may send English titles even when macOS is in another language.
    private func displayTitle(_ title: String) -> String {
        switch title {
        case "My Live Radio", "Mes Live Radios": return String(localized: "My Live Radio")
        case "Tags": return String(localized: "Tags")
        case "Artists": return String(localized: "Artists")
        case "Tracks": return String(localized: "Tracks")
        case "Composers": return String(localized: "Composers")
        default: return title
        }
    }

    /// Asset image name for services with a custom icon (nil = use SF Symbol)
    private func customIconForTitle(_ title: String) -> String? {
        switch title {
        case "Qobuz": return "QobuzIcon"
        case "TIDAL": return "TidalIcon"
        default: return nil
        }
    }

    // MARK: - Open Settings

    private func openSettingsLegacy() {
        var opened = false
        if #available(macOS 14, *) {
            opened = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            opened = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        if !opened {
            // Fallback: open via menu bar item (Cmd+,)
            if let appMenu = NSApp.mainMenu?.items.first?.submenu,
               let settingsItem = appMenu.items.first(where: { $0.keyEquivalent == "," }) {
                settingsItem.target?.perform(settingsItem.action, with: settingsItem)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Helpers

    private func stateLabel(_ state: String) -> String {
        switch state {
        case "playing": String(localized: "Playing")
        case "paused": String(localized: "Paused")
        case "loading": String(localized: "Loading...")
        default: String(localized: "Stopped")
        }
    }

    private func stateColor(_ state: String) -> Color {
        switch state {
        case "playing": Color.roonGreen
        case "paused": Color.roonOrange
        default: Color.roonTertiary
        }
    }
}
