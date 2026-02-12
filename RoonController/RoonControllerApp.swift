import SwiftUI

@main
struct RoonControllerApp: App {
    @StateObject private var roonService = RoonService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(roonService)
                .frame(minWidth: 800, minHeight: 500)
                .preferredColorScheme(.dark)
                .tint(Color.roonAccent)
                .task {
                    roonService.connect()
                }
        }
        .defaultSize(width: 1200, height: 800)

        Settings {
            SettingsView()
                .environmentObject(roonService)
        }
    }
}
