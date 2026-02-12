import SwiftUI
import CoreText

// MARK: - Roon Font Registration

enum RoonFonts {
    nonisolated(unsafe) private static var registered = false

    static func registerAll() {
        guard !registered else { return }
        registered = true
        let fontNames = ["GrifoM-Medium.otf", "GrifoS-Medium.otf", "Lato-Regular.ttf", "Lato-Bold.ttf"]
        for name in fontNames {
            if let url = Bundle.main.url(forResource: name, withExtension: nil)
                ?? Bundle.main.url(forResource: (name as NSString).deletingPathExtension,
                                   withExtension: (name as NSString).pathExtension,
                                   subdirectory: "Fonts") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}

// MARK: - Font Helpers

extension Font {
    /// Grifo M Medium — brand serif font for section headers, genre names
    static func grifoM(_ size: CGFloat) -> Font {
        .custom("GrifoM-Medium", size: size)
    }

    /// Grifo S Medium — brand serif font for artist names, subtitles
    static func grifoS(_ size: CGFloat) -> Font {
        .custom("GrifoS-Medium", size: size)
    }

    /// Lato Regular — body text, card titles
    static func lato(_ size: CGFloat) -> Font {
        .custom("Lato-Regular", size: size)
    }

    /// Lato Bold — emphasized body text
    static func latoBold(_ size: CGFloat) -> Font {
        .custom("Lato-Bold", size: size)
    }
}

// MARK: - Hover Scale Effect (Roon-style card interaction)

struct HoverScaleModifier: ViewModifier {
    @State private var isHovered = false
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension View {
    /// Roon-style hover scale effect for cards
    func hoverScale(_ scale: CGFloat = 1.04) -> some View {
        modifier(HoverScaleModifier(scale: scale))
    }
}
