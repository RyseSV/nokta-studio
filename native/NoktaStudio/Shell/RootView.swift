import SwiftUI
import WebKit

/// One entry per sidebar row in admin.html, same order/grouping/icons.
/// Sections without a native screen yet fall back to the shared WKWebView,
/// driven to the matching page via its `nav(id)` JS router.
enum NoktaSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard, calendario, alertas
    case nuevoTrabajo, trabajos, gastos, documentos
    case clientes, galerias
    case analiticas, equipo, reportes
    case usuarios
    case asistente

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard: "Dashboard"
        case .calendario: "Calendario"
        case .alertas: "Alertas"
        case .nuevoTrabajo: "Nuevo trabajo"
        case .trabajos: "Trabajos"
        case .gastos: "Gastos"
        case .documentos: "Documentos"
        case .clientes: "Clientes"
        case .galerias: "Galerías"
        case .analiticas: "Analíticas"
        case .equipo: "Mi equipo"
        case .reportes: "Reportes"
        case .usuarios: "Usuarios"
        case .asistente: "Asistente"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "▦"
        case .calendario: "📅"
        case .alertas: "🔔"
        case .nuevoTrabajo: "＋"
        case .trabajos: "💼"
        case .gastos: "💸"
        case .documentos: "📄"
        case .clientes: "👤"
        case .galerias: "🖼"
        case .analiticas: "📊"
        case .equipo: "👥"
        case .reportes: "📋"
        case .usuarios: "🔑"
        case .asistente: "✨"
        }
    }

    /// admin.html's `nav(id)` page id, or nil for sections with a native
    /// screen (no web navigation needed) — see server/views/admin.html's
    /// sidebar `onclick="nav('...')"` handlers for the exact id list.
    var webPageId: String? {
        switch self {
        case .dashboard, .asistente: nil
        case .nuevoTrabajo: "nuevo-trabajo"
        default: rawValue
        }
    }
}

private struct SidebarGroup { let title: String; let items: [NoktaSection] }
private let sidebarGroups: [SidebarGroup] = [
    SidebarGroup(title: "PRINCIPAL", items: [.dashboard, .calendario, .alertas]),
    SidebarGroup(title: "FINANZAS", items: [.nuevoTrabajo, .trabajos, .gastos, .documentos]),
    SidebarGroup(title: "CLIENTES", items: [.clientes, .galerias]),
    SidebarGroup(title: "NEGOCIO", items: [.analiticas, .equipo, .reportes]),
    SidebarGroup(title: "ADMINISTRACIÓN", items: [.usuarios]),
    SidebarGroup(title: "", items: [.asistente]),
]

/// Shared state/wiring both platform shells need: the one persistent
/// WKWebView instance (so it survives navigating away and back), the
/// nav(id) side effect, and the unread-alerts badge count.
@MainActor
private final class RootShell {
    static let adminURL = URL(string: "https://nokta-studio.onrender.com/admin")!
}

struct RootView: View {
    @State private var webView = WKWebView(frame: .zero, configuration: makeNoktaWebViewConfiguration())
    @State private var isLoading = false
    @State private var canGoBack = false
    @State private var unreadAlertas = 0

    var body: some View {
        Group {
            #if os(iOS)
            iOSShell
            #else
            macShell
            #endif
        }
        .task {
            if let alertas: [NoktaAlerta] = try? await NoktaAPI.get("/api/alertas") {
                unreadAlertas = alertas.filter { !$0.leida }.count
            }
        }
    }

    private func onSelect(_ item: NoktaSection) {
        if let pageId = item.webPageId {
            webView.evaluateJavaScript("if (typeof nav === 'function') { nav('\(pageId)'); }")
        }
    }

    @ViewBuilder
    private func detailView(for item: NoktaSection) -> some View {
        switch item {
        case .dashboard: DashboardView()
        case .asistente: AssistantView()
        default: webPanel
        }
    }

    private var webPanel: some View {
        ZStack {
            NoktaPalette.bg.ignoresSafeArea()
            NoktaWebView(url: RootShell.adminURL, isLoading: $isLoading, canGoBack: $canGoBack, webView: webView)
                .ignoresSafeArea()
            if isLoading { ProgressView().tint(NoktaPalette.ember) }
        }
    }

    // MARK: - macOS: NavigationSplitView with fully custom (Button-based)
    // sidebar rows. Deliberately NOT `List(selection:)` — on macOS a
    // selectable List always paints AppKit's system-accent selection
    // highlight/focus ring behind the row (it composites on top of any
    // `.listRowBackground`/content color we set), which fights the ember
    // Liquid-Glass-adjacent look everywhere else in the app. A plain Button
    // updating `@State selection` gives us full control of the "active row"
    // appearance with zero system chrome.
    #if os(macOS)
    @State private var macSelection: NoktaSection = .dashboard

    private var macShell: some View {
        NavigationSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    logoRow
                    ForEach(sidebarGroups, id: \.title) { group in
                        if !group.title.isEmpty {
                            Text(group.title)
                                .font(NoktaFont.sidebarSection)
                                .tracking(2)
                                .foregroundStyle(NoktaPalette.muted)
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                                .padding(.bottom, 6)
                        }
                        ForEach(group.items) { item in
                            Button {
                                macSelection = item
                                onSelect(item)
                            } label: {
                                sidebarRowLabel(item, isActive: macSelection == item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .background(NoktaPalette.sb)
            .navigationSplitViewColumnWidth(220)
        } detail: {
            detailView(for: macSelection)
        }
    }
    #endif

    // MARK: - iOS: plain NavigationStack + real NavigationLink push. A
    // pushed-and-popped row doesn't retain a persistent "selected" system
    // look the way a split-view sidebar List does, so this doesn't need the
    // same workaround as macOS.
    #if os(iOS)
    private var iOSShell: some View {
        NavigationStack {
            List {
                logoRow
                ForEach(sidebarGroups, id: \.title) { group in
                    Section {
                        ForEach(group.items) { item in
                            NavigationLink(value: item) {
                                sidebarRowLabel(item, isActive: false)
                            }
                            .listRowBackground(NoktaPalette.sb)
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        if !group.title.isEmpty {
                            Text(group.title)
                                .font(NoktaFont.sidebarSection)
                                .tracking(2)
                                .foregroundStyle(NoktaPalette.muted)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(NoktaPalette.sb)
            .navigationDestination(for: NoktaSection.self) { item in
                detailView(for: item)
                    .onAppear { onSelect(item) }
            }
        }
    }
    #endif

    private var logoRow: some View {
        HStack(spacing: 0) {
            Text("nokta").foregroundStyle(NoktaPalette.cream)
            Text(".").foregroundStyle(NoktaPalette.ember)
        }
        .font(NoktaFont.sidebarLogo)
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 20)
        .listRowBackground(NoktaPalette.sb)
        .listRowSeparator(.hidden)
    }

    private func sidebarRowLabel(_ item: NoktaSection, isActive: Bool) -> some View {
        HStack(spacing: 10) {
            Text(item.icon).font(.system(size: 16)).frame(width: 20, alignment: .center)
            Text(item.label).font(NoktaFont.sidebarLink)
            Spacer(minLength: 0)
            if item == .alertas, unreadAlertas > 0 {
                // String(_:), not a Text("\(unreadAlertas)") literal — a direct
                // interpolated-Int Text applies locale grouping (1,234) by default.
                Text(String(unreadAlertas))
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(NoktaPalette.ember, in: Capsule())
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 20)
        .foregroundStyle(isActive ? NoktaPalette.cream : NoktaPalette.muted)
        .background(isActive ? Color.clear : NoktaPalette.sb)
        .glassEffect(isActive ? .regular.tint(NoktaPalette.ember) : .identity, in: RoundedRectangle(cornerRadius: NoktaRadius.button))
        .overlay(alignment: .leading) {
            Rectangle().fill(isActive ? NoktaPalette.ember : .clear).frame(width: 3)
        }
        .contentShape(Rectangle())
    }
}
