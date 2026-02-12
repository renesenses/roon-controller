import SwiftUI

struct RoonSidebarView: View {
    @EnvironmentObject var roonService: RoonService
    @Binding var selectedSection: RoonSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Zone selector at top
            zoneSelector
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 10)

            Divider()
                .overlay(Color.roonSeparator.opacity(0.3))

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    // Home
                    sidebarItem(.home)
                        .padding(.top, 6)

                    // Section header
                    Text("MA BIBLIOTHEQUE")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.roonTertiary)
                        .tracking(1.2)
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 4)

                    sidebarItem(.browse)
                    sidebarItem(.radio)
                    sidebarItem(.queue)
                    sidebarItem(.history)
                    sidebarItem(.favorites)
                }
                .padding(.bottom, 8)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 220)
        .background(Color.roonSidebar)
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
                    Text(roonService.currentZone?.display_name ?? "Aucune zone")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.roonText)
                        .lineLimit(1)
                    if let state = roonService.currentZone?.state {
                        Text(stateLabel(state))
                            .font(.system(size: 10))
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

    // MARK: - Sidebar Item

    private func sidebarItem(_ section: RoonSection) -> some View {
        Button {
            selectedSection = section
        } label: {
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(.system(size: 15))
                    .frame(width: 22)
                    .foregroundStyle(selectedSection == section ? Color.roonText : Color.roonSecondary)

                Text(section.label)
                    .font(.system(size: 13))
                    .foregroundStyle(selectedSection == section ? Color.roonText : Color.roonSecondary)

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .background(
                selectedSection == section
                    ? Color.roonGrey2.opacity(0.6)
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func stateLabel(_ state: String) -> String {
        switch state {
        case "playing": "Lecture en cours"
        case "paused": "En pause"
        case "loading": "Chargement..."
        default: "Arrete"
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
