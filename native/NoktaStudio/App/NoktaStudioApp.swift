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
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}
