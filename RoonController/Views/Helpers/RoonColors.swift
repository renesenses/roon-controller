import SwiftUI
import AppKit

// MARK: - Theme

enum AppTheme: String, CaseIterable {
    case dark, light, system

    var label: String {
        switch self {
        case .dark: "Sombre"
        case .light: "Clair"
        case .system: "Systeme"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

// MARK: - Adaptive Colors (Roon Creamsicle light / Dark theme)

extension Color {

    /// Creates a Color that adapts to light/dark appearance automatically.
    private static func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let (r, g, b) = isDark ? dark : light
            return NSColor(red: r/255, green: g/255, blue: b/255, alpha: 1)
        })
    }

    // Backgrounds — Creamsicle: white-based / Dark: #181818-based
    static let roonBackground = adaptive(light: (0xFF, 0xFF, 0xFF), dark: (0x18, 0x18, 0x18))  // atom-background
    static let roonSurface    = adaptive(light: (0xFF, 0xFF, 0xFF), dark: (0x1E, 0x1E, 0x1E))  // atom-grey1
    static let roonSidebar    = adaptive(light: (0xF7, 0xF8, 0xF9), dark: (0x18, 0x18, 0x18))  // atom-footer
    static let roonFooter     = adaptive(light: (0xF7, 0xF8, 0xF9), dark: (0x24, 0x24, 0x24))  // atom-footer
    static let roonPanel      = adaptive(light: (0xFA, 0xFA, 0xFA), dark: (0x24, 0x24, 0x24))  // atom-panel
    static let roonPopup      = adaptive(light: (0xFF, 0xFF, 0xFF), dark: (0x26, 0x26, 0x26))  // atom-popup

    // Interactive — Creamsicle: #D8DFE6 selectable / Dark: #3C3C3F
    static let roonGrey2      = adaptive(light: (0xD8, 0xDF, 0xE6), dark: (0x3C, 0x3C, 0x3F))  // atom-grey2/selectable

    // Accent — Creamsicle: #7574F3 / Dark: #6B6ED9
    static let roonAccent     = adaptive(light: (0x75, 0x74, 0xF3), dark: (0x6B, 0x6E, 0xD9))  // atom-blue
    static let roonAccentHover = adaptive(light: (0x6D, 0x6C, 0xD4), dark: (0x78, 0x7C, 0xD7))

    // Semantic
    static let roonGreen      = adaptive(light: (0x57, 0xC6, 0xB9), dark: (0x57, 0xC6, 0xB9))  // same both
    static let roonOrange     = adaptive(light: (0xF2, 0x45, 0x37), dark: (0xC9, 0x54, 0x4B))
    static let roonRed        = adaptive(light: (0xE0, 0x29, 0x54), dark: (0xE0, 0x29, 0x54))  // same both

    // Separators — Creamsicle: #E4E4E4 light, #CFCFD0 heavy / Dark: #4D4E51, #414245
    static let roonSeparator  = adaptive(light: (0xE4, 0xE4, 0xE4), dark: (0x4D, 0x4E, 0x51))  // atom-separator-light
    static let roonBorder     = adaptive(light: (0xCF, 0xCF, 0xD0), dark: (0x41, 0x42, 0x45))  // atom-separator-heavy

    // Text — Creamsicle: #2C2C2E grey4, #4A4A4A grey3 / Dark: white, #A8A8A8
    static let roonText       = adaptive(light: (0x2C, 0x2C, 0x2E), dark: (0xFF, 0xFF, 0xFF))  // atom-grey4
    static let roonSecondary  = adaptive(light: (0x4A, 0x4A, 0x4A), dark: (0xA8, 0xA8, 0xA8))  // atom-grey3
    static let roonTertiary   = adaptive(light: (0x8E, 0x8E, 0x93), dark: (0x66, 0x66, 0x66))  // muted
}
