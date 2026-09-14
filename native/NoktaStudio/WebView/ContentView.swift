import SwiftUI
import WebKit

private enum AppSection: String, CaseIterable, Identifiable {
    case panel, asistente
    var id: String { rawValue }
    var label: String { self == .panel ? "Panel" : "Asistente" }
    var icon: String { self == .panel ? "square.grid.2x2" : "sparkles" }
}

struct ContentView: View {
    private static let adminURL = URL(string: "https://nokta-studio.onrender.com/admin")!
    private static let bgColor = Color(red: 0x1C/255.0, green: 0x1C/255.0, blue: 0x1A/255.0)
    private static let emberColor = Color(red: 0xB8/255.0, green: 0x52/255.0, blue: 0x28/255.0)

    @State private var webView = WKWebView(frame: .zero, configuration: makeNoktaWebViewConfiguration())
    @State private var isLoading = false
    @State private var canGoBack = false
    @State private var section: AppSection = .panel

    var body: some View {
        #if os(iOS)
        TabView(selection: $section) {
            webContent
                .ignoresSafeArea()
                .tabItem { Label(AppSection.panel.label, systemImage: AppSection.panel.icon) }
                .tag(AppSection.panel)

            NavigationStack { AssistantView() }
                .tabItem { Label(AppSection.asistente.label, systemImage: AppSection.asistente.icon) }
                .tag(AppSection.asistente)
        }
        #else
        NavigationStack {
            Group {
                if section == .panel { webContent } else { AssistantView() }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $section) {
                        ForEach(AppSection.allCases) { s in
                            Label(s.label, systemImage: s.icon).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                if section == .panel {
                    ToolbarItem {
                        if canGoBack {
                            Button { webView.goBack() } label: { Image(systemName: "chevron.left") }
                        }
                    }
                    ToolbarItem {
                        Button { webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                    }
                }
            }
        }
        #endif
    }

    private var webContent: some View {
        ZStack {
            Self.bgColor.ignoresSafeArea()

            NoktaWebView(url: Self.adminURL, isLoading: $isLoading, canGoBack: $canGoBack, webView: webView)
                .ignoresSafeArea()

            if isLoading {
                ProgressView().tint(Self.emberColor)
            }
        }
    }
}
