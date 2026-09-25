import SwiftUI
import Charts
import Combine

private struct MesDatum: Identifiable { let id = UUID(); let label: String; let monto: Double }
private struct ServicioDatum: Identifiable { let id = UUID(); let servicio: String; let monto: Double; let color: Color }

@Observable
final class DashboardViewModel {
    var trabajos: [NoktaTrabajo] = []
    var gastos: [NoktaGasto] = []
    var estados: [NoktaClienteEstado] = []
    var nombre: String?
    var mesSeleccionado: Int = Calendar.current.component(.month, from: Date()) - 1 // 0-based
    var isLoading = false
    var errorMessage: String?
    /// Today's year and 0-based month. Stored (not read from Date() on every
    /// access) so the view re-renders when `actualizarFecha()` moves them.
    private(set) var year = Calendar.current.component(.year, from: Date())
    private(set) var mesDeHoy = Calendar.current.component(.month, from: Date()) - 1

    /// Call on day change / app reactivation. When a new month (or year)
    /// starts and the user was looking at the "current" month, follow it to
    /// the new one; a month picked on purpose is left alone.
    func actualizarFecha() {
        let hoy = Date()
        let nuevoAnio = Calendar.current.component(.year, from: hoy)
        let nuevoMes = Calendar.current.component(.month, from: hoy) - 1
        guard nuevoAnio != year || nuevoMes != mesDeHoy else { return }
        if mesSeleccionado == mesDeHoy { mesSeleccionado = nuevoMes }
        year = nuevoAnio
        mesDeHoy = nuevoMes
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let t: [NoktaTrabajo] = NoktaAPI.get("/api/trabajos")
            async let g: [NoktaGasto] = NoktaAPI.get("/api/gastos")
            async let e: [NoktaClienteEstado] = NoktaAPI.get("/api/clientes-estados")
            (trabajos, gastos, estados) = try await (t, g, e)
            errorMessage = nil
        } catch is CancellationError {
            // Left the Dashboard mid-load — not a real error, keep what we have.
        } catch let e as URLError where e.code == .cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
        if nombre == nil, let me: NoktaUsuario = try? await NoktaAPI.get("/api/admin/me") {
            nombre = me.nombre
        }
    }

    var periodoMes: String { FechaUtil.periodo(anio: year, mes: mesSeleccionado + 1) }

    /// Mirrors admin.html's `periodoPrev` literally, including its January
    /// year-wrap quirk (keeps the *current* year for December when the
    /// selected month is January) — a parity port, not a fix.
    var periodoPrev: String {
        let mesPrev = mesSeleccionado == 0 ? 12 : mesSeleccionado
        return FechaUtil.periodo(anio: year, mes: mesPrev)
    }

    var ingresos: Double { IngresosCalculator.ingresosDelPeriodo(periodoMes, trabajos: trabajos) }
    var ingresosPrev: Double { IngresosCalculator.ingresosDelPeriodo(periodoPrev, trabajos: trabajos) }

    var gastosDelMes: Double {
        gastos.filter { FechaUtil.periodoDeFecha($0.fecha) == periodoMes }.reduce(0) { $0 + ($1.monto ?? 0) }
    }
    var ganancia: Double { ingresos - gastosDelMes }

    var pendiente: (monto: Double, count: Int) {
        IngresosCalculator.pendienteDelMes(periodoMes, trabajos: trabajos, estados: estados)
    }

    var pctVsMesAnterior: Double {
        guard ingresosPrev > 0 else { return 0 }
        return (ingresos - ingresosPrev) / ingresosPrev * 100
    }

    var margen: Int { ingresos > 0 ? Int(ganancia / ingresos * 100) : 0 }

    var nombreMes: String { FechaUtil.mesesCompletos[mesSeleccionado] }
    var nombreMesPrev: String { FechaUtil.mesesCompletos[(mesSeleccionado + 11) % 12] }

    /// Same four-month window admin.html's "Ingresos últimos 4 meses" chart uses.
    fileprivate var ultimosMeses: [MesDatum] {
        (0...3).reversed().map { i in
            let m = ((mesSeleccionado - i) % 12 + 12) % 12
            let y = m > mesSeleccionado ? year - 1 : year
            let periodo = FechaUtil.periodo(anio: y, mes: m + 1)
            return MesDatum(label: FechaUtil.mesesAbrev[m].capitalized, monto: IngresosCalculator.ingresosDelPeriodo(periodo, trabajos: trabajos))
        }
    }

    /// Top 4 services by amount, with everything else folded into "Otros".
    fileprivate var porServicio: [ServicioDatum] {
        let sorted = IngresosCalculator.porTipoDeServicio(trabajos)
            .filter { $0.monto > 0 }
            .sorted { $0.monto > $1.monto }
        var rows = Array(sorted.prefix(4)).map { ($0.servicio, $0.monto) }
        let resto = sorted.dropFirst(4).reduce(0) { $0 + $1.monto }
        if resto > 0 { rows.append(("Otros", resto)) }
        let colores: [Color] = [
            NoktaTheme.marca, NoktaTheme.marca.opacity(0.62), NoktaTheme.marca.opacity(0.36),
            NoktaTheme.textoTenue, NoktaTheme.borde,
        ]
        return rows.enumerated().map { ServicioDatum(servicio: $1.0, monto: $1.1, color: colores[$0 % colores.count]) }
    }

    fileprivate var ultimosTrabajos: [NoktaTrabajo] { Array(trabajos.prefix(8)) }
}

struct DashboardView: View {
    /// Owned by RootView so data survives switching sections — the view
    /// itself is rebuilt on every visit (`.id(item)` in RootView).
    @Bindable var vm: DashboardViewModel
    var unreadAlertas: Int = 0
    var onNavegar: (NoktaSection) -> Void = { _ in }
    var onAbrirTrabajo: (String) -> Void = { _ in }

    @State private var busqueda = ""
    @FocusState private var buscando: Bool
    @Namespace private var mesNS
    /// Drives the entrance animation (cards rise in, chart draws up, service
    /// bar fills). Replays on every visit — it *is* the loading transition.
    @State private var aparecio = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var compacto: Bool { sizeClass == .compact }
    #else
    private let compacto = false
    #endif
    private var anioActual: Int { vm.year }
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compacto ? 16 : 24) {
                barraSuperior.zIndex(10)
                encabezado.entrada(aparecio, 0)
                if let error = vm.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(NoktaFont.poppins(12))
                        .foregroundStyle(NoktaTheme.error)
                }
                if compacto {
                    tarjetaIngresos.entrada(aparecio, 1)
                    indicadores.entrada(aparecio, 2)
                    tarjetaServicios.entrada(aparecio, 3)
                    tarjetaUltimos.entrada(aparecio, 4)
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        tarjetaIngresos.entrada(aparecio, 1)
                        indicadores.frame(width: 300).entrada(aparecio, 2)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: 16) {
                        tarjetaServicios.frame(width: 380).entrada(aparecio, 3)
                        tarjetaUltimos.entrada(aparecio, 4)
                    }
                }
            }
            .padding(.horizontal, compacto ? 20 : 44)
            .padding(.top, compacto ? 12 : 22)
            .padding(.bottom, compacto ? 16 : 36)
            .frame(maxWidth: 1240, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(NoktaTheme.fondo)
        .scrollContentBackground(.hidden)
        #if os(iOS)
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            // No skeleton/placeholder flash: with cached data (returning visit)
            // the entrance animation starts immediately and the refresh runs
            // underneath; on the very first load the cards stay hidden until
            // data arrives and then animate in.
            vm.actualizarFecha()
            if !vm.trabajos.isEmpty { animarEntrada() }
            await vm.load()
            animarEntrada()
        }
        .refreshable { await vm.load() }
        // Midnight rollover while the app stays open, and coming back to it.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            withAnimation(.snappy) { vm.actualizarFecha() }
        }
        .onChange(of: scenePhase) { _, fase in
            if fase == .active { withAnimation(.snappy) { vm.actualizarFecha() } }
        }
    }

    private func animarEntrada() {
        guard !aparecio else { return }
        withAnimation(reduceMotion ? nil : .spring(duration: 0.7, bounce: 0.15)) { aparecio = true }
    }

    // MARK: - Header

    private var saludo: String {
        let h = Calendar.current.component(.hour, from: Date())
        let base = h < 12 ? "Buenos días" : (h < 19 ? "Buenas tardes" : "Buenas noches")
        guard let n = vm.nombre?.split(separator: " ").first else { return base }
        return "\(base), \(n)"
    }

    private var encabezado: some View {
        let titulo = VStack(alignment: .leading, spacing: 4) {
            Text(saludo)
                .font(NoktaFont.poppins(compacto ? 26 : 34, .light))
                .tracking(compacto ? -0.6 : -1)
                .foregroundStyle(NoktaTheme.texto)
            Text("Así va Nokta Studio en \(vm.nombreMes.lowercased()).")
                .font(NoktaFont.poppins(compacto ? 13 : 14))
                .foregroundStyle(NoktaTheme.textoSuave)
        }
        return Group {
            if compacto {
                VStack(alignment: .leading, spacing: 14) { titulo; selectorMes }
            } else {
                HStack(alignment: .bottom) { titulo; Spacer(); selectorMes }
            }
        }
    }

    /// The current quarter (Ene–Mar, Abr–Jun, Jul–Sep, Oct–Dic) as a
    /// segmented pill, plus a calendar menu to jump to any month of the year.
    private var mesActual: Int { vm.mesDeHoy }
    private var mesesRecientes: [Int] {
        let inicio = mesActual / 3 * 3
        return Array(inicio...(inicio + 2))
    }

    private var selectorMes: some View {
        HStack(spacing: 2) {
            ForEach(mesesRecientes, id: \.self) { i in
                let activo = vm.mesSeleccionado == i
                Button {
                    withAnimation(.snappy(duration: 0.3)) { vm.mesSeleccionado = i }
                } label: {
                    // Plain String concatenation, not a Text("...\(year)...") literal —
                    // LocalizedStringKey interpolation would format 2026 as "2,026".
                    Text(FechaUtil.mesesAbrev[i].capitalized + " " + String(anioActual))
                        .font(NoktaFont.poppins(12, activo ? .medium : .regular))
                        // Months that haven't started yet read dimmer.
                        .foregroundStyle(activo ? NoktaTheme.texto : (i > mesActual ? NoktaTheme.textoTenue : NoktaTheme.textoSuave))
                        .padding(.horizontal, compacto ? 11 : 14).padding(.vertical, 6)
                        .background {
                            if activo {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(NoktaTheme.superficie2)
                                    .matchedGeometryEffect(id: "mes", in: mesNS)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Menu {
                Picker("Mes", selection: $vm.mesSeleccionado) {
                    ForEach(0..<12, id: \.self) { i in
                        Text(FechaUtil.mesesCompletos[i] + " " + String(anioActual)).tag(i)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                let otroMes = !mesesRecientes.contains(vm.mesSeleccionado)
                HStack(spacing: 5) {
                    Image(systemName: "calendar").font(.system(size: 12, weight: .light))
                    if otroMes {
                        Text(FechaUtil.mesesAbrev[vm.mesSeleccionado].capitalized + " " + String(anioActual))
                            .font(NoktaFont.poppins(12, .medium))
                    }
                }
                .foregroundStyle(otroMes ? NoktaTheme.texto : NoktaTheme.textoSuave)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background {
                    if otroMes {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(NoktaTheme.superficie2)
                            .matchedGeometryEffect(id: "mes", in: mesNS)
                    }
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Elegir otro mes")
        }
        .padding(3)
        .background(NoktaTheme.superficie, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(NoktaTheme.borde, lineWidth: 1))
        .fixedSize()
    }

    // MARK: - Barra superior (buscador, alertas, nuevo trabajo)

    private var barraSuperior: some View {
        HStack(spacing: 10) {
            if !compacto {
                Text("Resumen").font(NoktaFont.poppins(13)).foregroundStyle(NoktaTheme.textoSuave)
                Spacer(minLength: 16)
                buscador.frame(width: 300)
            } else {
                buscador
            }
            botonCampana
            botonNuevo
        }
    }

    private var resultados: [NoktaTrabajo] {
        let q = busqueda.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return Array(vm.trabajos.filter {
            $0.cliente.range(of: q, options: opts) != nil || $0.servicio.range(of: q, options: opts) != nil
        }.prefix(6))
    }

    private var buscador: some View {
        let forma = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .light))
                .foregroundStyle(NoktaTheme.textoTenue)
            TextField("", text: $busqueda, prompt: Text("Buscar trabajos o clientes…").foregroundStyle(NoktaTheme.textoTenue))
                .textFieldStyle(.plain)
                .font(NoktaFont.poppins(12))
                .foregroundStyle(NoktaTheme.texto)
                .focused($buscando)
                .onSubmit { if let t = resultados.first { abrir(t) } }
                #if os(macOS)
                .onExitCommand { busqueda = ""; buscando = false }
                #endif
            if !busqueda.isEmpty {
                Button { busqueda = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                        .foregroundStyle(NoktaTheme.textoTenue)
                }
                .buttonStyle(.plain)
            } else if !compacto {
                Text("⌘K").font(NoktaFont.poppins(10, .medium)).foregroundStyle(NoktaTheme.textoSuave)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(NoktaTheme.superficie2, in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(NoktaTheme.superficie, in: forma)
        .overlay(forma.strokeBorder(buscando ? NoktaTheme.marca.opacity(0.6) : NoktaTheme.borde, lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: buscando)
        .overlay(alignment: .topTrailing) {
            if !busqueda.isEmpty {
                listaResultados
                    .offset(y: 46)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: busqueda.isEmpty)
        .background {
            // ⌘K focuses the search field from anywhere on the Dashboard.
            Button("") { buscando = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
        }
    }

    private var listaResultados: some View {
        VStack(alignment: .leading, spacing: 0) {
            if resultados.isEmpty {
                Text("Sin resultados para “\(busqueda)”")
                    .font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoTenue)
                    .padding(12)
            } else {
                ForEach(resultados, id: \.id) { t in
                    Button { abrir(t) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "briefcase").font(.system(size: 13, weight: .light))
                                .foregroundStyle(NoktaTheme.textoSuave)
                                .frame(width: 30, height: 30)
                                .background(NoktaTheme.superficie2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 0) {
                                Text(t.cliente).font(NoktaFont.poppins(12, .medium)).foregroundStyle(NoktaTheme.texto).lineLimit(1)
                                Text("\(t.servicio) · \(FechaUtil.fechaCorta(t.fecha))")
                                    .font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoTenue).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Text(dinero(t.monto ?? 0)).font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoSuave)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(6)
        .frame(width: compacto ? nil : 360, alignment: .leading)
        .frame(maxWidth: compacto ? .infinity : nil, alignment: .leading)
        .background(NoktaTheme.superficie, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(NoktaTheme.borde, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
    }

    private func abrir(_ t: NoktaTrabajo) {
        busqueda = ""
        buscando = false
        onAbrirTrabajo(t.id)
    }

    private var botonCampana: some View {
        Button { onNavegar(.alertas) } label: {
            Image(systemName: "bell").font(.system(size: 14, weight: .light))
                .foregroundStyle(NoktaTheme.textoSuave)
                .frame(width: 36, height: 36)
                .background(NoktaTheme.superficie, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(NoktaTheme.borde, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if unreadAlertas > 0 {
                        // String(_:) — an interpolated Int in Text would get locale grouping.
                        Text(unreadAlertas > 9 ? "9+" : String(unreadAlertas))
                            .font(NoktaFont.poppins(9, .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).frame(minWidth: 17, minHeight: 17)
                            .background(NoktaTheme.marca, in: Capsule())
                            .offset(x: 6, y: -6)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Alertas")
    }

    private var botonNuevo: some View {
        Button { onNavegar(.nuevoTrabajo) } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                if !compacto { Text("Nuevo trabajo").font(NoktaFont.poppins(12, .medium)) }
            }
            .foregroundStyle(NoktaTheme.fondo)
            .padding(.horizontal, compacto ? 11 : 14)
            .frame(height: 36)
            .background(NoktaTheme.texto, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Nuevo trabajo")
    }

    // MARK: - Ingresos (hero)

    private var tarjetaIngresos: some View {
        VStack(alignment: .leading, spacing: 0) {
            etiqueta("INGRESOS DEL MES")
            HStack(alignment: .center, spacing: 14) {
                Text(dinero(vm.ingresos))
                    .font(NoktaFont.poppins(compacto ? 44 : 56, .light))
                    .tracking(compacto ? -1.5 : -2.5)
                    .foregroundStyle(NoktaTheme.texto)
                    .contentTransition(.numericText(value: vm.ingresos))
                    .lineLimit(1).minimumScaleFactor(0.6)
                if vm.ingresosPrev > 0 { variacion }
            }
            .padding(.top, 6)
            Text(vm.ingresos > 0 ? "Cobrado en \(vm.nombreMes.lowercased())" : "Aún sin cobros este mes")
                .font(NoktaFont.poppins(12))
                .foregroundStyle(NoktaTheme.textoSuave)
                .padding(.top, 2)
            curvaIngresos
                .frame(height: compacto ? 130 : 170)
                .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .noktaCard(padding: compacto ? 20 : 28)
        .animation(.snappy, value: vm.mesSeleccionado)
    }

    private var variacion: some View {
        let sube = vm.pctVsMesAnterior >= 0
        let color = sube ? NoktaTheme.exito : NoktaTheme.error
        return HStack(spacing: 4) {
            Image(systemName: sube ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 10, weight: .semibold))
            Text("\(abs(Int(vm.pctVsMesAnterior)))% vs \(vm.nombreMesPrev.lowercased())")
                .font(NoktaFont.poppins(11, .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
        .fixedSize()
    }

    /// Plotted on a numeric 0...3 index (not category labels) so the curve
    /// runs edge to edge — category axes center each point in its band and
    /// leave half-band gaps at both ends, which made the line look cut off.
    private var curvaIngresos: some View {
        let datos = vm.ultimosMeses
        let factor = aparecio ? 1.0 : 0.0
        let ultimo = datos.count - 1
        return Chart {
            ForEach(Array(datos.enumerated()), id: \.offset) { i, d in
                AreaMark(x: .value("Mes", i), y: .value("Monto", d.monto * factor))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [NoktaTheme.marca.opacity(0.24), NoktaTheme.marca.opacity(0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                LineMark(x: .value("Mes", i), y: .value("Monto", d.monto * factor))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(NoktaTheme.marca)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if let d = datos.last {
                PointMark(x: .value("Mes", ultimo), y: .value("Monto", d.monto * factor))
                    .symbol {
                        Circle()
                            .fill(NoktaTheme.superficie)
                            .overlay(Circle().strokeBorder(NoktaTheme.marca, lineWidth: 2.5))
                            .frame(width: 12, height: 12)
                    }
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...(max(datos.map(\.monto).max() ?? 0, 1) * 1.2))
        .chartXScale(domain: 0...max(ultimo, 1), range: .plotDimension(padding: 6))
        .chartXAxis {
            AxisMarks(values: Array(0...max(ultimo, 0))) { v in
                if let i = v.as(Int.self), datos.indices.contains(i) {
                    AxisValueLabel(anchor: i == 0 ? .topLeading : (i == ultimo ? .topTrailing : .top)) {
                        Text(datos[i].label)
                            .font(NoktaFont.poppins(11, i == ultimo ? .medium : .regular))
                            .foregroundStyle(i == ultimo ? NoktaTheme.textoSuave : NoktaTheme.textoTenue)
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.9), value: aparecio)
        .animation(.snappy, value: vm.mesSeleccionado)
    }

    // MARK: - Indicadores

    private var indicadores: some View {
        let items = VStack(spacing: compacto ? 10 : 16) {
            indicador(
                icono: "chart.line.uptrend.xyaxis", titulo: "Ganancia neta",
                valor: vm.ganancia, detalle: "\(vm.margen)% de margen"
            )
            indicador(
                icono: "clock", titulo: "Por cobrar", valor: vm.pendiente.monto,
                detalle: "\(vm.pendiente.count) trabajo\(vm.pendiente.count == 1 ? "" : "s") pendiente\(vm.pendiente.count == 1 ? "" : "s")",
                acento: vm.pendiente.monto > 0
            )
            indicador(
                icono: "calendar", titulo: "Mes pasado", valor: vm.ingresosPrev,
                detalle: vm.ingresosPrev > 0 ? "Cobrado en \(vm.nombreMesPrev.lowercased())" : "Sin ingresos en \(vm.nombreMesPrev.lowercased())"
            )
        }
        return items
    }

    private func indicador(icono: String, titulo: String, valor: Double, detalle: String, acento: Bool = false) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icono)
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(acento ? NoktaTheme.aviso : NoktaTheme.textoSuave)
                .frame(width: 40, height: 40)
                .background(acento ? NoktaTheme.avisoSuave : NoktaTheme.superficie2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(titulo).font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoSuave)
                Text(dinero(valor))
                    .font(NoktaFont.poppins(22))
                    .tracking(-0.6)
                    .foregroundStyle(acento ? NoktaTheme.aviso : NoktaTheme.texto)
                    .contentTransition(.numericText(value: valor))
                    .animation(.snappy, value: valor)
                Text(detalle).font(NoktaFont.poppins(11))
                    .foregroundStyle(acento ? NoktaTheme.aviso.opacity(0.85) : NoktaTheme.textoTenue)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .noktaCard(padding: compacto ? 16 : 20)
    }

    // MARK: - Por servicio

    private var tarjetaServicios: some View {
        let datos = vm.porServicio
        let total = datos.reduce(0) { $0 + $1.monto }
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Por servicio").font(NoktaFont.poppins(14, .medium)).foregroundStyle(NoktaTheme.texto)
                Spacer()
                Text("Histórico").font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoTenue)
            }
            if datos.isEmpty {
                vacio("Sin trabajos registrados")
            } else {
                GeometryReader { geo in
                    let espacio = CGFloat(datos.count - 1) * 3
                    HStack(spacing: 3) {
                        ForEach(datos) { d in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(d.color)
                                .frame(width: max(4, (geo.size.width - espacio) * d.monto / total * (aparecio ? 1 : 0)))
                        }
                    }
                    .animation(reduceMotion ? nil : .spring(duration: 0.9, bounce: 0.1).delay(0.25), value: aparecio)
                }
                .frame(height: 10)
                VStack(spacing: 12) {
                    ForEach(datos) { d in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 2).fill(d.color).frame(width: 8, height: 8)
                            Text(d.servicio).font(NoktaFont.poppins(13)).foregroundStyle(NoktaTheme.texto).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(dinero(d.monto)).font(NoktaFont.poppins(13)).foregroundStyle(NoktaTheme.textoSuave)
                            Text("\(Int((d.monto / total * 100).rounded()))%")
                                .font(NoktaFont.poppins(13, .medium)).foregroundStyle(NoktaTheme.texto)
                                .frame(width: 42, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .noktaCard(padding: compacto ? 20 : 24)
    }

    // MARK: - Últimos trabajos

    private var tarjetaUltimos: some View {
        let lista = compacto ? Array(vm.ultimosTrabajos.prefix(5)) : vm.ultimosTrabajos
        return VStack(alignment: .leading, spacing: 6) {
            Text("Últimos trabajos").font(NoktaFont.poppins(14, .medium)).foregroundStyle(NoktaTheme.texto)
                .padding(.bottom, 6)
            if lista.isEmpty {
                vacio("No hay trabajos registrados")
            } else {
                ForEach(Array(lista.enumerated()), id: \.element.id) { i, t in
                    if i > 0 { Rectangle().fill(NoktaTheme.borde).frame(height: 1) }
                    filaTrabajo(t)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .noktaCard(padding: compacto ? 20 : 24)
    }

    private func filaTrabajo(_ t: NoktaTrabajo) -> some View {
        let est = estadoDe(t)
        let iniciales = t.cliente.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        return HStack(spacing: 14) {
            Text(iniciales.isEmpty ? "·" : iniciales)
                .font(NoktaFont.poppins(11, .medium))
                .foregroundStyle(NoktaTheme.textoSuave)
                .frame(width: 34, height: 34)
                .background(NoktaTheme.superficie2, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(t.cliente).font(NoktaFont.poppins(13, .medium)).foregroundStyle(NoktaTheme.texto).lineLimit(1)
                Text("\(t.servicio) · \(FechaUtil.fechaCorta(t.fecha))")
                    .font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoTenue).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(dinero(t.monto ?? 0)).font(NoktaFont.poppins(14)).tracking(-0.3).foregroundStyle(NoktaTheme.texto)
                if compacto { estado(est) }
            }
            if !compacto { estado(est).frame(width: 96, alignment: .trailing) }
        }
        .padding(.vertical, 10)
    }

    /// Same rule as TrabajosListView's `estadoPill`: monthly contracts
    /// (grupo B) and "Clases" show the client relationship (Activo /
    /// Pausado / Cancelado); one-off jobs show Pagado / Pendiente.
    private func estadoDe(_ t: NoktaTrabajo) -> (texto: String, color: Color) {
        if t.grupoResuelto == "B" || t.servicio == "Clases" {
            let er = vm.estados.first { $0.nombre == t.cliente }?.estado ?? "activo"
            let color = er == "activo" ? NoktaTheme.exito : er == "pausado" ? NoktaTheme.aviso : NoktaTheme.error
            return (ESTADO_CLIENTE_LABEL[er] ?? er.capitalized, color)
        }
        return t.estado == "pagado" ? ("Pagado", NoktaTheme.exito) : ("Pendiente", NoktaTheme.aviso)
    }

    private func estado(_ e: (texto: String, color: Color)) -> some View {
        HStack(spacing: 6) {
            Circle().fill(e.color).frame(width: 6, height: 6)
            Text(e.texto).font(NoktaFont.poppins(compacto ? 10 : 12))
        }
        .foregroundStyle(e.color)
    }

    // MARK: - Helpers

    private func etiqueta(_ texto: String) -> some View {
        Text(texto).font(NoktaFont.poppins(10, .medium)).tracking(1.4).foregroundStyle(NoktaTheme.textoTenue)
    }

    private func vacio(_ texto: String) -> some View {
        Text(texto)
            .font(NoktaFont.poppins(13)).foregroundStyle(NoktaTheme.textoTenue)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
    }

    /// "$4,850" for whole amounts, "$4,850.50" when there are cents.
    private func dinero(_ v: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.minimumFractionDigits = v.rounded() == v ? 0 : 2
        f.maximumFractionDigits = 2
        return "$" + (f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v))
    }
}

private extension View {
    /// Staggered rise-and-fade entrance; `orden` sets the delay step.
    func entrada(_ visible: Bool, _ orden: Int) -> some View {
        opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 14)
            .animation(.spring(duration: 0.6, bounce: 0.12).delay(Double(orden) * 0.06), value: visible)
    }
}
