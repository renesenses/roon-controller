import SwiftUI

@main
struct RoonControllerApp: App {
    @StateObject private var roonService = RoonService()
    @AppStorage("appTheme") private var appTheme = "light"

    private var colorScheme: ColorScheme? {
        AppTheme(rawValue: appTheme)?.colorScheme
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(roonService)
                .frame(minWidth: 800, minHeight: 500)
                .preferredColorScheme(colorScheme)
                .tint(Color.roonAccent)
                .task {
                    roonService.connect()
                }
                .onAppear { RoonFonts.registerAll(); applyAppearance() }
                .onChange(of: appTheme) { _, _ in applyAppearance() }
        }
        .defaultSize(width: 1200, height: 800)

        Settings {
            SettingsView()
                .environmentObject(roonService)
                .preferredColorScheme(colorScheme)
        }
    }

    private func applyAppearance() {
        switch AppTheme(rawValue: appTheme) {
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .system, .none:
            NSApp.appearance = nil
        }
    }
}
