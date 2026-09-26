import SwiftUI
import Charts

/// Analíticas ("Tablero claro", 2026-09). Usa los mismos criterios de dinero
/// que el Dashboard y Trabajos: ingresos del mes = IngresosCalculator
/// (quincenas y clases pagadas, trabajos fechados en el mes); cobrado y por
/// cobrar = IngresosCalculator.cobrado / porCobrar.
private struct MesDatum: Identifiable { let id: Int; let mes: String; let monto: Double }

@Observable
final class AnaliticasViewModel {
    var trabajos: [NoktaTrabajo] = []
    var estados: [NoktaClienteEstado] = []
    var anio = Calendar.current.component(.year, from: Date())
    var isLoading = true

    func load() async {
        isLoading = true
        defer { isLoading = false }
        async let t: [NoktaTrabajo]? = try? NoktaAPI.get("/api/trabajos")
        async let e: [NoktaClienteEstado]? = try? NoktaAPI.get("/api/clientes-estados")
        let (tt, ee) = await (t, e)
        trabajos = tt ?? []; estados = ee ?? []
    }

    private static let mesesAbrev = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]

    /// Años con algún movimiento, más el actual.
    var aniosDisponibles: [Int] {
        var s = Set([Calendar.current.component(.year, from: Date())])
        for t in trabajos {
            for f in [t.fecha, t.fechaInicio] { if let am = FechaUtil.anioMes(f) { s.insert(am.anio) } }
            for q in t.quincenas ?? [] { if let am = FechaUtil.anioMes(q.periodo + "-01") { s.insert(am.anio) } }
            for x in t.sesiones ?? [] { if let am = FechaUtil.anioMes(x.fecha) { s.insert(am.anio) } }
        }
        return s.sorted()
    }

    private func periodo(_ mes: Int) -> String { FechaUtil.periodo(anio: anio, mes: mes) }

    fileprivate var porMes: [MesDatum] {
        (1...12).map { m in MesDatum(id: m, mes: Self.mesesAbrev[m - 1], monto: IngresosCalculator.ingresosDelPeriodo(periodo(m), trabajos: trabajos)) }
    }

    var totalAnio: Double { porMes.reduce(0) { $0 + $1.monto } }
    var mesesConIngreso: Int { porMes.filter { $0.monto > 0 }.count }
    var promedioMensual: Double { mesesConIngreso == 0 ? 0 : totalAnio / Double(mesesConIngreso) }
    fileprivate var mejorMes: MesDatum? { porMes.filter { $0.monto > 0 }.max { $0.monto < $1.monto } }

    var cobradoTotal: Double { trabajos.reduce(0) { $0 + IngresosCalculator.cobrado($1) } }
    var porCobrarTotal: Double { trabajos.reduce(0) { $0 + IngresosCalculator.porCobrar($1, estados: estados) } }
    var tasaDeCobro: Int? {
        let base = cobradoTotal + porCobrarTotal
        return base > 0 ? Int((cobradoTotal / base * 100).rounded()) : nil
    }

    /// Ingreso del año por trabajo (suma de sus 12 meses).
    private func ingresoAnual(_ t: NoktaTrabajo) -> Double {
        (1...12).reduce(0) { $0 + IngresosCalculator.ingresosDelPeriodo(periodo($1), trabajos: [t]) }
    }

    var porServicio: [(servicio: String, monto: Double)] {
        var tot: [String: Double] = [:]
        for t in trabajos { tot[t.servicio, default: 0] += ingresoAnual(t) }
        return tot.filter { $0.value > 0 }.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    var mejoresClientes: [(cliente: String, detalle: String, monto: Double)] {
        var tot: [String: Double] = [:]
        var servicios: [String: String] = [:]
        for t in trabajos {
            tot[t.cliente, default: 0] += ingresoAnual(t)
            servicios[t.cliente] = servicios[t.cliente] ?? t.servicio
        }
        return tot.filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(5).map { n, v in
            let ts = trabajos.filter { $0.cliente == n }
            let contrato = ts.contains { $0.grupoResuelto == "B" || $0.servicio == "Clases" || !($0.sesiones ?? []).isEmpty }
            let er = (estados.first { $0.nombre == n }?.estado ?? "activo").lowercased()
            let estado = contrato ? (ESTADO_CLIENTE_LABEL[er] ?? er).lowercased() : (ts.allSatisfy { $0.estado == "pagado" } ? "pagado" : "pendiente")
            return (n, "\(servicios[n] ?? "") · \(estado)", v)
        }
    }
}

struct AnaliticasView: View {
    @State private var vm = AnaliticasViewModel()
    @State private var seleccion: String?
    @State private var aparecio = false
    @State private var crecer = false
    @State private var cargado = false
    @State private var ancho: CGFloat = 1000

    private var ancha: Bool { ancho >= 900 }
    private let paleta: [Color] = [NoktaTheme.marca, NoktaTheme.exito, NoktaTheme.aviso, NoktaPalette.blue, NoktaTheme.error, NoktaTheme.textoSuave]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                NoktaEncabezado(titulo: "Analíticas", subtitulo: "Cómo va tu negocio en \(String(vm.anio))") {
                    if vm.aniosDisponibles.count > 1 {
                        NoktaChips(opciones: vm.aniosDisponibles.map { ($0, String($0)) }, seleccion: $vm.anio)
                    }
                }
                .noktaEntrada(aparecio, 0)

                if !cargado {
                    esqueleto
                } else {
                let fila1 = ancha
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                fila1 {
                    ganado.frame(maxWidth: .infinity).noktaEntrada(aparecio, 1)
                    indicadores.frame(width: ancha ? 250 : nil).frame(maxWidth: ancha ? 250 : .infinity).noktaEntrada(aparecio, 2)
                }

                let fila2 = ancha
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                fila2 {
                    servicios.frame(maxWidth: .infinity).noktaEntrada(aparecio, 3)
                    clientes.frame(maxWidth: .infinity).noktaEntrada(aparecio, 4)
                }
                }
            }
            .padding(.horizontal, ancho < 600 ? 20 : 40)
            .padding(.vertical, ancho < 600 ? 16 : 32)
            .frame(maxWidth: 1240, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(NoktaTheme.fondo)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { ancho = $0 }
        .task {
            await vm.load()
            // Primero llegan los datos; luego entran las tarjetas en cascada y
            // después crecen las barras y cuentan los números (nada "salta").
            cargado = true
            withAnimation(.spring(duration: 0.6, bounce: 0.12)) { aparecio = true }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.spring(duration: 1.1, bounce: 0.05)) { crecer = true }
        }
        .refreshable { await vm.load() }
        .onChange(of: vm.anio) {
            crecer = false
            withAnimation(.spring(duration: 0.9, bounce: 0.05).delay(0.05)) { crecer = true }
        }
    }

    /// Mismo acomodo que la pantalla real, con brillo mientras cargan los datos.
    private var esqueleto: some View {
        let caja = { (h: CGFloat) in
            RoundedRectangle(cornerRadius: NoktaTheme.radioTarjeta, style: .continuous)
                .fill(NoktaTheme.superficie).frame(height: h).modifier(NoktaBrillo())
        }
        let f1 = ancha ? AnyLayout(HStackLayout(alignment: .top, spacing: 16)) : AnyLayout(VStackLayout(spacing: 16))
        return VStack(spacing: 18) {
            f1 {
                caja(360).frame(maxWidth: .infinity)
                VStack(spacing: 12) { caja(112); caja(112); caja(112) }.frame(width: ancha ? 250 : nil).frame(maxWidth: ancha ? 250 : .infinity)
            }
            f1 { caja(170).frame(maxWidth: .infinity); caja(170).frame(maxWidth: .infinity) }
        }
        .transition(.opacity)
    }

    private func etiqueta(_ t: String) -> some View {
        Text(t).font(NoktaFont.poppins(10, .medium)).tracking(1.4).foregroundStyle(NoktaTheme.textoTenue)
    }

    // MARK: Ganado en el año (barras)

    private var ganado: some View {
        let datos = vm.porMes
        let mejor = vm.mejorMes
        return VStack(alignment: .leading, spacing: 4) {
            etiqueta("GANADO EN \(String(vm.anio))")
            Text(NoktaFormato.dinero(crecer ? vm.totalAnio : 0))
                .font(NoktaFont.poppins(46, .light)).tracking(-2.2)
                .foregroundStyle(NoktaTheme.texto)
                .contentTransition(.numericText(value: crecer ? vm.totalAnio : 0))
            Text(vm.mesesConIngreso == 0 ? "Sin ingresos registrados este año" : "\(vm.mesesConIngreso) mes\(vm.mesesConIngreso == 1 ? "" : "es") con ingresos · pasa el cursor por una barra")
                .font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoSuave)
            Chart(datos) { d in
                BarMark(x: .value("Mes", d.mes), y: .value("Ingreso", crecer ? d.monto : 0), width: .ratio(0.62))
                    .foregroundStyle(
                        d.monto > 0
                        ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.878, green: 0.541, blue: 0.361), Color(red: 0.72, green: 0.32, blue: 0.157)], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(NoktaTheme.superficie2)
                    )
                    .cornerRadius(6)
                    .opacity(seleccion == nil || seleccion == d.mes ? 1 : 0.45)
                    .annotation(position: .top, spacing: 4) {
                        if crecer && (seleccion == d.mes || (seleccion == nil && d.id == mejor?.id)) {
                            Text(NoktaFormato.dinero(d.monto))
                                .font(NoktaFont.poppins(11, .medium))
                                .foregroundStyle(d.id == mejor?.id ? NoktaTheme.marca : NoktaTheme.texto)
                        }
                    }
            }
            .chartXSelection(value: $seleccion)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { v in
                    AxisValueLabel { if let s = v.as(String.self) { Text(s).font(NoktaFont.poppins(10)).foregroundStyle(NoktaTheme.textoTenue) } }
                }
            }
            .chartYScale(domain: 0...max(vm.porMes.map(\.monto).max() ?? 0, 1) * 1.15)
            .frame(height: 210)
            .padding(.top, 14)
        }
        .padding(22)
        .noktaCard()
    }

    // MARK: Indicadores

    private var indicadores: some View {
        VStack(spacing: 12) {
            kpi("PROMEDIO MENSUAL", NoktaFormato.dinero(vm.promedioMensual), NoktaTheme.texto, "en los meses con ingresos")
            kpi("MEJOR MES", vm.mejorMes.map { FechaUtil.mesesCompletos[$0.id - 1] } ?? "—", NoktaTheme.marca,
                vm.mejorMes.map { NoktaFormato.dinero($0.monto) + " cobrados" } ?? "todavía sin ingresos")
            kpi("TASA DE COBRO", vm.tasaDeCobro.map { "\($0)%" } ?? "—", NoktaTheme.exito,
                "\(NoktaFormato.dinero(vm.cobradoTotal)) cobrado · \(NoktaFormato.dinero(vm.porCobrarTotal)) por cobrar")
        }
    }

    private func kpi(_ t: String, _ v: String, _ c: Color, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            etiqueta(t)
            Text(v).font(NoktaFont.poppins(26, .light)).tracking(-1).foregroundStyle(c).lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(sub).font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoSuave).lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .noktaCard()
    }

    // MARK: De dónde viene tu dinero

    private var servicios: some View {
        let datos = vm.porServicio
        let total = max(datos.reduce(0) { $0 + $1.monto }, 1)
        return VStack(alignment: .leading, spacing: 14) {
            etiqueta("DE DÓNDE VIENE TU DINERO")
            if datos.isEmpty {
                Text("Sin ingresos este año").font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoTenue)
            }
            ForEach(Array(datos.enumerated()), id: \.element.servicio) { i, d in
                let c = paleta[i % paleta.count]
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(d.servicio).foregroundStyle(NoktaTheme.texto)
                        Spacer()
                        Text("\(NoktaFormato.dinero(d.monto)) · \(Int((d.monto / total * 100).rounded()))%").foregroundStyle(NoktaTheme.textoSuave)
                    }
                    .font(NoktaFont.poppins(12.5))
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(NoktaTheme.superficie2)
                            Capsule().fill(c)
                                .frame(width: crecer ? g.size.width * d.monto / total : 0)
                                .animation(.spring(duration: 1, bounce: 0).delay(0.15 + Double(i) * 0.1), value: crecer)
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .noktaCard()
    }

    // MARK: Mejores clientes

    private var clientes: some View {
        let datos = vm.mejoresClientes
        return VStack(alignment: .leading, spacing: 4) {
            etiqueta("TUS MEJORES CLIENTES").padding(.bottom, 8)
            if datos.isEmpty {
                Text("Sin ingresos este año").font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoTenue)
            }
            ForEach(Array(datos.enumerated()), id: \.element.cliente) { i, c in
                HStack(spacing: 12) {
                    NoktaAvatar(nombre: c.cliente, tamano: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.cliente).font(NoktaFont.poppins(13, .medium)).foregroundStyle(NoktaTheme.texto).lineLimit(1)
                        Text(c.detalle).font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoTenue).lineLimit(1)
                    }
                    Spacer()
                    Text(NoktaFormato.dinero(c.monto)).font(NoktaFont.poppins(14)).foregroundStyle(NoktaTheme.texto)
                }
                .padding(.vertical, 8)
                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(NoktaTheme.borde).frame(height: 1) } }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .noktaCard()
    }
}
