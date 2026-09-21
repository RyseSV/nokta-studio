import SwiftUI
import AppIntents

@main
struct NoktaStudioApp: App {
    init() {
        NoktaShortcuts.updateAppShortcutParameters()
        NoktaFontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            SessionGateView()
                .preferredColorScheme(.dark)
        }
    }
}

/// Checks for an already-valid session cookie (e.g. from a previous "Recordar
/// sesión" login) before deciding whether to show LoginView or RootView —
/// this is what used to happen implicitly whenever the WKWebView loaded
/// /admin and the server redirected to the login page or not.
private enum SessionState: Equatable { case checking, loggedOut, loggedIn }

private struct SessionGateView: View {
    @State private var state: SessionState = .checking
    @State private var lockManager = AppLockManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch state {
            case .checking:
                ZStack {
                    NoktaPalette.bg.ignoresSafeArea()
                    ProgressView().tint(NoktaPalette.ember)
                }
            case .loggedOut:
                LoginView(onSuccess: { state = .loggedIn })
            case .loggedIn:
                RootView(onLogout: { state = .loggedOut })
                    .overlay { if lockManager.isLocked { AppLockedView(manager: lockManager) } }
            }
        }
        .task { await checkSession() }
        .onChange(of: state) { _, new in
            if new == .loggedIn { lockManager.start() } else { lockManager.stop() }
        }
        .onChange(of: scenePhase) { _, phase in lockManager.handleScenePhase(phase) }
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
