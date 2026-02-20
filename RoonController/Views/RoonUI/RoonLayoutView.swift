import SwiftUI

struct RoonLayoutView: View {
    @EnvironmentObject var roonService: RoonService
    @AppStorage("roonSelectedSection") private var selectedSection: RoonSection = .home
    @State private var sidebarVisible = true

    var body: some View {
        VStack(spacing: 0) {
            // Main area: sidebar + content (fills remaining space)
            HStack(spacing: 0) {
                if sidebarVisible {
                    RoonSidebarView(selectedSection: $selectedSection)

                    Divider()
                        .overlay(Color.roonSeparator.opacity(0.5))
                }

                RoonContentView(
                    selectedSection: $selectedSection,
                    toggleSidebar: { sidebarVisible.toggle() }
                )
            }
            .frame(maxHeight: .infinity)
            .clipped()
            .animation(.easeInOut(duration: 0.2), value: sidebarVisible)

            // Footer transport bar (explicit height, never compressed)
            RoonTransportBarView {
                selectedSection = .nowPlaying
            }
            .frame(height: 90)
            .layoutPriority(1)
        }
        .background(Color.roonBackground)
    }
}
