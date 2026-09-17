import SwiftUI
import WebKit

/// One entry per sidebar row in admin.html, same order/grouping/icons.
/// Sections without a native screen yet fall back to the shared WKWebView,
/// driven to the matching page via its `nav(id)` JS router.
enum NoktaSection: String, CaseIterable, Identifiable {
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

struct RootView: View {
    private static let adminURL = URL(string: "https://nokta-studio.onrender.com/admin")!

    @State private var selection: NoktaSection? = .dashboard
    @State private var webView = WKWebView(frame: .zero, configuration: makeNoktaWebViewConfiguration())
    @State private var isLoading = false
    @State private var canGoBack = false
    @State private var unreadAlertas = 0

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
        }
        .tint(NoktaPalette.ember)
        .accentColor(NoktaPalette.ember)
        .onChange(of: selection) { _, new in
            if let pageId = new?.webPageId {
                webView.evaluateJavaScript("if (typeof nav === 'function') { nav('\(pageId)'); }")
            }
        }
        .task {
            if let alertas: [NoktaAlerta] = try? await NoktaAPI.get("/api/alertas") {
                unreadAlertas = alertas.filter { !$0.leida }.count
            }
        }
    }

    /// `List(selection:)` (not a hand-rolled ScrollView+Button) is what makes
    /// NavigationSplitView do the right thing on both platforms: on Mac/iPad
    /// it swaps the detail column in place, on iPhone (compact) it pushes —
    /// a plain Button only updated `selection` without ever navigating on iOS.
    private var sidebar: some View {
        List(selection: $selection) {
            logoRow
            ForEach(sidebarGroups, id: \.title) { group in
                Section {
                    ForEach(group.items) { item in
                        sidebarRowLabel(item).tag(item)
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
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(NoktaPalette.sb)
        .tint(NoktaPalette.ember)
        .focusEffectDisabled()
        .navigationSplitViewColumnWidth(220)
    }

    private var logoRow: some View {
        HStack(spacing: 0) {
            Text("nokta").foregroundStyle(NoktaPalette.cream)
            Text(".").foregroundStyle(NoktaPalette.ember)
        }
        .font(NoktaFont.sidebarLogo)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func sidebarRowLabel(_ item: NoktaSection) -> some View {
        let isActive = selection == item
        return HStack(spacing: 10) {
            Text(item.icon).font(.system(size: 16)).frame(width: 20, alignment: .center)
            Text(item.label).font(NoktaFont.sidebarLink)
            Spacer(minLength: 0)
            if item == .alertas, unreadAlertas > 0 {
                Text("\(unreadAlertas)")
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(NoktaPalette.ember, in: Capsule())
            }
        }
        .foregroundStyle(isActive ? NoktaPalette.cream : NoktaPalette.muted)
        // Opaque, content-level background (not .listRowBackground) — on
        // macOS the sidebar List always paints its own system-accent-blue
        // selection highlight behind the row, on top of .listRowBackground,
        // so the only way to show our ember tint instead is to paint an
        // opaque layer as part of the row's own content, which composites
        // after (in front of) that highlight.
        .background(isActive ? NoktaPalette.sidebarActiveBg : NoktaPalette.sb)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .overlay(alignment: .leading) {
            Rectangle().fill(isActive ? NoktaPalette.ember : .clear).frame(width: 3)
        }
        .focusEffectDisabled()
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .dashboard, .none:
            DashboardView()
        case .asistente:
            AssistantView()
        default:
            webPanel
        }
    }

    private var webPanel: some View {
        ZStack {
            NoktaPalette.bg.ignoresSafeArea()
            NoktaWebView(url: Self.adminURL, isLoading: $isLoading, canGoBack: $canGoBack, webView: webView)
                .ignoresSafeArea()
            if isLoading { ProgressView().tint(NoktaPalette.ember) }
        }
    }
}
