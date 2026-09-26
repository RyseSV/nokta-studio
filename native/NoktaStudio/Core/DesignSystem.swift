import SwiftUI
import CoreText
import Observation

/// Legacy palette names, now mapped onto the premium adaptive `NoktaTheme`
/// (2026-09 redesign) so every screen picks up the new colors and follows the
/// Claro/Oscuro/Automático setting. These computed tokens register observation.
enum NoktaPalette {
    static var bg: Color { NoktaTheme.fondo }
    static var sb: Color { NoktaTheme.fondo }
    static var card: Color { NoktaTheme.superficie }
    static var ember: Color { NoktaTheme.marca }
    static var cream: Color { NoktaTheme.texto }
    static var muted: Color { NoktaTheme.textoSuave }
    static var green: Color { NoktaTheme.exito }
    static var yellow: Color { NoktaTheme.aviso }
    static var red: Color { NoktaTheme.error }
    static var border: Color { NoktaTheme.borde }
    /// `.pill-blue` — hardcoded in the CSS, never promoted to a `--variable`.
    static var blue: Color { Color(light: 0x3F6FD8, dark: 0x6495ED) }
    /// Quincena "retrasado" — same family as `red`.
    static var overdue: Color { NoktaTheme.error }

    /// Doughnut palette for "Por tipo de servicio".
    static var servicioPie: [Color] { [
        NoktaTheme.marca, NoktaTheme.marca.opacity(0.62), NoktaTheme.marca.opacity(0.36),
        NoktaTheme.textoTenue, NoktaTheme.superficie2,
    ] }
    /// Doughnut palette for "Nuevos vs recurrentes".
    static var nuevosRecurrentes: [Color] { [NoktaTheme.marca, NoktaTheme.exito] }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// Concrete RGB components; reading the shared observable state registers
    /// SwiftUI's dependency even through the legacy static palette helpers.
    init(light: UInt32, _ lightAlpha: Double = 1, dark: UInt32, _ darkAlpha: Double = 1) {
        let isDark = NoktaAppearance.shared.effectiveScheme == .dark
        self = Color(hex: isDark ? dark : light).opacity(isDark ? darkAlpha : lightAlpha)
    }
}

/// Premium redesign palette (2026-09) — same tokens as the "Tema Oscuro" /
/// "Tema Claro" variables in the Figma file "Nokta Studio – Rediseño
/// Dashboard". Both new and legacy screens observe the same appearance.
enum NoktaTheme {
    static var fondo: Color { Color(light: 0xF6F4EF, dark: 0x0C0C0B) }
    static var superficie: Color { Color(light: 0xFFFFFF, dark: 0x141413) }
    static var superficie2: Color { Color(light: 0xEFECE6, dark: 0x1C1C1A) }
    static var borde: Color { Color(light: 0x1A1917, 0.08, dark: 0xFFFFFF, 0.07) }
    static var texto: Color { Color(light: 0x191816, dark: 0xF4F1EA) }
    static var textoSuave: Color { Color(light: 0x191816, 0.52, dark: 0xF4F1EA, 0.5) }
    static var textoTenue: Color { Color(light: 0x191816, 0.32, dark: 0xF4F1EA, 0.3) }
    static var marca: Color { Color(light: 0xB85228, dark: 0xD0673A) }
    static var marcaSuave: Color { Color(light: 0xB85228, 0.09, dark: 0xD0673A, 0.13) }
    static var exito: Color { Color(light: 0x2E8B5A, dark: 0x6CC495) }
    static var exitoSuave: Color { Color(light: 0x2E8B5A, 0.1, dark: 0x6CC495, 0.12) }
    static var aviso: Color { Color(light: 0xA86B12, dark: 0xE3AE4A) }
    static var avisoSuave: Color { Color(light: 0xA86B12, 0.1, dark: 0xE3AE4A, 0.12) }
    static var error: Color { Color(light: 0xC0392B, dark: 0xE8706A) }

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

/// One in-process source of truth. UI mutations and system appearance callbacks
/// run on the main thread. Persistence is separate from SwiftUI invalidation.
@Observable
final class NoktaAppearance {
    static let shared = NoktaAppearance()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var systemObserver: NSKeyValueObservation?

    var selection: NoktaApariencia {
        didSet { defaults.set(selection.rawValue, forKey: "noktaApariencia") }
    }
    var systemScheme: ColorScheme = .light
    var effectiveScheme: ColorScheme { selection.colorScheme ?? systemScheme }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = defaults.string(forKey: "noktaApariencia")
            .flatMap(NoktaApariencia.init(rawValue:)) ?? .oscuro
    }

    #if os(macOS)
    @MainActor
    func observeSystemAppearance() {
        guard systemObserver == nil else { return }
        // Application appearance stays inherited. Window overrides must not be
        // mistaken for the OS appearance when switching back to Automatic.
        NSApp.appearance = nil
        systemScheme = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        systemObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] app, _ in
            let scheme: ColorScheme = app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
            DispatchQueue.main.async { self?.systemScheme = scheme }
        }
    }
    #endif
}

/// Reads iOS's inherited appearance when automatic; explicit choices use the
/// model directly. On macOS the application KVO above observes the OS instead.
struct NoktaAppearanceHost<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @State private var appearance = NoktaAppearance.shared
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            #if os(macOS)
            // Resolve Automatic from AppKit's system appearance too: clearing
            // preferredColorScheme to nil can leave native window chrome stale.
            .preferredColorScheme(appearance.effectiveScheme)
            .onAppear { appearance.observeSystemAppearance() }
            #else
            .preferredColorScheme(appearance.selection.colorScheme)
            .onChange(of: scheme, initial: true) { _, value in
                appearance.systemScheme = value
            }
            #endif
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
