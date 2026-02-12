import SwiftUI

struct ContentView: View {
    @EnvironmentObject var roonService: RoonService
    @AppStorage("uiMode") private var uiMode = "player"

    var body: some View {
        Group {
            if roonService.connectionState == .disconnected && roonService.zones.isEmpty {
                ConnectionView()
            } else if uiMode == "roon" {
                RoonLayoutView()
            } else {
                NavigationSplitView {
                    SidebarView()
                } detail: {
                    PlayerView()
                }
            }
        }
        .background(Color.roonBackground)
    }
}
