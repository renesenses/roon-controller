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
                    await roonService.ensureBackendRunning()
                    roonService.connect()
                }
        }
        .defaultSize(width: 1000, height: 700)

        Settings {
            SettingsView()
                .environmentObject(roonService)
        }
    }
}
