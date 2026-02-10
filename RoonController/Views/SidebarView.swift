import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var roonService: RoonService
    @State private var selectedSection: SidebarSection = .zones
    @State private var searchText: String = ""
    @State private var browseListId: UUID = UUID()
    @State private var showSearchPrompt: Bool = false
    @State private var roonSearchText: String = ""
    @State private var searchItemKey: String?

    enum SidebarSection: String, CaseIterable {
        case zones = "Zones"
        case browse = "Bibliotheque"
        case queue = "File d'attente"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Section Picker
            Picker("Section", selection: $selectedSection) {
                ForEach(SidebarSection.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(12)

            Divider()
                .overlay(Color.roonTertiary.opacity(0.3))

            switch selectedSection {
            case .zones:
                zonesSection
            case .browse:
                browseSection
            case .queue:
                QueueView()
                    .environmentObject(roonService)
            }
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
                    roonService.selectZone(zone)
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
                                    .tint(Color.roonAccent)
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
        .scrollContentBackground(.hidden)
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
        guard let items = roonService.browseResult?.items else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if query.isEmpty { return items }
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
                                Button {
                                    searchText = ""
                                    handleBrowseItemTap(item)
                                } label: {
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

                                        if item.hint == "list" || item.hint == "action_list" {
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundStyle(Color.roonTertiary)
                                        } else if item.hint == "action" {
                                            Image(systemName: "play.circle")
                                                .font(.caption)
                                                .foregroundStyle(Color.roonSecondary)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .onAppear {
                                    loadMoreIfNeeded(item: item)
                                }
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Button("Parcourir la bibliotheque") {
                        roonService.browse()
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.roonAccent)
                    Spacer()
                }
            }
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
}
