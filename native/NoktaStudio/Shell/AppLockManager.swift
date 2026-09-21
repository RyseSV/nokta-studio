import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Closes the session after inactivity — not a local lock screen. After the
/// timeout, `onTimeout` fires and the caller does a real logout (same
/// POST /api/admin/logout the sidebar's logout button uses), dropping back
/// to LoginView, where the Touch ID / Face ID button (if a credential is
/// saved) or typing the password again both work. Only arms itself when the
/// device actually supports biometrics/passcode — no point requiring
/// re-entry with no fast way back in.
@Observable
final class AppLockManager {
    private let timeout: TimeInterval
    var onTimeout: (() -> Void)?
    #if os(macOS)
    private var idleTimer: Timer?
    private var sleepObservers: [NSObjectProtocol] = []
    #endif

    init(timeout: TimeInterval = 10 * 60) {
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
            if idleSeconds >= self.timeout { self.fire() }
        }
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers = [
            center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.fire() },
            center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.fire() },
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
        if phase == .background { fire() }
    }

    private func fire() {
        stop()
        onTimeout?()
    }
}
