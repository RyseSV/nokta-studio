import SwiftUI
import Charts

private let gastoCategorias = ["Equipo", "Transporte", "Software", "Marketing", "Otros"]

/// Icono y color de cada categoría (mismos en la dona, la lista y el registro rápido).
private enum CategoriaGasto {
    static func icono(_ c: String) -> String {
        switch c {
        case "Equipo": "camera"
        case "Transporte": "car"
        case "Software": "desktopcomputer"
        case "Marketing": "megaphone"
        default: "ellipsis"
        }
    }
    static func color(_ c: String) -> Color {
        switch c {
        case "Equipo": NoktaTheme.marca
        case "Transporte": NoktaPalette.blue
        case "Software": NoktaTheme.exito
        case "Marketing": NoktaTheme.aviso
        default: NoktaTheme.textoSuave
        }
    }
}

@Observable
final class GastosViewModel {
    var gastos: [NoktaGasto] = []
    var trabajos: [NoktaTrabajo] = []
    var filtroMes = ""
    var filtroCategoria = ""
    var rango = 6
    var isLoading = true
    var errorMessage: String?

    func load() async {
        isLoading = true
        defer { isLoading = false }
        async let g: [NoktaGasto]? = try? NoktaAPI.get("/api/gastos")
        async let t: [NoktaTrabajo]? = try? NoktaAPI.get("/api/trabajos")
        let (gg, tt) = await (g, t)
        gastos = (gg ?? []).sorted { $0.fecha > $1.fecha }
        trabajos = tt ?? []
    }

    static var periodoActual: String { IngresosCalculator.periodoActual }

    /// Los últimos `n` meses terminando en el actual ("2026-04" … "2026-09").
    func periodos(_ n: Int) -> [String] {
        let cal = Calendar(identifier: .gregorian)
        let hoy = Date()
        return (0..<n).reversed().compactMap { k in
            guard let d = cal.date(byAdding: .month, value: -k, to: hoy) else { return nil }
            return FechaUtil.periodo(anio: cal.component(.year, from: d), mes: cal.component(.month, from: d))
        }
    }

    func gastado(_ periodo: String) -> Double {
        gastos.filter { FechaUtil.periodoDeFecha($0.fecha) == periodo }.reduce(0) { $0 + ($1.monto ?? 0) }
    }
    /// Mismo criterio de ingresos que el Dashboard.
    func ganado(_ periodo: String) -> Double {
        IngresosCalculator.ingresosDelPeriodo(periodo, trabajos: trabajos)
    }

    var mesesDisponibles: [String] {
        Array(Set(gastos.compactMap { FechaUtil.periodoDeFecha($0.fecha) })).sorted(by: >)
    }

    var filtrados: [NoktaGasto] {
        gastos.filter { g in
            (filtroMes.isEmpty || FechaUtil.periodoDeFecha(g.fecha) == filtroMes) &&
            (filtroCategoria.isEmpty || g.categoria == filtroCategoria)
        }
    }

    /// Gasto del mes actual por categoría, de mayor a menor.
    var porCategoria: [(categoria: String, monto: Double)] {
        let p = Self.periodoActual
        return gastoCategorias.map { c in
            (c, gastos.filter { $0.categoria == c && FechaUtil.periodoDeFecha($0.fecha) == p }.reduce(0) { $0 + ($1.monto ?? 0) })
        }
        .filter { $0.1 > 0 }
        .sorted { $0.1 > $1.1 }
    }

    func guardar(concepto: String, categoria: String, monto: Double, fecha: String) async -> Bool {
        struct Body: Encodable { let concepto: String; let categoria: String; let monto: Double; let fecha: String }
        struct Resp: Decodable { let ok: Bool? }
        errorMessage = nil
        do {
            let _: Resp = try await NoktaAPI.post("/api/gastos", body: Body(concepto: concepto, categoria: categoria, monto: monto, fecha: fecha))
            await load()
            return true
        } catch {
            errorMessage = "No se pudo registrar el gasto. \(error.localizedDescription)"
            return false
        }
    }

    func eliminar(_ id: String) async {
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp? = try? await NoktaAPI.delete("/api/gastos/\(id)")
        await load()
    }
}

struct GastosView: View {
    @State private var vm = GastosViewModel()
    @State private var concepto = ""
    @State private var categoria = gastoCategorias[0]
    @State private var monto = ""
    @State private var fecha = Date()
    @State private var errorLocal: String?
    @State private var eliminarConfirm: String?
    @State private var seleccion: String?
    @State private var resaltado: String?
    @State private var aparecio = false
    @State private var ancho: CGFloat = 1000
    @FocusState private var focoConcepto: Bool

    private var ancha: Bool { ancho >= 900 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                NoktaEncabezado(titulo: "Gastos", subtitulo: "Así va tu dinero") {
                    NoktaChips(opciones: [(3, "3 meses"), (6, "6 meses"), (12, "12 meses")], seleccion: $vm.rango)
                }
                .noktaEntrada(aparecio, 0)

                let fila1 = ancha
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                fila1 {
                    grafica.frame(maxWidth: .infinity).noktaEntrada(aparecio, 1)
                    indicadores.frame(width: ancha ? 250 : nil).frame(maxWidth: ancha ? 250 : .infinity).noktaEntrada(aparecio, 2)
                }

                let fila2 = ancha
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                fila2 {
                    dona.frame(width: ancha ? 250 : nil).frame(maxWidth: ancha ? 250 : .infinity).noktaEntrada(aparecio, 3)
                    lista.frame(maxWidth: .infinity).noktaEntrada(aparecio, 4)
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
            withAnimation(.spring(duration: 0.6, bounce: 0.12)) { aparecio = true }
            await vm.load()
        }
        .refreshable { await vm.load() }
        .alert("¿Eliminar este gasto?", isPresented: Binding(get: { eliminarConfirm != nil }, set: { if !$0 { eliminarConfirm = nil } })) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar", role: .destructive) {
                if let id = eliminarConfirm { Task { await vm.eliminar(id) } }
            }
        }
    }

    // MARK: Gráfica ingresos vs gastos

    private struct Punto: Identifiable { let mes: String; let periodo: String; let serie: String; let valor: Double; var id: String { periodo + serie } }

    private func etiquetaMes(_ periodo: String) -> String {
        guard let am = FechaUtil.anioMes(periodo) else { return periodo }
        return FechaUtil.mesesAbrev[am.mes - 1]
    }

    private var grafica: some View {
        let ps = vm.periodos(vm.rango)
        let puntos = ps.flatMap { p in
            [Punto(mes: etiquetaMes(p), periodo: p, serie: "Ingresos", valor: vm.ganado(p)),
             Punto(mes: etiquetaMes(p), periodo: p, serie: "Gastos", valor: vm.gastado(p))]
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                leyenda("Ingresos", NoktaTheme.exito)
                leyenda("Gastos", NoktaTheme.error)
                Spacer()
                Text("Pasa el cursor por un mes").font(NoktaFont.poppins(10.5)).foregroundStyle(NoktaTheme.textoTenue)
            }
            Chart {
                ForEach(puntos.filter { $0.serie == "Ingresos" }) { p in
                    AreaMark(x: .value("Mes", p.mes), y: .value("Monto", p.valor))
                        .foregroundStyle(LinearGradient(colors: [NoktaTheme.exito.opacity(0.22), NoktaTheme.exito.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                }
                ForEach(puntos) { p in
                    LineMark(x: .value("Mes", p.mes), y: .value("Monto", p.valor), series: .value("Serie", p.serie))
                        .foregroundStyle(p.serie == "Ingresos" ? NoktaTheme.exito : NoktaTheme.error)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                }
                if let sel = seleccion, let p = ps.first(where: { etiquetaMes($0) == sel }) {
                    RuleMark(x: .value("Mes", sel))
                        .foregroundStyle(NoktaTheme.texto.opacity(0.18))
                        .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            tooltip(p)
                        }
                    PointMark(x: .value("Mes", sel), y: .value("Monto", vm.ganado(p))).foregroundStyle(NoktaTheme.exito).symbolSize(60)
                    PointMark(x: .value("Mes", sel), y: .value("Monto", vm.gastado(p))).foregroundStyle(NoktaTheme.error).symbolSize(60)
                }
            }
            .chartXSelection(value: $seleccion)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                    AxisGridLine().foregroundStyle(NoktaTheme.borde)
                    AxisValueLabel { if let d = v.as(Double.self) { Text(NoktaFormato.dinero(d)).font(NoktaFont.poppins(9)).foregroundStyle(NoktaTheme.textoTenue) } }
                }
            }
            .chartXAxis {
                AxisMarks { v in
                    AxisValueLabel { if let s = v.as(String.self) { Text(s).font(NoktaFont.poppins(10)).foregroundStyle(NoktaTheme.textoTenue) } }
                }
            }
            .frame(height: 220)
            .animation(.spring(duration: 0.5), value: vm.rango)
        }
        .padding(20)
        .noktaCard()
    }

    private func tooltip(_ p: String) -> some View {
        let g = vm.ganado(p), s = vm.gastado(p)
        return VStack(alignment: .leading, spacing: 4) {
            Text(etiquetaMesLargo(p)).font(NoktaFont.poppins(11, .medium)).foregroundStyle(NoktaTheme.texto)
            filaTip("Ganaste", g, NoktaTheme.exito)
            filaTip("Gastaste", s, NoktaTheme.error)
            filaTip("Te quedó", g - s, NoktaTheme.texto)
        }
        .padding(10)
        .background(NoktaTheme.superficie2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(NoktaTheme.borde))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
    }

    private func filaTip(_ t: String, _ v: Double, _ c: Color) -> some View {
        HStack(spacing: 14) {
            Text(t).foregroundStyle(NoktaTheme.textoSuave)
            Spacer(minLength: 0)
            Text(NoktaFormato.dinero(v)).foregroundStyle(c)
        }
        .font(NoktaFont.poppins(10.5))
        .frame(width: 130)
    }

    private func etiquetaMesLargo(_ periodo: String) -> String {
        guard let am = FechaUtil.anioMes(periodo) else { return periodo }
        return "\(FechaUtil.mesesCompletos[am.mes - 1]) \(am.anio)"
    }

    private func leyenda(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(c).frame(width: 14, height: 3)
            Text(t).font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoSuave)
        }
    }

    // MARK: Indicadores del mes

    private var indicadores: some View {
        let ps = vm.periodos(2)
        let ant = ps.first ?? "", act = ps.last ?? ""
        let gAct = vm.gastado(act), gAnt = vm.gastado(ant)
        let iAct = vm.ganado(act), iAnt = vm.ganado(ant)
        let mesAnt = etiquetaMesLargo(ant).split(separator: " ").first.map(String.init)?.lowercased() ?? ""
        let mesAct = FechaUtil.mesesAbrev[(FechaUtil.anioMes(act)?.mes ?? 1) - 1]
        return VStack(spacing: 12) {
            kpi("GASTADO · \(mesAct.uppercased())", NoktaFormato.dinero(gAct), NoktaTheme.error,
                comparacion(gAct, gAnt, mesAnt, subirEsBueno: false))
            kpi("GANADO · \(mesAct.uppercased())", NoktaFormato.dinero(iAct), NoktaTheme.exito,
                comparacion(iAct, iAnt, mesAnt, subirEsBueno: true))
            kpi("TE QUEDÓ", NoktaFormato.dinero(iAct - gAct), NoktaTheme.texto,
                (iAct > 0 ? "margen \(Int(((iAct - gAct) / iAct * 100).rounded()))%" : "sin ingresos este mes", NoktaTheme.textoSuave))
        }
    }

    private func comparacion(_ a: Double, _ b: Double, _ mes: String, subirEsBueno: Bool) -> (String, Color) {
        guard b > 0 else { return (a > 0 ? "primer mes con datos" : "sin datos", NoktaTheme.textoTenue) }
        let pct = Int(((a - b) / b * 100).rounded())
        if pct == 0 { return ("igual que \(mes)", NoktaTheme.textoSuave) }
        let sube = pct > 0
        return ("\(sube ? "↑" : "↓") \(abs(pct))% vs \(mes)", sube == subirEsBueno ? NoktaTheme.exito : NoktaTheme.error)
    }

    private func kpi(_ t: String, _ v: String, _ c: Color, _ sub: (String, Color)) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(t).font(NoktaFont.poppins(10, .medium)).tracking(1.2).foregroundStyle(NoktaTheme.textoTenue)
            Text(v).font(NoktaFont.poppins(26, .light)).tracking(-1).foregroundStyle(c)
                .contentTransition(.numericText())
            Text(sub.0).font(NoktaFont.poppins(11)).foregroundStyle(sub.1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .noktaCard()
    }

    // MARK: En qué se va (dona)

    private var dona: some View {
        let datos = vm.porCategoria
        let total = datos.reduce(0) { $0 + $1.monto }
        return VStack(alignment: .leading, spacing: 14) {
            Text("EN QUÉ SE VA").font(NoktaFont.poppins(10, .medium)).tracking(1.4).foregroundStyle(NoktaTheme.textoTenue)
            ZStack {
                if datos.isEmpty {
                    Circle().strokeBorder(NoktaTheme.superficie2, lineWidth: 18)
                } else {
                    Chart(datos, id: \.categoria) { d in
                        SectorMark(angle: .value("Monto", d.monto), innerRadius: .ratio(0.68), angularInset: 1.5)
                            .foregroundStyle(CategoriaGasto.color(d.categoria))
                            .cornerRadius(3)
                            .opacity(vm.filtroCategoria.isEmpty || vm.filtroCategoria == d.categoria ? 1 : 0.3)
                    }
                    .chartLegend(.hidden)
                }
                VStack(spacing: 0) {
                    Text(NoktaFormato.dinero(total)).font(NoktaFont.poppins(18, .light)).foregroundStyle(NoktaTheme.texto)
                    Text(FechaUtil.mesesAbrev[(FechaUtil.anioMes(GastosViewModel.periodoActual)?.mes ?? 1) - 1])
                        .font(NoktaFont.poppins(10)).foregroundStyle(NoktaTheme.textoTenue)
                }
            }
            .frame(width: 150, height: 150)
            .frame(maxWidth: .infinity)
            VStack(spacing: 2) {
                if datos.isEmpty {
                    Text("Sin gastos este mes").font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoTenue)
                        .frame(maxWidth: .infinity)
                }
                ForEach(datos, id: \.categoria) { d in
                    Button {
                        withAnimation(.spring(duration: 0.3)) { vm.filtroCategoria = vm.filtroCategoria == d.categoria ? "" : d.categoria }
                    } label: {
                        HStack(spacing: 8) {
                            Circle().fill(CategoriaGasto.color(d.categoria)).frame(width: 8, height: 8)
                            Text(d.categoria).foregroundStyle(NoktaTheme.textoSuave)
                            Spacer()
                            Text(NoktaFormato.dinero(d.monto)).foregroundStyle(NoktaTheme.texto)
                        }
                        .font(NoktaFont.poppins(11.5))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(vm.filtroCategoria == d.categoria ? NoktaTheme.superficie2 : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Filtrar la lista por \(d.categoria)")
                }
            }
        }
        .padding(18)
        .noktaCard()
    }

    // MARK: Lista + registro rápido

    private var lista: some View {
        VStack(alignment: .leading, spacing: 12) {
            registroRapido
            if let e = errorLocal ?? vm.errorMessage {
                Label(e, systemImage: "exclamationmark.circle").font(NoktaFont.poppins(11.5)).foregroundStyle(NoktaTheme.error)
            }
            HStack(spacing: 8) {
                Menu {
                    Button("Todos los meses") { vm.filtroMes = "" }
                    ForEach(vm.mesesDisponibles, id: \.self) { p in Button(etiquetaMesLargo(p)) { vm.filtroMes = p } }
                } label: { filtroEtiqueta(vm.filtroMes.isEmpty ? "Todos los meses" : etiquetaMesLargo(vm.filtroMes)) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                Menu {
                    Button("Todas las categorías") { vm.filtroCategoria = "" }
                    ForEach(gastoCategorias, id: \.self) { c in Button(c) { vm.filtroCategoria = c } }
                } label: { filtroEtiqueta(vm.filtroCategoria.isEmpty ? "Todas las categorías" : vm.filtroCategoria) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                Spacer()
                Text("\(vm.filtrados.count) gasto\(vm.filtrados.count == 1 ? "" : "s")").font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoTenue)
            }
            if vm.filtrados.isEmpty {
                NoktaVacio(icono: "creditcard", titulo: vm.isLoading ? "Cargando…" : (vm.gastos.isEmpty ? "Aún no hay gastos" : "Nada con esos filtros"),
                           detalle: vm.gastos.isEmpty ? "Registra el primero en la barra de arriba." : nil)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(grupos, id: \.titulo) { grupo in
                        Text(grupo.titulo).font(NoktaFont.poppins(10, .medium)).tracking(1.4).foregroundStyle(NoktaTheme.textoTenue)
                            .padding(.top, 10).padding(.bottom, 4)
                        ForEach(grupo.gastos, id: \.id) { g in fila(g) }
                    }
                }
                .animation(.spring(duration: 0.4), value: vm.filtrados.map(\.id))
            }
        }
        .padding(18)
        .noktaCard()
    }

    private func filtroEtiqueta(_ t: String) -> some View {
        HStack(spacing: 6) {
            Text(t)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
        }
        .font(NoktaFont.poppins(11.5)).foregroundStyle(NoktaTheme.textoSuave)
        .padding(.horizontal, 12).frame(height: 30)
        .background(NoktaTheme.superficie2, in: Capsule())
        .contentShape(Capsule())
    }

    private var registroRapido: some View {
        let forma = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { camposRapidos }
            VStack(alignment: .leading, spacing: 8) {
                campoConcepto
                HStack(spacing: 8) { categoriasRapidas; campoMonto; campoFecha; botonRegistrar }
            }
        }
        .padding(8)
        .background(NoktaTheme.superficie2.opacity(0.6), in: forma)
        .overlay(forma.strokeBorder(focoConcepto ? NoktaTheme.marca.opacity(0.5) : NoktaTheme.borde))
        .animation(.easeOut(duration: 0.2), value: focoConcepto)
    }

    @ViewBuilder private var camposRapidos: some View {
        campoConcepto; categoriasRapidas; campoMonto; campoFecha; botonRegistrar
    }

    private func cajita<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        c()
            .textFieldStyle(.plain)
            .font(NoktaFont.poppins(12.5)).foregroundStyle(NoktaTheme.texto)
            .padding(.horizontal, 10).frame(height: 34)
            .background(NoktaTheme.superficie, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var campoConcepto: some View {
        cajita {
            TextField("", text: $concepto, prompt: Text("¿En qué gastaste?").foregroundStyle(NoktaTheme.textoTenue))
                .focused($focoConcepto)
                .onSubmit { Task { await guardar() } }
        }
        .frame(minWidth: 180, maxWidth: .infinity)
    }

    private var categoriasRapidas: some View {
        HStack(spacing: 4) {
            ForEach(gastoCategorias, id: \.self) { c in
                let on = categoria == c
                Button { withAnimation(.spring(duration: 0.25)) { categoria = c } } label: {
                    Image(systemName: CategoriaGasto.icono(c))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(on ? Color.black.opacity(0.8) : NoktaTheme.textoTenue)
                        .frame(width: 30, height: 30)
                        .background(on ? CategoriaGasto.color(c) : NoktaTheme.superficie, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(c)
            }
        }
    }

    private var campoMonto: some View {
        cajita {
            HStack(spacing: 3) {
                Text("$").foregroundStyle(NoktaTheme.textoSuave)
                TextField("", text: $monto, prompt: Text("0.00").foregroundStyle(NoktaTheme.textoTenue))
                    .onSubmit { Task { await guardar() } }
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
            }
        }
        .frame(width: 90)
    }

    private var campoFecha: some View {
        DatePicker("", selection: $fecha, displayedComponents: .date)
            .labelsHidden().datePickerStyle(.compact)
            .environment(\.locale, Locale(identifier: "es"))
            .fixedSize()
    }

    private var botonRegistrar: some View {
        Button { Task { await guardar() } } label: {
            Text("Registrar")
                .font(NoktaFont.poppins(12, .medium)).foregroundStyle(.white)
                .padding(.horizontal, 14).frame(height: 34)
                .background(LinearGradient(colors: [Color(red: 0.855, green: 0.478, blue: 0.282), Color(red: 0.72, green: 0.32, blue: 0.157)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private struct Grupo { let titulo: String; let gastos: [NoktaGasto] }

    /// Hoy / Ayer / Esta semana / por mes.
    private var grupos: [Grupo] {
        let cal = Calendar.current
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        let hoy = cal.startOfDay(for: Date())
        var orden: [String] = []
        var dict: [String: [NoktaGasto]] = [:]
        for g in vm.filtrados {
            let d = f.date(from: String(g.fecha.prefix(10))).map { cal.startOfDay(for: $0) }
            let dias = d.map { cal.dateComponents([.day], from: $0, to: hoy).day ?? 99 } ?? 99
            let titulo: String
            if dias == 0 { titulo = "HOY" }
            else if dias == 1 { titulo = "AYER" }
            else if dias >= 0 && dias < 7 { titulo = "ESTA SEMANA" }
            else { titulo = etiquetaMesLargo(FechaUtil.periodoDeFecha(g.fecha) ?? "").uppercased() }
            if dict[titulo] == nil { orden.append(titulo) }
            dict[titulo, default: []].append(g)
        }
        return orden.map { Grupo(titulo: $0, gastos: dict[$0] ?? []) }
    }

    private func fila(_ g: NoktaGasto) -> some View {
        let c = CategoriaGasto.color(g.categoria)
        let nuevo = resaltado == g.id
        return HStack(spacing: 12) {
            Image(systemName: CategoriaGasto.icono(g.categoria))
                .font(.system(size: 12, weight: .medium)).foregroundStyle(c)
                .frame(width: 32, height: 32)
                .background(c.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(g.concepto).font(NoktaFont.poppins(13, .medium)).foregroundStyle(NoktaTheme.texto).lineLimit(1)
                Text("\(g.categoria) · \(FechaUtil.fechaCorta(g.fecha))").font(NoktaFont.poppins(10.5)).foregroundStyle(NoktaTheme.textoTenue)
            }
            Spacer()
            Text("−" + NoktaFormato.dinero(g.monto ?? 0)).font(NoktaFont.poppins(13)).foregroundStyle(NoktaTheme.texto)
            Button { eliminarConfirm = g.id } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(NoktaTheme.textoTenue)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Eliminar gasto")
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(nuevo ? NoktaTheme.marca.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .noktaHover(radio: 10)
        .overlay(alignment: .top) { Rectangle().fill(NoktaTheme.borde).frame(height: 1).padding(.horizontal, 8) }
    }

    private func guardar() async {
        errorLocal = nil
        guard !concepto.trimmingCharacters(in: .whitespaces).isEmpty else { errorLocal = "Escribe en qué gastaste"; focoConcepto = true; return }
        let limpio = monto.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
        guard let m = Double(limpio), m > 0 else { errorLocal = "Escribe el monto"; return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        let fechaStr = f.string(from: fecha)
        let c = concepto.trimmingCharacters(in: .whitespaces)
        guard await vm.guardar(concepto: c, categoria: categoria, monto: m, fecha: fechaStr) else { return }
        // Destello en el gasto recién creado.
        if let nuevo = vm.gastos.first(where: { $0.concepto == c && $0.monto == m && $0.fecha.hasPrefix(fechaStr) }) {
            withAnimation(.easeOut(duration: 0.2)) { resaltado = nuevo.id }
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                withAnimation(.easeOut(duration: 0.8)) { resaltado = nil }
            }
        }
        concepto = ""; monto = ""; fecha = Date()
    }
}
