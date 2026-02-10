import SwiftUI

struct ContentView: View {
    @EnvironmentObject var roonService: RoonService

    var body: some View {
        Group {
            if roonService.connectionState == .disconnected && roonService.zones.isEmpty {
                ConnectionView()
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
