import SwiftUI
import AppKit

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
                .accentColor(Color.roonAccent)
                .task {
                    roonService.connect()
                }
                .onAppear {
                    RoonFonts.registerAll()
                    applyAppearance()
                    UserDefaults.standard.set("roon", forKey: "uiMode")
                    UserDefaults.standard.set("home", forKey: "roonSelectedSection")
                    installMouseBackButtonMonitor()
                }
                .onChangeCompat(of: appTheme) { applyAppearance() }
        }

        Settings {
            SettingsView()
                .environmentObject(roonService)
                .preferredColorScheme(colorScheme)
        }
    }

    private func installMouseBackButtonMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { event in
            // Mouse button 3 = back button on multi-button mice
            if event.buttonNumber == 3 {
                if !roonService.browseStack.isEmpty {
                    roonService.browseBack()
                }
                return nil // consume the event
            }
            return event
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
