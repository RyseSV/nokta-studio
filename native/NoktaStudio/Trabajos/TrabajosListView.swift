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

    /// "cobrar" (te debe algo ahora), "aldia" (activo y sin deuda) o
    /// "inactivo" (contrato/clases de un cliente pausado o cancelado).
    func situacion(_ t: NoktaTrabajo) -> String {
        let esContrato = t.grupoResuelto == "B" || t.servicio == "Clases" || !(t.sesiones ?? []).isEmpty
        if esContrato {
            let rel = (estados.first { $0.nombre == t.cliente }?.estado ?? t.estadoContrato ?? "activo").lowercased()
            if rel != "activo" { return "inactivo" }
        }
        return IngresosCalculator.porCobrar(t, estados: estados) > 0 ? "cobrar" : "aldia"
    }

    /// Solo los tipos que existen, con cuántos hay de cada uno.
    var gruposPresentes: [(valor: String, texto: String)] {
        ["A", "B", "C", "D", "E"].compactMap { g in
            let n = trabajos.filter { $0.grupoResuelto == g }.count
            return n > 0 ? (g, "\(ServicioGrupoMap.nombres[g] ?? g) \(n)") : nil
        }
    }

    var filtrados: [NoktaTrabajo] {
        let q = busqueda.trimmingCharacters(in: .whitespaces)
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return trabajos.filter { t in
            (filtroGrupo.isEmpty || t.grupoResuelto == filtroGrupo) &&
            (filtroEstado.isEmpty || situacion(t) == filtroEstado) &&
            (q.isEmpty || t.cliente.range(of: q, options: opts) != nil || t.servicio.range(of: q, options: opts) != nil)
        }
    }
}

struct TrabajosContainerView: View {
    @State private var selectedId: String?

    /// `abrir`: jump straight into one trabajo's detail (used by the
    /// Dashboard search); Back still returns to the list.
    private let onNuevo: (() -> Void)?

    init(abrir: String? = nil, onNuevo: (() -> Void)? = nil) {
        _selectedId = State(initialValue: abrir)
        self.onNuevo = onNuevo
    }

    var body: some View {
        if let id = selectedId {
            TrabajoDetailView(trabajoId: id, onBack: { selectedId = nil })
        } else {
            TrabajosListView(onSelect: { selectedId = $0 }, onNuevo: onNuevo)
        }
    }
}

struct TrabajosListView: View {
    @State private var vm = TrabajosListViewModel()
    var onSelect: (String) -> Void = { _ in }
    var onNuevo: (() -> Void)?
    @State private var aparecio = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var compacto: Bool { sizeClass == .compact }
    #else
    private let compacto = false
    #endif

    private var cobrado: Double { vm.filtrados.reduce(0) { $0 + IngresosCalculator.cobrado($1) } }
    private var porCobrar: Double { vm.filtrados.reduce(0) { $0 + IngresosCalculator.porCobrar($1, estados: vm.estados) } }
    private var conSaldo: Int { vm.filtrados.filter { vm.situacion($0) == "cobrar" }.count }
    private var enCurso: Int { vm.filtrados.filter { vm.situacion($0) != "inactivo" }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compacto ? 18 : 26) {
                NoktaEncabezado(
                    titulo: "Trabajos",
                    subtitulo: vm.trabajos.isEmpty && vm.isLoading ? "Cargando tus trabajos…"
                        : "\(vm.filtrados.count) trabajo\(vm.filtrados.count == 1 ? "" : "s")" + (vm.filtrados.count != vm.trabajos.count ? " de \(vm.trabajos.count)" : "")
                ) {
                    NoktaBuscador(texto: $vm.busqueda, placeholder: "Buscar cliente o servicio…")
                        .frame(maxWidth: compacto ? .infinity : 260)
                    if let onNuevo {
                        Button(action: onNuevo) { Label("Nuevo trabajo", systemImage: "plus") }
                            .buttonStyle(NoktaBotonPrimario())
                    }
                }
                .noktaEntrada(aparecio, 0)

                indicadores.noktaEntrada(aparecio, 1)

                filtros.noktaEntrada(aparecio, 2)

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
            TarjetaTotal(icono: "checkmark.circle", titulo: "Cobrado", valor: NoktaFormato.dinero(cobrado),
                         detalle: "Lo que ya te pagaron", color: NoktaTheme.exito)
            TarjetaTotal(icono: "clock", titulo: "Por cobrar", valor: NoktaFormato.dinero(porCobrar),
                         detalle: conSaldo == 0 ? "Nadie te debe ahora" : "\(conSaldo) trabajo\(conSaldo == 1 ? "" : "s") con pago pendiente",
                         color: porCobrar > 0 ? NoktaTheme.aviso : NoktaTheme.textoSuave)
            TarjetaTotal(icono: "sparkles", titulo: "En curso", valor: "\(enCurso)",
                         detalle: enCurso == vm.filtrados.count ? "Todos activos" : "\(vm.filtrados.count - enCurso) en pausa o cancelado",
                         color: NoktaTheme.marca)
        }
        return Group {
            if compacto { VStack(spacing: 10) { items } } else { HStack(spacing: 14) { items } }
        }
    }

    private var filtros: some View {
        let tipos = NoktaChips(opciones: [("", "Todos")] + vm.gruposPresentes, seleccion: $vm.filtroGrupo)
        let estado = NoktaChips(opciones: [("", "Todos"), ("cobrar", "Por cobrar"), ("aldia", "Al día"), ("inactivo", "Pausados y cancelados")],
                                seleccion: $vm.filtroEstado)
        return Group {
            if compacto {
                VStack(alignment: .leading, spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) { tipos }
                    ScrollView(.horizontal, showsIndicators: false) { estado }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { tipos; Spacer(minLength: 12); estado }
                    VStack(alignment: .leading, spacing: 10) { tipos; estado }
                }
            }
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
                        TarjetaTrabajo(trabajo: t, estado: NoktaEstadoTrabajo.de(t, estados: vm.estados), estados: vm.estados, aparecio: aparecio)
                    }
                    .buttonStyle(.plain)
                    .noktaEntrada(aparecio, 4 + i)
                }
            }
            .animation(.snappy(duration: 0.35), value: vm.filtrados.map(\.id))
        }
    }

    private var columnas: [GridItem] {
        [GridItem(.adaptive(minimum: compacto ? 280 : 280, maximum: 460), spacing: 16)]
    }
}

/// Estilo 5 ("Foco que sigue al cursor"): el estado va en la pastilla y en
/// una luz que sigue al puntero por el borde y el fondo (en reposo, un brillo
/// suave arriba al centro). El dinero protagonista es lo ya cobrado, "de" el
/// total; abajo, lo que sigue con ese trabajo.
private struct TarjetaTrabajo: View {
    let trabajo: NoktaTrabajo
    let estado: (texto: String, color: Color)
    let estados: [NoktaClienteEstado]
    let aparecio: Bool

    private var sesiones: [NoktaSesion] { trabajo.sesiones ?? [] }
    private var esMensual: Bool { trabajo.grupoResuelto == "B" }
    private var cobrado: Double { IngresosCalculator.cobrado(trabajo) }

    /// "de $120" / "cobrado · $250 al mes" / "de $325"
    private var deCuanto: String {
        if esMensual { return "cobrado · " + NoktaFormato.dinero(trabajo.pagoMensual ?? trabajo.monto ?? 0) + " al mes" }
        if !sesiones.isEmpty { return "de " + NoktaFormato.dinero(sesiones.reduce(0) { $0 + ($1.monto ?? 0) }) }
        return "de " + NoktaFormato.dinero(trabajo.monto ?? 0)
    }

    /// Lo que sigue: (etiqueta, detalle resaltado).
    private var siguiente: (String, String) {
        let relacion = (estados.first { $0.nombre == trabajo.cliente }?.estado ?? trabajo.estadoContrato ?? "activo").lowercased()
        if esMensual || !sesiones.isEmpty, relacion != "activo" {
            return ("Contrato", relacion == "pausado" ? "en pausa" : "cancelado")
        }
        if !sesiones.isEmpty {
            let pendientes = sesiones.filter { $0.estado != "pagado" && $0.estado != "oculta" && $0.estado != "cancelado" }
            guard let prox = pendientes.min(by: { $0.fecha < $1.fecha }) else { return ("Clases", "todas pagadas ✓") }
            return ("Próxima clase", Self.diaCorto(prox.fecha) + " · " + NoktaFormato.dinero(prox.monto ?? 0))
        }
        if esMensual {
            let debe = IngresosCalculator.porCobrar(trabajo, estados: estados)
            return debe > 0 ? ("Por cobrar este mes", NoktaFormato.dinero(debe)) : ("Este mes", "al día ✓")
        }
        let saldo = IngresosCalculator.porCobrar(trabajo, estados: estados)
        if saldo <= 0 { return ("Cobrado", "completo ✓") }
        let fecha = trabajo.fechaEntrega ?? trabajo.fecha
        return ("Falta cobrar", NoktaFormato.dinero(saldo) + (fecha.map { " · " + Self.diaCorto($0) } ?? ""))
    }

    private var detalle: String {
        if !sesiones.isEmpty { return "\(trabajo.servicio) · \(sesiones.count) sesion\(sesiones.count == 1 ? "" : "es")" }
        if esMensual { return "\(trabajo.servicio) · Mensual" }
        return "\(trabajo.servicio) · \(FechaUtil.fechaCorta(trabajo.fecha))"
    }

    var body: some View {
        let c = estado.color
        let sig = siguiente
        VStack(alignment: .leading, spacing: 0) {
            NoktaEstado(texto: estado.texto, color: c, tamano: 11)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(c.opacity(0.12), in: Capsule())
            Spacer(minLength: 26)
            Text(trabajo.cliente)
                .font(NoktaFont.poppins(15, .medium)).foregroundStyle(NoktaTheme.texto)
                .lineLimit(1)
            Text(detalle)
                .font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoTenue).lineLimit(1).padding(.top, 2)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(NoktaFormato.dinero(cobrado))
                    .font(NoktaFont.poppins(34, .light)).tracking(-1.6)
                    .foregroundStyle(NoktaTheme.texto)
                Text(deCuanto)
                    .font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoTenue).lineLimit(1)
            }
            .padding(.top, 12)
            (Text(sig.0 + " · ").foregroundStyle(NoktaTheme.textoSuave) + Text(sig.1).foregroundStyle(c))
                .font(NoktaFont.poppins(11))
                .lineLimit(1)
                .padding(.top, 8)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .leading)
        .noktaFoco(c, radio: 20)
    }

    private static func diaCorto(_ iso: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: String(iso.prefix(10))) else { return FechaUtil.fechaCorta(iso) }
        f.dateFormat = "EEE d MMM"
        return f.string(from: d).replacingOccurrences(of: ".", with: "")
    }
}

/// Total de arriba con el mismo "foco que sigue al cursor" que las tarjetas.
private struct TarjetaTotal: View {
    let icono: String
    let titulo: String
    let valor: String
    let detalle: String
    let color: Color

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icono)
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoSuave)
                Text(valor)
                    .font(NoktaFont.poppins(26, .light)).tracking(-1)
                    .foregroundStyle(NoktaTheme.texto)
                    .contentTransition(.numericText())
                Text(detalle).font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoTenue).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .noktaFoco(color, radio: 18)
    }
}
