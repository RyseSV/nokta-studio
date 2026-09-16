import SwiftUI
import AppIntents

@main
struct NoktaStudioApp: App {
    init() {
        NoktaShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
