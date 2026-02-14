import SwiftUI

struct RoonSidebarView: View {
    @EnvironmentObject var roonService: RoonService
    @Binding var selectedSection: RoonSection
    @State private var activeCategoryKey: String?
    @State private var hoveredSection: RoonSection?
    @State private var hoveredCategoryKey: String?
    @State private var searchText: String = ""

    // Classification des items par titre
    private static let explorerTitles = Set([
        "Genres", "TIDAL", "Qobuz", "KKBOX", "nugs.net",
        "Live Radio", "Écouter plus tard", "Étiquettes", "Tags",
        "Historique", "History"
    ])
    private static let libraryTitles = Set([
        "Albums", "Artistes", "Artists", "Morceaux", "Tracks",
        "Compositeurs", "Composers", "Compositions",
        "Mes Live Radios", "My Live Radio", "Répertoires", "Folders"
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {

                    // MARK: - EXPLORER
                    sectionHeader("EXPLORER")

                    // Accueil (always present)
                    sidebarItem(.home)

                    // Dynamic explorer items
                    ForEach(explorerItems) { item in
                        dynamicSidebarItem(item)
                    }

                    // MARK: - MA BIBLIOTHEQUE MUSICALE
                    sectionHeader("MA BIBLIOTHEQUE MUSICALE")

                    // Dynamic library items
                    ForEach(libraryItems) { item in
                        dynamicSidebarItem(item)
                    }

                    // Fixed items
                    sidebarItem(.queue)
                    sidebarItem(.favorites)

                    // MARK: - LISTES DE LECTURE
                    if !roonService.sidebarPlaylists.isEmpty {
                        sectionHeader("LISTES DE LECTURE")

                        sidebarSearchField

                        ForEach(roonService.sidebarPlaylists) { item in
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
            .foregroundStyle(Color.roonTertiary)
            .tracking(1.5)
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
                    Text(roonService.currentZone?.display_name ?? String(localized: "Aucune zone"))
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
                Image(systemName: iconForTitle(item.title ?? ""))
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
            TextField("Rechercher...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.lato(13))
                .foregroundStyle(Color.roonText)
                .onSubmit {
                    let query = searchText.trimmingCharacters(in: .whitespaces)
                    guard !query.isEmpty else { return }
                    roonService.browseSearch(query: query)
                    activeCategoryKey = nil
                    selectedSection = .browse
                    searchText = ""
                }
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

    private func iconForTitle(_ title: String) -> String {
        switch title {
        case "Genres": return "guitars"
        case "TIDAL": return "waveform"
        case "Qobuz": return "headphones"
        case "KKBOX", "nugs.net": return "waveform"
        case "Live Radio": return "antenna.radiowaves.left.and.right"
        case "Écouter plus tard": return "bookmark"
        case "Étiquettes", "Tags": return "tag"
        case "Historique", "History": return "clock"
        case "Albums": return "opticaldisc"
        case "Artistes", "Artists": return "music.mic"
        case "Morceaux", "Tracks": return "music.note"
        case "Compositeurs", "Composers": return "music.quarternote.3"
        case "Compositions": return "music.note.list"
        case "Mes Live Radios", "My Live Radio": return "radio"
        case "Répertoires", "Folders": return "folder"
        default: return "music.note.list"
        }
    }

    // MARK: - Helpers

    private func stateLabel(_ state: String) -> String {
        switch state {
        case "playing": String(localized: "Lecture en cours")
        case "paused": String(localized: "En pause")
        case "loading": String(localized: "Chargement...")
        default: String(localized: "Arrete")
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
