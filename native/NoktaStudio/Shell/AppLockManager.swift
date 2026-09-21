import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Locks the app locally after inactivity — separate from LoginView/logout:
/// the server session stays valid, this only hides the UI until the device
/// owner is verified again (Touch ID / Face ID / system passcode via
/// BiometricAuth, same as LoginView's biometric unlock). Only arms itself
/// when the device actually supports that check — no point locking a door
/// with no key.
@Observable
final class AppLockManager {
    var isLocked = false
    private let timeout: TimeInterval
    #if os(macOS)
    private var idleTimer: Timer?
    private var sleepObservers: [NSObjectProtocol] = []
    #endif

    init(timeout: TimeInterval = 5 * 60) {
        self.timeout = timeout
    }

    var isEnabled: Bool { BiometricAuth.isAvailable }

    func start() {
        guard isEnabled else { return }
        #if os(macOS)
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            let idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
            if idleSeconds >= self.timeout { Task { @MainActor in self.isLocked = true } }
        }
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers = [
            center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.isLocked = true },
            center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.isLocked = true },
        ]
        #endif
    }

    func stop() {
        #if os(macOS)
        idleTimer?.invalidate()
        idleTimer = nil
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers.forEach(center.removeObserver)
        sleepObservers = []
        #endif
    }

    /// iOS has no system-wide idle-time API a normal app can read — leaving
    /// the app (backgrounding, which also covers the device itself locking)
    /// is the equivalent "stepped away" signal there.
    func handleScenePhase(_ phase: ScenePhase) {
        guard isEnabled else { return }
        if phase == .background { isLocked = true }
    }

    func unlock() async -> Bool {
        guard await BiometricAuth.authenticate(reason: "Reanuda tu sesión en Nokta Studio") else { return false }
        isLocked = false
        return true
    }
}

/// Full-screen cover shown while AppLockManager.isLocked — deliberately
/// doesn't reveal any panel content behind it (no blur-of-real-data trick).
struct AppLockedView: View {
    let manager: AppLockManager
    @State private var isUnlocking = false
    @State private var failed = false

    var body: some View {
        ZStack {
            NoktaPalette.bg.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill").font(.system(size: 40)).foregroundStyle(NoktaPalette.ember)
                Text("Sesión bloqueada por inactividad").font(.system(size: 15, weight: .medium)).foregroundStyle(NoktaPalette.cream)
                if failed {
                    Text("No se pudo verificar. Inténtalo de nuevo.").font(.system(size: 12)).foregroundStyle(NoktaPalette.red)
                }
                Button(isUnlocking ? "Verificando…" : "Desbloquear") { Task { await unlock() } }
                    .buttonStyle(.glassProminent).tint(NoktaPalette.ember)
                    .disabled(isUnlocking)
            }
        }
        .task { await unlock() } // prompt immediately, no extra tap needed
    }

    private func unlock() async {
        guard !isUnlocking else { return }
        isUnlocking = true
        defer { isUnlocking = false }
        failed = !(await manager.unlock())
    }
}
