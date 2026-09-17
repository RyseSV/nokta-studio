import SwiftUI
import CoreText

/// Exact colors copied from `:root` in server/views/admin.html — this is a
/// port, not a redesign. Keep these in lockstep with the CSS variables if
/// the web palette ever changes.
enum NoktaPalette {
    static let bg = Color(hex: 0x1C1C1A)
    static let sb = Color(hex: 0x111110)
    static let card = Color(hex: 0x2E2E2B)
    static let ember = Color(hex: 0xB85228)
    static let cream = Color(hex: 0xF0ECE4)
    static let muted = Color(hex: 0x7A7A72)
    static let green = Color(hex: 0x4CAF7D)
    static let yellow = Color(hex: 0xE6A817)
    static let red = Color(hex: 0xE05A5A)
    static let border = Color(hex: 0x3A3A37)
    /// `.pill-blue` — hardcoded in the CSS, never promoted to a `--variable`.
    static let blue = Color(hex: 0x6495ED)
    /// `#e55` (quincena "retrasado") — distinct from `--red`.
    static let overdue = Color(hex: 0xEE5555)
    /// `sb` blended with 8% `ember` — precomputed as a solid/opaque color so
    /// it can fully mask macOS's system-accent sidebar selection highlight
    /// (see RootView's sidebarRowLabel for why this must be opaque).
    static let sidebarActiveBg = Color(hex: 0x1E1612)

    /// Chart.js doughnut palette for "Por tipo de servicio".
    static let servicioPie: [Color] = [
        Color(hex: 0xB85228), Color(hex: 0xD4724A), Color(hex: 0xE8956E),
        Color(hex: 0x7A7A72), Color(hex: 0x4A4A47),
    ]
    /// Chart.js doughnut palette for "Nuevos vs recurrentes".
    static let nuevosRecurrentes: [Color] = [Color(hex: 0xB85228), Color(hex: 0x4CAF7D)]
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Poppins, bundled as .ttf (Resources/Fonts) since it's not a system font —
/// the web loads it from Google Fonts, native apps need it embedded.
enum NoktaFont {
    enum Weight { case light, regular, medium, semibold, bold
        var postScriptName: String {
            switch self {
            case .light: "Poppins-Light"
            case .regular: "Poppins-Regular"
            case .medium: "Poppins-Medium"
            case .semibold: "Poppins-SemiBold"
            case .bold: "Poppins-Bold"
            }
        }
    }

    static func poppins(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        .custom(weight.postScriptName, size: size)
    }

    // Named sizes matching admin.html's role table (px values there map 1:1 to pt here).
    static let pageTitle = poppins(20, .semibold)
    static let cardValue = poppins(24, .semibold)
    static let cardLabel = poppins(11, .regular)
    static let cardSub = poppins(12, .regular)
    static let sidebarLogo = poppins(22, .semibold)
    static let sidebarSection = poppins(10, .regular)
    static let sidebarLink = poppins(13, .regular)
    static let button = poppins(13, .medium)
    static let pill = poppins(11, .medium)
    static let chartTitle = poppins(13, .medium)
    static let tableHead = poppins(11, .regular)
    static let tableCell = poppins(13, .regular)
}

/// Registers the bundled Poppins .ttf files with CoreText so `Font.custom`
/// can find them by PostScript name — needed on both iOS and macOS since
/// this project synthesizes Info.plist (no `UIAppFonts` array to declare
/// them in) and runtime registration works identically on both platforms.
enum NoktaFontRegistrar {
    static func registerBundledFonts() {
        let names = ["Poppins-Light", "Poppins-Regular", "Poppins-Medium", "Poppins-SemiBold", "Poppins-Bold"]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// Corner radii from admin.html — flat design, no shadows except one
/// dropdown (`0 8px 24px rgba(0,0,0,.4)`), so depth comes from `card` vs
/// `bg`/`sb` contrast rather than elevation.
enum NoktaRadius {
    static let card: CGFloat = 12
    static let button: CGFloat = 8
    static let modal: CGFloat = 14
    static let pill: CGFloat = 20
}
