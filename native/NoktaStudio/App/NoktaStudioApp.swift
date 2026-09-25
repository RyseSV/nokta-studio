import SwiftUI
import AppIntents

@main
struct NoktaStudioApp: App {
    @AppStorage("noktaApariencia") private var apariencia: NoktaApariencia = .oscuro

    init() {
        NoktaShortcuts.updateAppShortcutParameters()
        NoktaFontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            SessionGateView()
                .preferredColorScheme(apariencia.colorScheme)
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

    var body: some View {
        Group {
            switch state {
            case .checking:
                PantallaInicio()
            case .loggedOut:
                LoginView(onSuccess: { state = .loggedIn })
            case .loggedIn:
                RootView(onLogout: { state = .loggedOut })
            }
        }
        .task { await checkSession() }
    }

    private func checkSession() async {
        struct Me: Decodable { let username: String? }
        if let _: Me = try? await NoktaAPI.get("/api/admin/me") {
            state = .loggedIn
        } else {
            state = .loggedOut
        }
    }
}

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
