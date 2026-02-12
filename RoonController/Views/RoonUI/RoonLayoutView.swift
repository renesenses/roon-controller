import SwiftUI

struct RoonLayoutView: View {
    @EnvironmentObject var roonService: RoonService
    @State private var selectedSection: RoonSection = .browse

    var body: some View {
        VStack(spacing: 0) {
            // Main area: sidebar + content
            HStack(spacing: 0) {
                RoonSidebarView(selectedSection: $selectedSection)

                Divider()
                    .overlay(Color.roonSeparator.opacity(0.5))

                RoonContentView(selectedSection: $selectedSection)
            }

            // Footer transport bar
            RoonTransportBarView()
        }
        .background(Color.roonBackground)
    }
}
