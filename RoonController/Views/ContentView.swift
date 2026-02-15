import SwiftUI

struct ContentView: View {
    @EnvironmentObject var roonService: RoonService
    @AppStorage("uiMode") private var uiMode = "roon"

    var body: some View {
        Group {
            if (roonService.connectionState == .disconnected || roonService.connectionState == .waitingForApproval) && roonService.zones.isEmpty {
                ConnectionView()
            } else if uiMode == "roon" {
                RoonLayoutView()
            } else {
                NavigationView {
                    SidebarView()
                    PlayerView()
                }
                .navigationViewStyle(.columns)
            }
        }
        .background(Color.roonBackground)
    }
}
