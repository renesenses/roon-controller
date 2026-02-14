import SwiftUI

struct RoonLayoutView: View {
    @EnvironmentObject var roonService: RoonService
    @SceneStorage("roonSelectedSection") private var selectedSection: RoonSection = .home
    @State private var sidebarVisible = true

    var body: some View {
        GeometryReader { geo in
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
                .frame(height: geo.size.height - 90)
                .clipped()
                .animation(.easeInOut(duration: 0.2), value: sidebarVisible)

                // Footer transport bar (explicit height, never compressed)
                RoonTransportBarView {
                    selectedSection = .nowPlaying
                }
                .frame(height: 90)
            }
        }
        .background(Color.roonBackground)
    }
}
