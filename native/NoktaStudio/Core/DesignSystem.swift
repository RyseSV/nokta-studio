import SwiftUI
import CoreText

/// Legacy palette names, now mapped onto the premium adaptive `NoktaTheme`
/// (2026-09 redesign) so every screen picks up the new colors and follows the
/// Claro/Oscuro/Automático setting. New code should use `NoktaTheme` directly.
enum NoktaPalette {
    static let bg = NoktaTheme.fondo
    static let sb = NoktaTheme.fondo
    static let card = NoktaTheme.superficie
    static let ember = NoktaTheme.marca
    static let cream = NoktaTheme.texto
    static let muted = NoktaTheme.textoSuave
    static let green = NoktaTheme.exito
    static let yellow = NoktaTheme.aviso
    static let red = NoktaTheme.error
    static let border = NoktaTheme.borde
    /// `.pill-blue` — hardcoded in the CSS, never promoted to a `--variable`.
    static let blue = Color(light: 0x3F6FD8, dark: 0x6495ED)
    /// Quincena "retrasado" — same family as `red`.
    static let overdue = NoktaTheme.error

    /// Doughnut palette for "Por tipo de servicio".
    static let servicioPie: [Color] = [
        NoktaTheme.marca, NoktaTheme.marca.opacity(0.62), NoktaTheme.marca.opacity(0.36),
        NoktaTheme.textoTenue, NoktaTheme.superficie2,
    ]
    /// Doughnut palette for "Nuevos vs recurrentes".
    static let nuevosRecurrentes: [Color] = [NoktaTheme.marca, NoktaTheme.exito]
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// A color that resolves differently in light and dark appearance.
    init(light: UInt32, _ lightAlpha: Double = 1, dark: UInt32, _ darkAlpha: Double = 1) {
        func comps(_ h: UInt32) -> (CGFloat, CGFloat, CGFloat) {
            (CGFloat((h >> 16) & 0xFF) / 255, CGFloat((h >> 8) & 0xFF) / 255, CGFloat(h & 0xFF) / 255)
        }
        let (lr, lg, lb) = comps(light), (dr, dg, db) = comps(dark)
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: dr, green: dg, blue: db, alpha: darkAlpha)
                : NSColor(srgbRed: lr, green: lg, blue: lb, alpha: lightAlpha)
        })
        #else
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: dr, green: dg, blue: db, alpha: darkAlpha)
                : UIColor(red: lr, green: lg, blue: lb, alpha: lightAlpha)
        })
        #endif
    }
}

/// Premium redesign palette (2026-09) — same tokens as the "Tema Oscuro" /
/// "Tema Claro" variables in the Figma file "Nokta Studio – Rediseño
/// Dashboard". Adapts to light/dark. Screens not yet redesigned still use
/// `NoktaPalette` and are pinned to dark in RootView.
enum NoktaTheme {
    static let fondo = Color(light: 0xF6F4EF, dark: 0x0C0C0B)
    static let superficie = Color(light: 0xFFFFFF, dark: 0x141413)
    static let superficie2 = Color(light: 0xEFECE6, dark: 0x1C1C1A)
    static let borde = Color(light: 0x1A1917, 0.08, dark: 0xFFFFFF, 0.07)
    static let texto = Color(light: 0x191816, dark: 0xF4F1EA)
    static let textoSuave = Color(light: 0x191816, 0.52, dark: 0xF4F1EA, 0.5)
    static let textoTenue = Color(light: 0x191816, 0.32, dark: 0xF4F1EA, 0.3)
    static let marca = Color(light: 0xB85228, dark: 0xD0673A)
    static let marcaSuave = Color(light: 0xB85228, 0.09, dark: 0xD0673A, 0.13)
    static let exito = Color(light: 0x2E8B5A, dark: 0x6CC495)
    static let exitoSuave = Color(light: 0x2E8B5A, 0.1, dark: 0x6CC495, 0.12)
    static let aviso = Color(light: 0xA86B12, dark: 0xE3AE4A)
    static let avisoSuave = Color(light: 0xA86B12, 0.1, dark: 0xE3AE4A, 0.12)
    static let error = Color(light: 0xC0392B, dark: 0xE8706A)

    static let radioTarjeta: CGFloat = 20
}

/// User-chosen appearance, persisted in UserDefaults under `noktaApariencia`.
enum NoktaApariencia: String, CaseIterable, Identifiable {
    case sistema, claro, oscuro
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sistema: "Automático"
        case .claro: "Claro"
        case .oscuro: "Oscuro"
        }
    }
    var icon: String {
        switch self {
        case .sistema: "circle.lefthalf.filled"
        case .claro: "sun.max"
        case .oscuro: "moon"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .sistema: nil
        case .claro: .light
        case .oscuro: .dark
        }
    }
}

/// Flat surface card used across the redesigned screens: solid surface,
/// hairline border, and a whisper of shadow in light mode only.
struct NoktaCardStyle: ViewModifier {
    var padding: CGFloat = 24
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: NoktaTheme.radioTarjeta, style: .continuous)
        content
            .padding(padding)
            // Shadow on the background shape only — applied to the whole
            // card it also haloed text that renders in its own layer
            // (e.g. `.contentTransition(.numericText)` numbers).
            .background(
                shape.fill(NoktaTheme.superficie)
                    .shadow(color: .black.opacity(scheme == .light ? 0.05 : 0), radius: 10, y: 3)
            )
            .overlay(shape.strokeBorder(NoktaTheme.borde, lineWidth: 1))
    }
}

extension View {
    func noktaCard(padding: CGFloat = 24) -> some View { modifier(NoktaCardStyle(padding: padding)) }
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
