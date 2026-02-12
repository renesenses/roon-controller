import SwiftUI

extension Color {
    // Backgrounds — from Roon Dark theme
    static let roonBackground = Color(red: 0x18/255, green: 0x18/255, blue: 0x18/255)  // #181818 atom-background
    static let roonSurface    = Color(red: 0x1e/255, green: 0x1e/255, blue: 0x1e/255)  // #1E1E1E atom-grey1
    static let roonSidebar    = Color(red: 0x18/255, green: 0x18/255, blue: 0x18/255)  // #181818 same as background
    static let roonFooter     = Color(red: 0x24/255, green: 0x24/255, blue: 0x24/255)  // #242424 atom-footer
    static let roonPanel      = Color(red: 0x24/255, green: 0x24/255, blue: 0x24/255)  // #242424 atom-panel
    static let roonPopup      = Color(red: 0x26/255, green: 0x26/255, blue: 0x26/255)  // #262626 atom-popup

    // Interactive
    static let roonGrey2      = Color(red: 0x3c/255, green: 0x3c/255, blue: 0x3f/255)  // #3C3C3F atom-grey2

    // Accent — Roon's signature purple-blue
    static let roonAccent     = Color(red: 0x6b/255, green: 0x6e/255, blue: 0xd9/255)  // #6B6ED9 atom-blue
    static let roonAccentHover = Color(red: 0x78/255, green: 0x7c/255, blue: 0xd7/255) // #787CD7

    // Semantic
    static let roonGreen      = Color(red: 0x57/255, green: 0xc6/255, blue: 0xb9/255)  // #57C6B9
    static let roonOrange     = Color(red: 0xc9/255, green: 0x54/255, blue: 0x4b/255)  // #C9544B
    static let roonRed        = Color(red: 0xe0/255, green: 0x29/255, blue: 0x54/255)  // #E02954

    // Separators
    static let roonSeparator  = Color(red: 0x4d/255, green: 0x4e/255, blue: 0x51/255)  // #4D4E51 atom-separator-light
    static let roonBorder     = Color(red: 0x41/255, green: 0x42/255, blue: 0x45/255)  // #414245 atom-border

    // Text
    static let roonText       = Color.white                                              // #FFFFFF atom-grey4
    static let roonSecondary  = Color(red: 0xa8/255, green: 0xa8/255, blue: 0xa8/255)  // #A8A8A8 atom-grey4-secondary
    static let roonTertiary   = Color(red: 0x66/255, green: 0x66/255, blue: 0x66/255)  // #666666
}
