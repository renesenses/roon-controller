import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var roonService: RoonService
    @AppStorage("uiMode") private var uiMode = "roon"
    @SceneStorage("playerSelectedSection") private var selectedSection: SidebarSection = .zones
    @State private var searchText: String = ""
    @State private var browseListId: UUID = UUID()
    @State private var showSearchPrompt: Bool = false
    @State private var roonSearchText: String = ""
    @State private var searchItemKey: String?

    enum SidebarSection: Hashable, RawRepresentable {
        case zones, browse, queue, history, favorites, myLiveRadios
        case streaming(serviceName: String)

        static let fixedSections: [SidebarSection] = [.zones, .browse, .queue, .history, .favorites, .myLiveRadios]

        init?(rawValue: String) {
            switch rawValue {
            case "zones": self = .zones
            case "browse": self = .browse
            case "queue": self = .queue
            case "history": self = .history
            case "favorites": self = .favorites
            case "myLiveRadios": self = .myLiveRadios
            default:
                if rawValue.hasPrefix("streaming:") {
                    let name = String(rawValue.dropFirst("streaming:".count))
                    self = .streaming(serviceName: name)
                } else {
                    return nil
                }
            }
        }

        var rawValue: String {
            switch self {
            case .zones: "zones"
            case .browse: "browse"
            case .queue: "queue"
            case .history: "history"
            case .favorites: "favorites"
            case .myLiveRadios: "myLiveRadios"
            case .streaming(let name): "streaming:\(name)"
            }
        }

        var label: LocalizedStringKey {
            switch self {
            case .zones: "Zones"
            case .browse: "Bibliotheque"
            case .queue: "File d'attente"
            case .history: "Historique"
            case .favorites: "Favoris"
            case .myLiveRadios: "My Live Radio"
            case .streaming(let name): LocalizedStringKey(name)
            }
        }

        var icon: String {
            switch self {
            case .zones: "hifispeaker.2"
            case .browse: "square.grid.2x2"
            case .queue: "list.number"
            case .history: "clock"
            case .favorites: "heart"
            case .myLiveRadios: "dot.radiowaves.left.and.right"
            case .streaming: "waveform"
            }
        }

        /// Asset image name for services that have a custom icon (nil = use SF Symbol)
        var customIcon: String? {
            switch self {
            case .streaming(let name) where name == "Qobuz": "QobuzIcon"
            case .streaming(let name) where name == "TIDAL": "TidalIcon"
            default: nil
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Mode toggle + Section icon bar
            HStack(spacing: 0) {
                ForEach(SidebarSection.fixedSections, id: \.self) { section in
                    sidebarButton(section)
                }

                if !availableStreamingServices.isEmpty {
                    Divider()
                        .frame(height: 16)
                        .padding(.horizontal, 4)

                    ForEach(availableStreamingServices, id: \.self) { name in
                        sidebarButton(.streaming(serviceName: name))
                    }
                }

                Spacer()

                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.roonSecondary)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.roonGrey2.opacity(0.5))
                        )
                }
                .buttonStyle(.plain)
                .help("Reglages")

                Button {
                    uiMode = "roon"
                } label: {
                    Image(systemName: "rectangle.2.swap")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.roonSecondary)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.roonGrey2.opacity(0.5))
                        )
                }
                .buttonStyle(.plain)
                .help("Mode Roon")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)

            Divider()
                .overlay(Color.roonTertiary.opacity(0.3))

            Group {
                switch selectedSection {
                case .zones:
                    zonesSection
                case .browse:
                    browseSection
                case .queue:
                    QueueView()
                        .environmentObject(roonService)
                case .history:
                    HistoryView()
                        .environmentObject(roonService)
                case .favorites:
                    FavoritesView()
                        .environmentObject(roonService)
                case .myLiveRadios:
                    myLiveRadiosSection
                case .streaming(let serviceName):
                    streamingServiceContent(serviceName: serviceName)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedSection)
        }
        .frame(minWidth: 250)
        .background(Color.roonSidebar)
        .alert("Recherche", isPresented: $showSearchPrompt) {
            TextField("Rechercher...", text: $roonSearchText)
            Button("Rechercher") { submitSearch() }
            Button("Annuler", role: .cancel) {
                roonSearchText = ""
                searchItemKey = nil
            }
        }
    }

    // MARK: - Zones Section

    private var zonesSection: some View {
        List(roonService.zones, selection: Binding(
            get: { roonService.currentZone?.zone_id },
            set: { id in
                if let zone = roonService.zones.first(where: { $0.zone_id == id }) {
                    Task { roonService.selectZone(zone) }
                }
            }
        )) { zone in
            VStack(alignment: .leading, spacing: 6) {
                // Zone header
                HStack {
                    Text(zone.display_name)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.roonText)

                    Spacer()

                    if let state = zone.state {
                        stateIndicator(state)
                    }
                }

                // Mini now playing
                if let np = zone.now_playing {
                    HStack(spacing: 8) {
                        if let url = roonService.imageURL(key: np.image_key, width: 80, height: 80) {
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
                            Text(np.three_line?.line1 ?? np.one_line?.line1 ?? "")
                                .font(.caption)
                                .foregroundStyle(Color.roonText)
                                .lineLimit(1)
                            Text(np.three_line?.line2 ?? "")
                                .font(.caption2)
                                .foregroundStyle(Color.roonSecondary)
                                .lineLimit(1)
                        }
                    }
                }

                // Volume controls per output
                if let outputs = zone.outputs {
                    ForEach(outputs) { output in
                        if let volume = output.volume, let value = volume.value {
                            HStack(spacing: 8) {
                                Button {
                                    roonService.toggleMute(outputId: output.output_id)
                                } label: {
                                    Image(systemName: (volume.is_muted ?? false) ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                        .font(.caption)
                                        .foregroundStyle((volume.is_muted ?? false) ? .red : Color.roonSecondary)
                                }
                                .buttonStyle(.plain)

                                if let min = volume.min, let max = volume.max {
                                    Slider(
                                        value: Binding(
                                            get: { value },
                                            set: { newVal in
                                                roonService.setVolume(outputId: output.output_id, value: newVal)
                                            }
                                        ),
                                        in: min...max,
                                        step: volume.step ?? 1
                                    )
                                    .controlSize(.mini)
                                    .accentColor(Color.roonAccent)
                                }

                                Text("\(Int(value))")
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(Color.roonSecondary)
                                    .frame(width: 30, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .tag(zone.zone_id)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 6)
                    .fill(roonService.currentZone?.zone_id == zone.zone_id
                          ? Color.roonAccent.opacity(0.15)
                          : Color.clear)
                    .padding(.horizontal, 4)
            )
        }
        .listStyle(.sidebar)
        .hideScrollBackground()
    }

    @ViewBuilder
    private func stateIndicator(_ state: String) -> some View {
        switch state {
        case "playing":
            Image(systemName: "play.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case "paused":
            Image(systemName: "pause.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        case "loading":
            ProgressView()
                .controlSize(.mini)
        default:
            Image(systemName: "stop.fill")
                .font(.caption)
                .foregroundStyle(Color.roonTertiary)
        }
    }

    // MARK: - Browse Section

    private var filteredBrowseItems: [BrowseItem] {
        guard let result = roonService.browseResult else { return [] }
        let items = result.items
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if query.isEmpty { return items }
        // Load all remaining items when searching (deferred to avoid publishing during view update)
        if let total = result.list?.count, items.count < total {
            Task { roonService.browseLoad(offset: items.count) }
        }
        return items.filter { item in
            (item.title ?? "").localizedCaseInsensitiveContains(query) ||
            (item.subtitle ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    private var browseSection: some View {
        VStack(spacing: 0) {
            // Navigation bar
            HStack {
                if !roonService.browseStack.isEmpty {
                    Button {
                        searchText = ""
                        browseListId = UUID()
                        roonService.browseBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(Color.roonText)
                    }
                    .buttonStyle(.plain)
                }

                if roonService.browseStack.isEmpty {
                    Text("Bibliotheque")
                        .font(.headline)
                        .foregroundStyle(Color.roonText)
                } else {
                    Text(roonService.browseStack.last ?? "")
                        .font(.headline)
                        .foregroundStyle(Color.roonText)
                        .lineLimit(1)
                }

                if roonService.browseLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 4)
                }

                Spacer()

                if !roonService.browseStack.isEmpty {
                    Button {
                        searchText = ""
                        browseListId = UUID()
                        roonService.browseHome()
                    } label: {
                        Image(systemName: "house")
                            .foregroundStyle(Color.roonText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Search field
            if roonService.browseResult != nil {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.roonTertiary)
                    TextField("Rechercher...", text: $searchText)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Color.roonText)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.roonTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.roonSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.roonTertiary.opacity(0.3), lineWidth: 0.5)
                        )
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }

            Divider()
                .overlay(Color.roonTertiary.opacity(0.3))

            // Browse items
            if roonService.browseResult != nil {
                let items = filteredBrowseItems
                if items.isEmpty && !searchText.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .foregroundStyle(Color.roonTertiary)
                        Text("Aucun resultat pour \"\(searchText)\"")
                            .font(.caption)
                            .foregroundStyle(Color.roonSecondary)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(items) { item in
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
                                        .frame(width: 36, height: 36)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title ?? "")
                                            .foregroundStyle(Color.roonText)
                                            .lineLimit(1)
                                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                                            Text(subtitle)
                                                .font(.caption)
                                                .foregroundStyle(Color.roonSecondary)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()

                                    if (item.hint == "action_list" || item.hint == "action"),
                                       let itemKey = item.item_key {
                                        Image(systemName: "play.circle.fill")
                                            .font(.body)
                                            .foregroundStyle(Color.roonAccent)
                                            .onTapGesture {
                                                roonService.playItem(itemKey: itemKey)
                                            }
                                    }

                                    if item.hint == "list" || item.hint == "action_list" {
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(Color.roonTertiary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    searchText = ""
                                    handleBrowseItemTap(item)
                                }
                                .onAppear {
                                    loadMoreIfNeeded(item: item)
                                }
                            }
                        }
                    }
                    .id(browseListId)
                    .transition(.move(edge: .trailing))
                }
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Button("Parcourir la bibliotheque") {
                        roonService.browse()
                    }
                    .buttonStyle(.bordered)
                    .accentColor(Color.roonAccent)
                    Spacer()
                }
            }
        }
    }

    // MARK: - My Live Radios Section

    private var myLiveRadiosSection: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(Color.roonAccent)
                Text("My Live Radio")
                    .font(.headline)
                    .foregroundStyle(Color.roonText)

                if !roonService.myLiveRadioStations.isEmpty {
                    Text("\(roonService.myLiveRadioStations.count)")
                        .font(.caption2)
                        .foregroundStyle(Color.roonSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.roonSurface))
                }

                Spacer()

                Button {
                    roonService.fetchMyLiveRadioStations()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(Color.roonSecondary)
                }
                .buttonStyle(.plain)
                .help("Recharger")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()
                .overlay(Color.roonTertiary.opacity(0.3))

            if roonService.myLiveRadioStations.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundStyle(Color.roonTertiary)
                    Text("Aucune station")
                        .font(.caption)
                        .foregroundStyle(Color.roonSecondary)
                    Button("Charger les radios") {
                        roonService.fetchMyLiveRadioStations()
                    }
                    .buttonStyle(.bordered)
                    .accentColor(Color.roonAccent)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(roonService.myLiveRadioStations) { station in
                            HStack(spacing: 10) {
                                if let url = roonService.imageURL(key: station.image_key, width: 80, height: 80) {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .success(let img):
                                            img.resizable().aspectRatio(contentMode: .fill)
                                        default:
                                            Color.roonSurface
                                        }
                                    }
                                    .frame(width: 36, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                } else {
                                    Image(systemName: "radio")
                                        .font(.title3)
                                        .foregroundStyle(Color.roonTertiary)
                                        .frame(width: 36, height: 36)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(station.title ?? "")
                                        .foregroundStyle(Color.roonText)
                                        .lineLimit(1)
                                    if let subtitle = station.subtitle, !subtitle.isEmpty {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(Color.roonSecondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                Button {
                                    if let name = station.title {
                                        roonService.playMyLiveRadioStation(stationName: name)
                                    }
                                } label: {
                                    Image(systemName: "play.circle.fill")
                                        .font(.body)
                                        .foregroundStyle(Color.roonAccent)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let name = station.title {
                                    roonService.playMyLiveRadioStation(stationName: name)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            roonService.fetchMyLiveRadioStations()
        }
    }

    private func loadMoreIfNeeded(item: BrowseItem) {
        guard let result = roonService.browseResult,
              let totalCount = result.list?.count else { return }
        let loadedCount = result.items.count
        guard loadedCount < totalCount else { return }
        // Load more when reaching the last 10 items
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

    // MARK: - Streaming service detection

    private static let streamingServiceTitles: Set<String> = ["TIDAL", "Qobuz", "KKBOX", "nugs.net"]

    private var availableStreamingServices: [String] {
        roonService.sidebarCategories.compactMap(\.title).filter {
            Self.streamingServiceTitles.contains($0)
        }
    }

    // MARK: - Open Settings

    private func openSettings() {
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Icon bar button

    private func sidebarButton(_ section: SidebarSection) -> some View {
        Button {
            selectedSection = section
        } label: {
            Group {
                if let custom = section.customIcon {
                    Image(custom)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 13, height: 13)
                } else {
                    Image(systemName: section.icon)
                        .font(.system(size: 13))
                }
            }
            .foregroundStyle(selectedSection == section ? Color.roonAccent : Color.roonSecondary)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(selectedSection == section ? Color.roonAccent.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help(section.label)
    }

    // MARK: - Streaming Service Content

    private func streamingServiceContent(serviceName: String) -> some View {
        let sections = roonService.cachedStreamingSectionsForService(serviceName)
        return Group {
            if sections.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Text("Chargement de \(serviceName)...")
                        .font(.caption)
                        .foregroundStyle(Color.roonSecondary)
                    Spacer()
                }
                .onAppear {
                    roonService.prefetchStreamingServices()
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(sections) { section in
                            streamingSectionView(section: section, serviceName: serviceName)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .id("streaming_\(serviceName)_\(roonService.streamingCacheVersion)")
    }

    private func streamingSectionView(section: StreamingSection, serviceName: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.roonSecondary)
                .textCase(.uppercase)
                .padding(.horizontal, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(section.items) { item in
                        streamingCard(item: item, section: section, serviceName: serviceName)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    private func streamingCard(item: BrowseItem, section: StreamingSection, serviceName: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let url = roonService.imageURL(key: item.image_key, width: 200, height: 200) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Color.roonSurface
                    }
                }
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.roonSurface)
                    .frame(width: 100, height: 100)
            }

            Text(item.title ?? "")
                .font(.caption2)
                .foregroundStyle(Color.roonText)
                .lineLimit(2)
                .frame(width: 100, alignment: .leading)

            if let subtitle = item.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Color.roonSecondary)
                    .lineLimit(1)
                    .frame(width: 100, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedSection = .browse
            roonService.browseToStreamingAlbum(
                serviceName: serviceName,
                albumTitle: item.title ?? "",
                sectionTitles: section.navigationTitles
            )
        }
    }
}
