import SwiftUI

@Observable
final class TrabajosListViewModel {
    var trabajos: [NoktaTrabajo] = []
    var estados: [NoktaClienteEstado] = []
    var filtroGrupo: String = ""
    var filtroEstado: String = ""
    var busqueda: String = ""
    var isLoading = false

    func load() async {
        isLoading = true
        defer { isLoading = false }
        async let t: [NoktaTrabajo]? = try? NoktaAPI.get("/api/trabajos")
        async let e: [NoktaClienteEstado]? = try? NoktaAPI.get("/api/clientes-estados")
        if let t = await t { trabajos = t }
        if let e = await e { estados = e }
    }

    func estadoRelacion(_ cliente: String) -> String {
        estados.first { $0.nombre == cliente }?.estado ?? "activo"
    }

    var filtrados: [NoktaTrabajo] {
        let q = busqueda.trimmingCharacters(in: .whitespaces)
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return trabajos.filter { t in
            (filtroGrupo.isEmpty || t.grupoResuelto == filtroGrupo) &&
            (filtroEstado.isEmpty || t.estado == filtroEstado) &&
            (q.isEmpty || t.cliente.range(of: q, options: opts) != nil || t.servicio.range(of: q, options: opts) != nil)
        }
    }
}

struct TrabajosContainerView: View {
    @State private var selectedId: String?

    /// `abrir`: jump straight into one trabajo's detail (used by the
    /// Dashboard search); Back still returns to the list.
    init(abrir: String? = nil) {
        _selectedId = State(initialValue: abrir)
    }

    var body: some View {
        if let id = selectedId {
            TrabajoDetailView(trabajoId: id, onBack: { selectedId = nil })
        } else {
            TrabajosListView(onSelect: { selectedId = $0 })
        }
    }
}

struct TrabajosListView: View {
    @State private var vm = TrabajosListViewModel()
    var onSelect: (String) -> Void = { _ in }
    @State private var aparecio = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var compacto: Bool { sizeClass == .compact }
    #else
    private let compacto = false
    #endif

    private var facturado: Double { vm.filtrados.reduce(0) { $0 + ($1.monto ?? 0) } }
    private var porCobrar: Double { vm.filtrados.reduce(0) { $0 + max(0, $1.saldo ?? 0) } }
    private var conSaldo: Int { vm.filtrados.filter { ($0.saldo ?? 0) > 0 }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compacto ? 16 : 24) {
                NoktaEncabezado(
                    titulo: "Trabajos",
                    subtitulo: vm.trabajos.isEmpty && vm.isLoading ? "Cargando tus trabajos…"
                        : "\(vm.filtrados.count) trabajo\(vm.filtrados.count == 1 ? "" : "s")" + (vm.filtrados.count != vm.trabajos.count ? " de \(vm.trabajos.count)" : "")
                ) {
                    NoktaBuscador(texto: $vm.busqueda, placeholder: "Buscar cliente o servicio…")
                        .frame(maxWidth: compacto ? .infinity : 280)
                }
                .noktaEntrada(aparecio, 0)

                indicadores.noktaEntrada(aparecio, 1)

                VStack(alignment: .leading, spacing: 10) {
                    NoktaChips(
                        opciones: [("", "Todos")] + ["A", "B", "C", "D", "E"].map { ($0, ServicioGrupoMap.nombres[$0] ?? $0) },
                        seleccion: $vm.filtroGrupo
                    )
                    NoktaChips(opciones: [("", "Todos los estados"), ("pendiente", "Pendiente"), ("pagado", "Pagado")], seleccion: $vm.filtroEstado)
                }
                .noktaEntrada(aparecio, 2)

                lista.noktaEntrada(aparecio, 3)
            }
            .padding(.horizontal, compacto ? 20 : 44)
            .padding(.vertical, compacto ? 16 : 36)
            .frame(maxWidth: 1240, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(NoktaTheme.fondo)
        .scrollContentBackground(.hidden)
        #if os(iOS)
        .navigationTitle("Trabajos")
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            withAnimation(.spring(duration: 0.6, bounce: 0.12)) { aparecio = true }
            await vm.load()
        }
        .refreshable { await vm.load() }
    }

    private var indicadores: some View {
        let items = Group {
            NoktaIndicador(icono: "doc.text", titulo: "Facturado", valor: facturado, detalle: "Suma de los trabajos mostrados")
            NoktaIndicador(icono: "clock", titulo: "Saldo por cobrar", valor: porCobrar,
                           detalle: "\(conSaldo) trabajo\(conSaldo == 1 ? "" : "s") con saldo", acento: porCobrar > 0 ? NoktaTheme.aviso : nil)
        }
        return Group {
            if compacto { VStack(spacing: 10) { items } } else { HStack(spacing: 16) { items } }
        }
    }

    @ViewBuilder
    private var lista: some View {
        if vm.trabajos.isEmpty && vm.isLoading {
            LazyVGrid(columns: columnas, spacing: 16) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(NoktaTheme.superficie)
                        .frame(height: 210).modifier(NoktaBrillo())
                }
            }
        } else if vm.filtrados.isEmpty {
            NoktaVacio(
                icono: vm.trabajos.isEmpty ? "briefcase" : "line.3.horizontal.decrease.circle",
                titulo: vm.trabajos.isEmpty ? "Aún no hay trabajos" : "Nada coincide con los filtros",
                detalle: vm.trabajos.isEmpty ? "Cuando registres un trabajo aparecerá aquí." : "Prueba con otro filtro o búsqueda."
            )
            .noktaCard()
        } else {
            LazyVGrid(columns: columnas, spacing: 16) {
                ForEach(Array(vm.filtrados.enumerated()), id: \.element.id) { i, t in
                    Button { onSelect(t.id) } label: {
                        TarjetaTrabajo(trabajo: t, estado: NoktaEstadoTrabajo.de(t, estados: vm.estados), aparecio: aparecio)
                    }
                    .buttonStyle(.plain)
                    .noktaEntrada(aparecio, 4 + i)
                }
            }
            .animation(.snappy(duration: 0.35), value: vm.filtrados.map(\.id))
        }
    }

    private var columnas: [GridItem] {
        [GridItem(.adaptive(minimum: compacto ? 280 : 250, maximum: 420), spacing: 16)]
    }
}

/// Option A ("Tarjetas con progreso"): one card per trabajo. At rest it's
/// neutral (hairline frame, grey icon); on hover the frame lights up in the
/// status color (green / yellow / red) and the card lifts.
private struct TarjetaTrabajo: View {
    let trabajo: NoktaTrabajo
    let estado: (texto: String, color: Color)
    let aparecio: Bool
    @State private var encima = false
    @State private var lleno = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    /// Share of the amount already collected: (monto − saldo) / monto.
    private var cobrado: Double {
        let monto = trabajo.monto ?? 0
        guard monto > 0 else { return trabajo.estado == "pagado" ? 1 : 0 }
        if let saldo = trabajo.saldo { return min(1, max(0, (monto - saldo) / monto)) }
        return trabajo.estado == "pagado" ? 1 : 0
    }
    private var esContrato: Bool { trabajo.grupoResuelto == "B" || trabajo.servicio == "Clases" }

    private var icono: String {
        let s = trabajo.servicio.lowercased()
        if s.contains("video") || s.contains("edición") { return "video" }
        if s.contains("redes") || s.contains("social") || s.contains("community") { return "iphone" }
        if s.contains("boda") || s.contains("foto") || s.contains("sesión") { return "camera" }
        if s.contains("evento") || s.contains("fiesta") { return "party.popper" }
        if s.contains("brand") || s.contains("logo") || s.contains("diseño") { return "sparkles" }
        if s.contains("clase") { return "graduationcap" }
        return "briefcase"
    }

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: 20, style: .continuous)
        let c = estado.color
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: icono)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(NoktaTheme.textoSuave)
                    .frame(width: 38, height: 38)
                    .background(NoktaTheme.superficie2, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Spacer()
                NoktaEstado(texto: estado.texto, color: c, tamano: 11)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(c.opacity(0.1), in: Capsule())
            }
            Text(trabajo.cliente)
                .font(NoktaFont.poppins(15, .medium)).foregroundStyle(NoktaTheme.texto)
                .lineLimit(1).padding(.top, 16)
            Text(esContrato ? "\(trabajo.servicio) · Mensual" : "\(trabajo.servicio) · \(FechaUtil.fechaCorta(trabajo.fecha))")
                .font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoTenue).lineLimit(1).padding(.top, 2)
            Text(NoktaFormato.dinero(esContrato ? (trabajo.pagoMensual ?? trabajo.monto ?? 0) : (trabajo.monto ?? 0)))
                .font(NoktaFont.poppins(30, .light)).tracking(-1.2)
                .foregroundStyle(NoktaTheme.texto)
                .padding(.top, 14)
            if esContrato {
                Text("por mes").font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoTenue)
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(NoktaTheme.texto.opacity(0.07))
                        Capsule()
                            .fill(LinearGradient(colors: [c, c.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * (lleno ? cobrado : 0))
                    }
                }
                .frame(height: 5)
                .padding(.top, 12)
                HStack {
                    Text("Cobrado \(Int((cobrado * 100).rounded()))%")
                    Spacer()
                    Text(cobrado < 1 ? "Saldo " + NoktaFormato.dinero(max(0, trabajo.saldo ?? 0)) : "Completo")
                }
                .font(NoktaFont.poppins(10)).foregroundStyle(NoktaTheme.textoTenue)
                .padding(.top, 6)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .bottomTrailing) {
                forma.fill(NoktaTheme.superficie)
                // Soft glow in the status color, bottom-right corner.
                Circle()
                    .fill(c.opacity(scheme == .dark ? 0.14 : 0.09))
                    .frame(width: 200, height: 200)
                    .blur(radius: 60)
                    .offset(x: 70, y: 90)
                    .opacity(encima ? 1 : 0.6)
            }
            .clipShape(forma)
        }
        .overlay(forma.strokeBorder(encima ? c.opacity(0.8) : NoktaTheme.borde, lineWidth: encima ? 1.5 : 1))
        .shadow(color: c.opacity(encima ? 0.25 : 0), radius: 18, y: 8)
        .shadow(color: .black.opacity(encima ? 0.25 : 0.08), radius: encima ? 20 : 8, y: encima ? 12 : 3)
        .offset(y: encima ? -5 : 0)
        .contentShape(forma)
        .onHover { h in withAnimation(.spring(duration: 0.35, bounce: 0.3)) { encima = h } }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(duration: 1.1, bounce: 0).delay(0.35)) { lleno = true }
        }
    }
}
