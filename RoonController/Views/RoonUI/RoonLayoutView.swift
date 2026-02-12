import SwiftUI

struct RoonLayoutView: View {
    @EnvironmentObject var roonService: RoonService
    @State private var selectedSection: RoonSection = .home
    @State private var sidebarVisible = true

    var body: some View {
        VStack(spacing: 0) {
            // Main area: sidebar + content
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
            .animation(.easeInOut(duration: 0.2), value: sidebarVisible)

            // Footer transport bar
            RoonTransportBarView {
                selectedSection = .nowPlaying
            }
        }
        .background(Color.roonBackground)
    }
}
