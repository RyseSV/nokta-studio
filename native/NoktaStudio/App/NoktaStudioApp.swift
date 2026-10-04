import SwiftUI
import AppIntents
#if os(iOS)
import UIKit
#else
import AppKit
#endif

@main
struct NoktaStudioApp: App {


    init() {
        NoktaShortcuts.updateAppShortcutParameters()
        NoktaFontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            NoktaAppearanceHost {
                SessionGateView()
            }
        }
    }
}

/// Checks for an already-valid session cookie (e.g. from a previous "Recordar
/// sesión" login) before deciding whether to show LoginView or RootView —
/// this is what used to happen implicitly whenever the WKWebView loaded
/// /admin and the server redirected to the login page or not.
private enum SessionState { case checking, loggedOut, loggedIn }

private struct SessionGateView: View {
    @State private var state: SessionState = .checking
    @State private var inactividad = Inactividad()
    @State private var aviso: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch state {
            case .checking:
                PantallaInicio()
            case .loggedOut:
                LoginView(onSuccess: { entrar() }, aviso: aviso)
            case .loggedIn:
                RootView(onLogout: { salir(aviso: nil) })
            }
        }
        .task { await checkSession() }
        // Al volver a la app (o al despertar la Mac) se revisa de inmediato:
        // si pasó el límite sin usarla, se cierra la sesión.
        .onChange(of: scenePhase) { _, fase in
            if fase == .active, state == .loggedIn, inactividad.vencida { cerrarPorInactividad() }
        }
        // El servidor ya cerró la sesión (también vence a los 12 min sin uso).
        .onReceive(NotificationCenter.default.publisher(for: .noktaSesionVencida)) { _ in
            if state == .loggedIn { cerrarPorInactividad() }
        }
    }

    private func checkSession() async {
        struct Me: Decodable { let username: String? }
        if let _: Me = try? await NoktaAPI.get("/api/admin/me") {
            // Sesión guardada, pero la app se quedó sin usar más del límite
            // (p. ej. se cerró y se abrió horas después): hay que volver a entrar.
            if inactividad.vencida {
                cerrarPorInactividad()
            } else {
                entrar()
            }
        } else {
            state = .loggedOut
        }
    }

    private func entrar() {
        aviso = nil
        state = .loggedIn
        inactividad.iniciar { cerrarPorInactividad() }
    }

    private func salir(aviso: String?) {
        inactividad.detener()
        self.aviso = aviso
        state = .loggedOut
    }

    private func cerrarPorInactividad() {
        guard state != .loggedOut else { return }
        salir(aviso: "Cerramos tu sesión por inactividad. Vuelve a entrar.")
        Task {
            // Aunque falle el internet, la sesión local se borra igual.
            try? await NoktaAPI.logout()
            NoktaAPI.clearSessionCookies()
        }
    }
}

/// Cierre de sesión por inactividad, como las apps del banco: si pasan
/// `limite` segundos sin tocar la app (ni teclear ni mover el mouse dentro de
/// ella), se cierra la sesión. Se mide con la hora real de la última
/// actividad DENTRO de Nokta (guardada en UserDefaults), así que funciona
/// aunque la app se cierre, se vaya al fondo o la Mac se duerma, y nunca
/// depende de contadores del sistema (el intento anterior leía mal el tiempo
/// inactivo de macOS y sacaba a los 20–30 segundos).
@MainActor
@Observable
final class Inactividad {
    #if DEBUG
    // Para probar en el simulador con un límite corto: NOKTA_INACTIVIDAD=40
    static let limite: TimeInterval = ProcessInfo.processInfo.environment["NOKTA_INACTIVIDAD"].flatMap(Double.init) ?? 10 * 60
    #else
    static let limite: TimeInterval = 10 * 60
    #endif
    private static let clave = "noktaUltimaActividad"

    private var ultima: TimeInterval = UserDefaults.standard.double(forKey: Inactividad.clave)
    private var ultimaGuardada: TimeInterval = 0
    private var ultimoAviso: TimeInterval = 0
    private var reloj: Timer?
    private var alVencer: (() -> Void)?
    private var observadores: [NSObjectProtocol] = []
    #if os(macOS)
    private var monitor: Any?
    #else
    private var toque: ToqueGlobal?
    #endif

    /// Sin registro previo (primera vez) no cuenta como vencida.
    var vencida: Bool { ultima > 0 && Date().timeIntervalSince1970 - ultima >= Self.limite }

    func iniciar(alVencer: @escaping () -> Void) {
        detener()
        self.alVencer = alVencer
        ultimoAviso = Date().timeIntervalSince1970
        marcar(forzar: true)
        reloj = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.vencida else { return }
                self.alVencer?()
            }
        }
        #if os(macOS)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseDragged, .scrollWheel, .keyDown]) { [weak self] e in
            self?.marcar()
            return e
        }
        #else
        let g = ToqueGlobal { [weak self] in self?.marcar() }
        for escena in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for ventana in escena.windows { ventana.addGestureRecognizer(g) }
        }
        toque = g
        // Teclear en un campo no pasa por la ventana de la app (el teclado es
        // otra ventana), así que también cuenta como actividad.
        for n in [UITextField.textDidChangeNotification, UITextView.textDidChangeNotification] {
            observadores.append(NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.marcar() }
            })
        }
        #endif
    }

    func detener() {
        reloj?.invalidate(); reloj = nil
        alVencer = nil
        observadores.forEach(NotificationCenter.default.removeObserver)
        observadores = []
        #if os(macOS)
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        #else
        if let toque { toque.view?.removeGestureRecognizer(toque) }
        toque = nil
        #endif
    }

    /// Guarda la hora como máximo cada 5 s (mover el mouse dispara muchísimos eventos).
    private func marcar(forzar: Bool = false) {
        let ahora = Date().timeIntervalSince1970
        ultima = ahora
        if forzar || ahora - ultimaGuardada >= 5 {
            ultimaGuardada = ahora
            UserDefaults.standard.set(ahora, forKey: Self.clave)
        }
        // Como mucho cada 2 min se le avisa al servidor que sigues usando la
        // app (leer o desplazarte no carga datos, y el servidor no lo vería).
        if !forzar, ahora - ultimoAviso >= 120 {
            ultimoAviso = ahora
            Task {
                struct Vacio: Encodable {}
                struct Ok: Decodable { let ok: Bool? }
                let _: Ok? = try? await NoktaAPI.post("/api/admin/actividad", body: Vacio())
            }
        }
    }
}

#if os(iOS)
/// Detecta cualquier toque en la ventana sin interferir: falla al instante,
/// así los botones, listas y gestos de la app funcionan igual que siempre.
private final class ToqueGlobal: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private let alTocar: () -> Void
    init(alTocar: @escaping () -> Void) {
        self.alTocar = alTocar
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        alTocar()
        state = .failed
    }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otro: UIGestureRecognizer) -> Bool { true }
}
#endif

/// Shown while the saved session is checked (can take a few seconds when the
/// server is waking up): the brand mark with a softly pulsing dot instead of
/// a bare spinner.
private struct PantallaInicio: View {
    @State private var late = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            NoktaTheme.fondo.ignoresSafeArea()
            HStack(spacing: 9) {
                Circle().fill(NoktaTheme.marca).frame(width: 10, height: 10)
                    .scaleEffect(late ? 1.25 : 0.85)
                    .shadow(color: NoktaTheme.marca.opacity(0.7), radius: late ? 10 : 2)
                HStack(spacing: 6) {
                    Text("nokta").font(NoktaFont.poppins(26, .medium)).foregroundStyle(NoktaTheme.texto)
                    Text("studio").font(NoktaFont.poppins(26, .light)).foregroundStyle(NoktaTheme.textoTenue)
                }
                .tracking(-0.8)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { late = true }
        }
    }
}
