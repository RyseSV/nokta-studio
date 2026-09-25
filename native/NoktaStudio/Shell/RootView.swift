import SwiftUI
import WebKit

/// One entry per sidebar row in admin.html, same order/grouping/icons.
/// Sections without a native screen yet fall back to the shared WKWebView,
/// driven to the matching page via its `nav(id)` JS router.
enum NoktaSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard, calendario, alertas
    case nuevoTrabajo, trabajos, gastos, documentos, contratos
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
        case .contratos: "Contratos"
        case .clientes: "Clientes"
        case .galerias: "Galerías"
        case .analiticas: "Analíticas"
        case .equipo: "Mi equipo"
        case .reportes: "Reportes"
        case .usuarios: "Usuarios"
        case .asistente: "Asistente"
        }
    }

    /// SF Symbol name — thin-line style, rendered at `.light` weight.
    var icon: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .calendario: "calendar"
        case .alertas: "bell"
        case .nuevoTrabajo: "plus.circle"
        case .trabajos: "briefcase"
        case .gastos: "creditcard"
        case .documentos: "doc.text"
        case .contratos: "signature"
        case .clientes: "person.2"
        case .galerias: "photo.on.rectangle"
        case .analiticas: "chart.pie"
        case .equipo: "person.3"
        case .reportes: "chart.bar"
        case .usuarios: "key"
        case .asistente: "sparkles"
        }
    }

    /// admin.html's `nav(id)` page id, or nil for sections with a native
    /// screen (no web navigation needed) — see server/views/admin.html's
    /// sidebar `onclick="nav('...')"` handlers for the exact id list.
    var webPageId: String? {
        switch self {
        case .dashboard, .asistente, .trabajos, .nuevoTrabajo, .calendario, .alertas, .clientes, .galerias,
             .gastos, .documentos, .contratos, .reportes, .analiticas, .equipo, .usuarios: nil
        default: rawValue
        }
    }
}

private struct SidebarGroup { let title: String; let items: [NoktaSection] }
private let sidebarGroups: [SidebarGroup] = [
    SidebarGroup(title: "GENERAL", items: [.dashboard, .calendario, .alertas, .asistente]),
    SidebarGroup(title: "TRABAJOS", items: [.nuevoTrabajo, .trabajos, .contratos, .documentos]),
    SidebarGroup(title: "FINANZAS", items: [.gastos, .reportes, .analiticas]),
    SidebarGroup(title: "CLIENTES", items: [.clientes, .galerias]),
    SidebarGroup(title: "ESTUDIO", items: [.equipo]),
    SidebarGroup(title: "ADMINISTRACIÓN", items: [.usuarios]),
]

/// Shared state/wiring both platform shells need: the one persistent
/// WKWebView instance (so it survives navigating away and back), the
/// nav(id) side effect, and the unread-alerts badge count.
@MainActor
private final class RootShell {
    static let adminURL = URL(string: "https://nokta-studio.onrender.com/admin")!
}

struct RootView: View {
    var onLogout: () -> Void = {}
    @State private var assistant = AssistantViewModel()
    @State private var webView = WKWebView(frame: .zero, configuration: makeNoktaWebViewConfiguration())
    @State private var isLoading = false
    @State private var canGoBack = false
    @State private var unreadAlertas = 0
    @AppStorage("noktaApariencia") private var apariencia: NoktaApariencia = .oscuro
    /// Trabajo to open directly when navigating to Trabajos from the
    /// Dashboard search; cleared whenever a sidebar row is picked.
    @State private var trabajoAbrir: String?
    /// Kept for the whole session so returning to the Dashboard is instant
    /// (no reload flash); it refreshes itself in the background on each visit.
    @State private var dashboardVM = DashboardViewModel()
    @State private var isLoggingOut = false
    @State private var logoutError: String?
    /// "Usuarios" (login accounts) is admin-only, same as the web sidebar's
    /// hidden "Administración" section — native never tracked who's logged
    /// in before, so this is the first thing that needs it.
    @State private var currentUserRole: String?
    @State private var currentUserNombre: String?
    @State private var currentUserFoto: String?
    /// If a sidebar item is tapped before the WKWebView's first load finishes
    /// (e.g. right after launch), `nav(id)` silently no-ops — the page's own
    /// router isn't defined yet — leaving the SPA on its own default page.
    /// Remember the request and replay it once loading actually finishes.
    @State private var pendingWebPage: String?

    var body: some View {
        Group {
            #if os(iOS)
            iOSShell
            #else
            macShell
            #endif
        }
        .task {
            // Mirrors admin.html's `setInterval(...,30000)` — the badge is
            // otherwise only fetched once at launch and goes stale as soon
            // as alerts are read/created anywhere (native or web).
            while !Task.isCancelled {
                await refreshUnreadAlertas()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
        .task { await loadCurrentUserRole() }
        .alert("No se pudo cerrar sesión", isPresented: Binding(get: { logoutError != nil }, set: { if !$0 { logoutError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(logoutError ?? "")
        }
    }

    private func refreshUnreadAlertas() async {
        if let alertas: [NoktaAlerta] = try? await NoktaAPI.get("/api/alertas") {
            unreadAlertas = alertas.filter { !$0.leida }.count
        }
    }

    private func loadCurrentUserRole() async {
        if let me: NoktaUsuario = try? await NoktaAPI.get("/api/admin/me") {
            currentUserRole = me.role
            currentUserNombre = me.nombre
            currentUserFoto = me.foto
        }
    }

    private var visibleGroups: [SidebarGroup] {
        currentUserRole == "admin" ? sidebarGroups : sidebarGroups.filter { $0.title != "ADMINISTRACIÓN" }
    }

    private func logout() async {
        guard !isLoggingOut else { return }
        isLoggingOut = true
        defer { isLoggingOut = false }
        do {
            try await NoktaAPI.logout()
            onLogout()
        } catch {
            logoutError = "La sesión sigue abierta. \(error.localizedDescription)"
        }
    }

    /// Programmatic navigation (Dashboard buttons/search) — same effect as
    /// picking the row in the sidebar.
    private func ir(a item: NoktaSection) {
        #if os(macOS)
        macSelection = item
        #else
        iosPath.append(item)
        #endif
        onSelect(item)
    }

    private func onSelect(_ item: NoktaSection) {
        if let pageId = item.webPageId {
            pendingWebPage = pageId
            webView.evaluateJavaScript("if (typeof nav === 'function') { nav('\(pageId)'); }")
        }
        // AlertasView reports its own count as soon as it loads (see
        // `onUnreadChange`), so no separate refresh is needed here.
    }

    @ViewBuilder
    private func detailView(for item: NoktaSection) -> some View {
        Group {
            switch item {
            case .dashboard:
                DashboardView(
                    vm: dashboardVM,
                    unreadAlertas: unreadAlertas,
                    onNavegar: { ir(a: $0) },
                    onAbrirTrabajo: { id in
                        trabajoAbrir = id
                        ir(a: .trabajos)
                    }
                )
            case .asistente: AssistantView(vm: assistant)
            case .nuevoTrabajo: NuevoTrabajoView()
            case .trabajos: TrabajosContainerView(abrir: trabajoAbrir)
            case .calendario: CalendarioView()
            case .alertas: AlertasView(onUnreadChange: { unreadAlertas = $0 })
            case .clientes: ClientesContainerView()
            case .galerias: GaleriasView()
            case .gastos: GastosView()
            case .documentos: DocumentosView()
            case .contratos: ContratosView()
            case .reportes: ReportesView()
            case .analiticas: AnaliticasView()
            case .equipo: EquipoView()
            case .usuarios: UsuariosView()
            default: webPanel
            }
        }
        // Without this, switching away from a section that owns its own
        // NavigationStack (e.g. Trabajos, mid-push into a detail row) can
        // leave that pushed content on screen under the newly-selected
        // sidebar item — NavigationSplitView doesn't always tear down a
        // nested stack's navigation state just because the branch changed.
        // Forcing a distinct identity per section guarantees a clean rebuild.
        .id(item)
        // Only the Dashboard follows the premium light/dark theme so far; the
        // rest still paint the original dark `NoktaPalette`, so keep their
        // system controls dark too until each one is redesigned.
        .environment(\.colorScheme, item == .dashboard ? currentScheme : .dark)
    }

    private var webPanel: some View {
        ZStack {
            NoktaPalette.bg.ignoresSafeArea()
            NoktaWebView(url: RootShell.adminURL, isLoading: $isLoading, canGoBack: $canGoBack, webView: webView)
                .ignoresSafeArea()
            if isLoading { ProgressView().tint(NoktaPalette.ember) }
        }
        // These sections are a single-page app inside one persistent WKWebView
        // — switching sidebar items only calls the page's own client-side
        // nav(id) router, it never refetches the page. After a server deploy
        // the running webView is still executing the OLD JS until something
        // actually reloads it, so a manual reload control is not optional here.
        .toolbar {
            ToolbarItem {
                if canGoBack {
                    Button { webView.goBack() } label: { Image(systemName: "chevron.left") }
                }
            }
            ToolbarItem {
                Button { webView.reload() } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .onChange(of: isLoading) { wasLoading, nowLoading in
            if wasLoading, !nowLoading, let pageId = pendingWebPage {
                webView.evaluateJavaScript("if (typeof nav === 'function') { nav('\(pageId)'); }")
            }
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
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        logoRow
                        ForEach(visibleGroups, id: \.title) { group in
                            if !group.title.isEmpty {
                                Text(group.title)
                                    .font(NoktaFont.poppins(10, .medium))
                                    .tracking(1.4)
                                    .foregroundStyle(NoktaTheme.textoTenue)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 18)
                                    .padding(.bottom, 6)
                            }
                            ForEach(group.items) { item in
                                Button {
                                    trabajoAbrir = nil
                                    macSelection = item
                                    onSelect(item)
                                } label: {
                                    sidebarRowLabel(item, isActive: macSelection == item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                }
                sidebarFooter
            }
            .background(NoktaTheme.fondo)
            .navigationSplitViewColumnWidth(240)
        } detail: {
            detailView(for: macSelection)
        }
    }
    #endif

    /// Pinned below the scrolling sidebar (not inside it) — the current
    /// user's name and a logout button, same spot as admin.html's
    /// sb-avatar/sb-nombre/logout-btn row.
    private var sidebarFooter: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(NoktaTheme.superficie2)
                if let fotoURL = currentUserFoto.flatMap(URL.init) {
                    AsyncImage(url: fotoURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        avatarInitial
                    }
                } else {
                    avatarInitial
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(NoktaTheme.marca, lineWidth: 1.5).padding(-3))
            .padding(3)
            VStack(alignment: .leading, spacing: 0) {
                Text(currentUserNombre ?? "—")
                    .font(NoktaFont.poppins(13, .medium)).foregroundStyle(NoktaTheme.texto)
                    .lineLimit(1)
                Text(currentUserRole == "admin" ? "Administrador" : "Editor")
                    .font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoTenue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
            aparienciaMenu
            Button { Task { await logout() } } label: {
                Image(systemName: "power").font(.system(size: 13, weight: .light))
                    .foregroundStyle(NoktaTheme.textoSuave)
                    .frame(width: 26, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Cerrar sesión")
            .disabled(isLoggingOut)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(NoktaTheme.borde).frame(height: 1) }
    }

    private var avatarInitial: some View {
        Text(String((currentUserNombre ?? "?").prefix(1)).uppercased())
            .font(NoktaFont.poppins(12, .medium)).foregroundStyle(NoktaTheme.texto)
    }

    private var currentScheme: ColorScheme {
        apariencia.colorScheme ?? systemScheme
    }
    @Environment(\.colorScheme) private var systemScheme

    /// Light / Dark / Automatic switch — persisted, applied app-wide in
    /// NoktaStudioApp via `.preferredColorScheme`.
    private var aparienciaMenu: some View {
        Menu {
            Picker("Apariencia", selection: $apariencia) {
                ForEach(NoktaApariencia.allCases) { a in
                    Label(a.label, systemImage: a.icon).tag(a)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: apariencia.icon).font(.system(size: 13, weight: .light))
                .foregroundStyle(NoktaTheme.textoSuave)
                .frame(width: 26, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Apariencia")
    }

    // MARK: - iOS: plain NavigationStack + real NavigationLink push. A
    // pushed-and-popped row doesn't retain a persistent "selected" system
    // look the way a split-view sidebar List does, so this doesn't need the
    // same workaround as macOS.
    #if os(iOS)
    @State private var iosPath: [NoktaSection] = []

    private var iOSShell: some View {
        NavigationStack(path: $iosPath) {
            List {
                logoRow
                ForEach(visibleGroups, id: \.title) { group in
                    Section {
                        ForEach(group.items) { item in
                            NavigationLink(value: item) {
                                sidebarRowLabel(item, isActive: false)
                            }
                            .listRowBackground(NoktaTheme.fondo)
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        if !group.title.isEmpty {
                            Text(group.title)
                                .font(NoktaFont.poppins(10, .medium))
                                .tracking(1.4)
                                .foregroundStyle(NoktaTheme.textoTenue)
                        }
                    }
                }
                Section {
                    Picker(selection: $apariencia) {
                        ForEach(NoktaApariencia.allCases) { a in
                            Label(a.label, systemImage: a.icon).tag(a)
                        }
                    } label: {
                        Label("Apariencia", systemImage: apariencia.icon)
                            .font(NoktaFont.poppins(13))
                            .foregroundStyle(NoktaTheme.texto)
                    }
                    .tint(NoktaTheme.textoSuave)
                    .listRowBackground(NoktaTheme.fondo)
                    .listRowSeparator(.hidden)
                    Button(role: .destructive) { Task { await logout() } } label: {
                        HStack {
                            Text("Cerrar sesión (\(currentUserNombre ?? "—"))")
                            Spacer()
                            Image(systemName: "power")
                        }
                    }
                    .disabled(isLoggingOut)
                    .listRowBackground(NoktaTheme.fondo)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(NoktaTheme.fondo)
            .navigationDestination(for: NoktaSection.self) { item in
                detailView(for: item)
                    .onAppear { onSelect(item) }
            }
            // Back at the root list: a later tap on "Trabajos" should show
            // the list, not the trabajo last opened from the Dashboard search.
            .onChange(of: iosPath) { _, path in
                if path.isEmpty { trabajoAbrir = nil }
            }
        }
    }
    #endif

    private var logoRow: some View {
        HStack(spacing: 8) {
            Circle().fill(NoktaTheme.marca).frame(width: 8, height: 8)
            HStack(spacing: 5) {
                Text("nokta").font(NoktaFont.poppins(19, .medium)).foregroundStyle(NoktaTheme.texto)
                Text("studio").font(NoktaFont.poppins(19, .light)).foregroundStyle(NoktaTheme.textoTenue)
            }
            .tracking(-0.5)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 22)
        .listRowBackground(NoktaTheme.fondo)
        .listRowSeparator(.hidden)
    }

    private func sidebarRowLabel(_ item: NoktaSection, isActive: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 15, weight: .light))
                .frame(width: 20, alignment: .center)
                .foregroundStyle(isActive ? NoktaTheme.texto : NoktaTheme.textoSuave)
            Text(item.label)
                .font(NoktaFont.poppins(13, isActive ? .medium : .regular))
                .foregroundStyle(isActive ? NoktaTheme.texto : NoktaTheme.textoSuave)
            Spacer(minLength: 0)
            if item == .alertas, unreadAlertas > 0 {
                // String(_:), not a Text("\(unreadAlertas)") literal — a direct
                // interpolated-Int Text applies locale grouping (1,234) by default.
                Text(String(unreadAlertas))
                    .font(NoktaFont.poppins(10, .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(NoktaTheme.marca, in: Capsule())
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(isActive ? NoktaTheme.superficie2 : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.18), value: isActive)
    }
}
