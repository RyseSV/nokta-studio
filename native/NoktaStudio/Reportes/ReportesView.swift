import SwiftUI

private struct ReportePreviewItem: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

@MainActor
@Observable
final class ReportesViewModel {
    var generando: String?
    var isGenerating: Bool { generando != nil }
    var errorMessage: String?

    // Datos para las portadas (números del mes elegido).
    var trabajos: [NoktaTrabajo] = []
    var gastos: [NoktaGasto] = []
    var estados: [NoktaClienteEstado] = []
    var clientes: [NoktaCliente] = []

    func cargar() async {
        async let t: [NoktaTrabajo]? = try? NoktaAPI.get("/api/trabajos")
        async let g: [NoktaGasto]? = try? NoktaAPI.get("/api/gastos")
        async let e: [NoktaClienteEstado]? = try? NoktaAPI.get("/api/clientes-estados")
        async let c: [NoktaCliente]? = try? NoktaAPI.get("/api/clientes")
        let (tt, gg, ee, cc) = await (t, g, e, c)
        trabajos = tt ?? []; gastos = gg ?? []; estados = ee ?? []; clientes = cc ?? []
    }

    /// Los últimos 12 meses, del más reciente al más antiguo.
    static var ultimosMeses: [String] {
        let cal = Calendar(identifier: .gregorian)
        return (0..<12).compactMap { k in
            guard let d = cal.date(byAdding: .month, value: -k, to: Date()) else { return nil }
            return FechaUtil.periodo(anio: cal.component(.year, from: d), mes: cal.component(.month, from: d))
        }
    }

    /// Tres números para la portada de cada reporte.
    func portada(_ tipo: String, periodo: String) -> [(String, String)] {
        switch tipo {
        case "mensual":
            let ing = IngresosCalculator.ingresosDelPeriodo(periodo, trabajos: trabajos)
            let gas = gastos.filter { FechaUtil.periodoDeFecha($0.fecha) == periodo }.reduce(0) { $0 + ($1.monto ?? 0) }
            return [("INGRESOS", NoktaFormato.dinero(ing)), ("GASTOS", NoktaFormato.dinero(gas)), ("NETO", NoktaFormato.dinero(ing - gas))]
        case "clientes":
            let filas = Self.clientesDelMes(periodo, trabajos: trabajos, estados: estados)
            return [("CLIENTES", "\(filas.count)"), ("INGRESO", NoktaFormato.dinero(filas.reduce(0) { $0 + $1.ingreso })),
                    ("POR COBRAR", NoktaFormato.dinero(filas.reduce(0) { $0 + $1.porCobrar }))]
        default:
            let activas = clientes.filter { $0.estado == "activo" }.count
            let visitas = clientes.reduce(0) { $0 + ($1.visitas ?? []).count }
            let desc = clientes.reduce(0) { $0 + ($1.descargas ?? []).count }
            return [("ACTIVAS", "\(activas)"), ("VISITAS", "\(visitas)"), ("DESCARGAS", "\(desc)")]
        }
    }

    struct FilaCliente { let cliente: String; let estado: String; let ingreso: Double; let porCobrar: Double }

    /// Clientes con movimiento en el mes: ingreso del mes (criterio Dashboard)
    /// o algo por cobrar ese mes. Un contrato cancelado en agosto ya no aparece
    /// en septiembre.
    static func clientesDelMes(_ periodo: String, trabajos: [NoktaTrabajo], estados: [NoktaClienteEstado]) -> [FilaCliente] {
        let cobros = IngresosCalculator.cobrosPendientes(periodo, trabajos: trabajos, estados: estados)
        var nombres: [String] = []
        for n in trabajos.map(\.cliente) where !nombres.contains(n) { nombres.append(n) }
        return nombres.compactMap { n in
            let ts = trabajos.filter { $0.cliente == n }
            let ingreso = IngresosCalculator.ingresosDelPeriodo(periodo, trabajos: ts)
            let pend = cobros.filter { $0.cliente == n }.reduce(0.0) { $0 + $1.monto }
            guard ingreso > 0 || pend > 0 else { return nil }
            let contrato = ts.contains { $0.grupoResuelto == "B" || $0.servicio == "Clases" || !($0.sesiones ?? []).isEmpty }
            let er = (estados.first { $0.nombre == n }?.estado ?? "activo").lowercased()
            let estado = contrato ? (ESTADO_CLIENTE_LABEL[er] ?? er.capitalized) : (pend > 0 ? "Pendiente" : "Pagado")
            return FilaCliente(cliente: n, estado: estado, ingreso: ingreso, porCobrar: pend)
        }
        .sorted { $0.ingreso + $0.porCobrar > $1.ingreso + $1.porCobrar }
    }

    func generar(_ tipo: String, periodo: String = IngresosCalculator.periodoActual) async -> (URL, String)? {
        errorMessage = nil
        generando = tipo
        defer { generando = nil }
        do {
            let am = FechaUtil.anioMes(periodo) ?? (anio: Calendar.current.component(.year, from: Date()), mes: Calendar.current.component(.month, from: Date()))
            let mesActual = am.mes
            let anioActual = am.anio
            let meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]
            let titulo: String
            let cuerpo: String

            switch tipo {
            case "mensual":
                async let t: [NoktaTrabajo] = NoktaAPI.get("/api/trabajos")
                async let g: [NoktaGasto] = NoktaAPI.get("/api/gastos")
                let (trabajos, gastos) = try await (t, g)
                let aportes = trabajos.map { trabajo in
                    (trabajo: trabajo, monto: IngresosCalculator.ingresosDelPeriodo(periodo, trabajos: [trabajo]))
                }.filter { $0.monto != 0 }
                let gMes = gastos.filter { g in
                    guard let am = FechaUtil.anioMes(g.fecha) else { return false }
                    return am.mes == mesActual && am.anio == anioActual
                }
                let ingresos = IngresosCalculator.ingresosDelPeriodo(periodo, trabajos: trabajos)
                let gastosTotal = gMes.reduce(0.0) { $0 + ($1.monto ?? 0) }
                titulo = "Reporte mensual — \(meses[mesActual - 1].capitalized) \(anioActual)"

                let trabajosRows = aportes.isEmpty
                    ? "<tr><td colspan=\"4\" style=\"padding:12px 0;color:#888\">Sin ingresos este mes</td></tr>"
                    : aportes.map { aporte in
                        "<tr><td style=\"padding:8px 0\">\(esc(aporte.trabajo.cliente))</td><td>\(esc(aporte.trabajo.servicio))</td><td>\(periodo)</td><td style=\"text-align:right\">$\(fmt(aporte.monto))</td></tr>"
                    }.joined()
                let gastosRows = gMes.isEmpty
                    ? "<tr><td colspan=\"4\" style=\"padding:12px 0;color:#888\">Sin gastos este mes</td></tr>"
                    : gMes.map { g in
                        "<tr><td style=\"padding:8px 0\">\(esc(g.concepto))</td><td>\(esc(g.categoria))</td><td>\(esc(g.fecha))</td><td style=\"text-align:right;color:#c0392b\">$\(fmt(g.monto ?? 0))</td></tr>"
                    }.joined()

                cuerpo = """
                <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin:8px 0 20px">
                  <div class="blk"><small>Ingresos</small><b style="font-size:24px;font-weight:300">$\(fmt(ingresos))</b></div>
                  <div class="blk"><small>Gastos</small><b style="font-size:24px;font-weight:300;color:#c0392b">$\(fmt(gastosTotal))</b></div>
                  <div class="blk"><small>Ganancia neta</small><b style="font-size:24px;font-weight:300;color:#2E8B5A">$\(fmt(ingresos - gastosTotal))</b></div>
                </div>
                <p style="font-size:11px;color:#888">Criterio del Dashboard: sesiones y quincenas pagadas del mes; trabajos ordinarios fechados en el mes, aunque estén pendientes.</p>
                <h3>INGRESOS DEL MES POR TRABAJO</h3>
                <table style="margin-bottom:24px"><thead><tr><th>Cliente</th><th>Servicio</th><th>Periodo</th><th style="text-align:right">Ingreso del mes</th></tr></thead><tbody>\(trabajosRows)</tbody></table>
                <h3>GASTOS</h3>
                <table><thead><tr><th>Concepto</th><th>Categoría</th><th>Fecha</th><th style="text-align:right">Monto</th></tr></thead><tbody>\(gastosRows)</tbody></table>
                """
            case "clientes":
                async let t: [NoktaTrabajo] = NoktaAPI.get("/api/trabajos")
                async let e: [NoktaClienteEstado] = NoktaAPI.get("/api/clientes-estados")
                let (trabajos, estados) = try await (t, e)
                titulo = "Reporte de clientes — \(meses[mesActual - 1].capitalized) \(anioActual)"
                let filas = Self.clientesDelMes(periodo, trabajos: trabajos, estados: estados)
                let rows = filas.isEmpty
                    ? "<tr><td colspan=\"4\" style=\"padding:12px 0;color:#888\">Sin movimiento de clientes este mes</td></tr>"
                    : filas.map { f -> String in
                        let colorEstado = (f.estado == "Activo" || f.estado == "Pagado") ? "#2E8B5A" : f.estado == "Cancelado" ? "#C0392B" : "#A86B12"
                        let colorPend = f.porCobrar > 0 ? "#e67e22" : "#27ae60"
                        return "<tr><td style=\"padding:8px 0;font-weight:500\">\(esc(f.cliente))</td><td style=\"color:\(colorEstado)\">\(esc(f.estado))</td><td style=\"text-align:right\">$\(fmt(f.ingreso))</td><td style=\"text-align:right;color:\(colorPend)\">$\(fmt(f.porCobrar))</td></tr>"
                    }.joined()
                let totIng = filas.reduce(0) { $0 + $1.ingreso }, totPend = filas.reduce(0) { $0 + $1.porCobrar }
                cuerpo = """
                <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin:8px 0 20px">
                  <div class="blk"><small>Clientes del mes</small><b style="font-size:24px;font-weight:300">\(filas.count)</b></div>
                  <div class="blk"><small>Ingreso del mes</small><b style="font-size:24px;font-weight:300;color:#2E8B5A">$\(fmt(totIng))</b></div>
                  <div class="blk"><small>Por cobrar</small><b style="font-size:24px;font-weight:300;color:#A86B12">$\(fmt(totPend))</b></div>
                </div>
                <p style="font-size:11px;color:#888">Solo clientes con movimiento en el mes. Ingreso del mes: mismo criterio que el Dashboard (quincenas y clases pagadas en el mes; trabajos fechados en el mes). Por cobrar: quincenas del mes de contratos activos, saldos de trabajos del mes y solo la próxima clase sin pagar. Clientes pausados o cancelados no deben nada.</p>
                <table style="margin-top:18px"><thead><tr><th>Cliente</th><th>Estado</th><th style="text-align:right">Ingreso del mes</th><th style="text-align:right">Por cobrar</th></tr></thead><tbody>\(rows)</tbody></table>
                """
            default:
                let clientes: [NoktaCliente] = try await NoktaAPI.get("/api/clientes")
                titulo = "Reporte de galerías — \(FechaUtil.fechaCorta(isoToday()))"
                _ = anioActual
                let rows = clientes.isEmpty
                    ? "<tr><td colspan=\"5\" style=\"padding:12px 0;color:#888\">Sin galerías</td></tr>"
                    : clientes.map { c -> String in
                        let estadoLabel = c.estado == "activo" ? "✓ Activo" : c.estado == "descargado" ? "✓ Descargado" : "✗ Expirado"
                        return "<tr><td style=\"padding:8px 0;font-weight:500\">\(esc(c.nombre))</td><td style=\"font-family:monospace;font-size:11px\">\(esc(c.codigo))</td><td>\(estadoLabel)</td><td style=\"text-align:right\">\((c.visitas ?? []).count)</td><td style=\"text-align:right\">\((c.descargas ?? []).count)</td></tr>"
                    }.joined()
                cuerpo = "<table style=\"margin-top:24px\"><thead><tr><th>Cliente</th><th>Código</th><th>Estado</th><th style=\"text-align:right\">Visitas</th><th style=\"text-align:right\">Descargas</th></tr></thead><tbody>\(rows)</tbody></table>"
            }

            let html = PDFTemplates.reporte(titulo: titulo, cuerpoHTML: cuerpo)
            let fileName = "Reporte-\(tipo)-\(anioActual)-\(String(format: "%02d", mesActual))"
            let url = try await PDFRenderer().renderToPDF(html: html, suggestedName: fileName)
            return (url, titulo)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func isoToday() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
    private func fmt(_ d: Double) -> String { String(format: "%.2f", d) }
    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

struct ReportesView: View {
    @State private var vm = ReportesViewModel()
    @State private var previewItem: ReportePreviewItem?
    @State private var periodos: [String: String] = [:]
    @State private var aparecio = false

    private let reportes: [(tipo: String, titulo: String, detalle: String, porMes: Bool)] = [
        ("mensual", "Ingresos y gastos", "Resumen financiero del mes", true),
        ("clientes", "Clientes", "Quién te pagó y quién te debe en el mes", true),
        ("galerias", "Galerías", "Activas, expiradas y descargadas", false),
    ]

    private func periodo(_ tipo: String) -> String { periodos[tipo] ?? IngresosCalculator.periodoActual }

    private func nombreMes(_ p: String) -> String {
        guard let am = FechaUtil.anioMes(p) else { return p }
        return "\(FechaUtil.mesesCompletos[am.mes - 1]) \(am.anio)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                NoktaEncabezado(titulo: "Reportes", subtitulo: "Elige el reporte y el mes; sale en PDF con tu diseño.")
                    .noktaEntrada(aparecio, 0)

                if let error = vm.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle").font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.error)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 400), spacing: 24)], alignment: .leading, spacing: 32) {
                    ForEach(Array(reportes.enumerated()), id: \.element.tipo) { i, r in
                        TarjetaReporte(
                            titulo: r.titulo, detalle: r.detalle,
                            portadaTitulo: r.porMes ? "\(r.titulo) — \(nombreMes(periodo(r.tipo)))" : "Galerías — estado actual",
                            numeros: vm.portada(r.tipo, periodo: periodo(r.tipo)),
                            generando: vm.generando == r.tipo,
                            bloqueado: vm.isGenerating
                        ) {
                            if r.porMes {
                                Menu {
                                    ForEach(ReportesViewModel.ultimosMeses, id: \.self) { p in
                                        Button(nombreMes(p)) { withAnimation(.spring(duration: 0.3)) { periodos[r.tipo] = p } }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(nombreMes(periodo(r.tipo)))
                                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                                    }
                                    .font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoSuave)
                                    .padding(.horizontal, 12).frame(height: 36)
                                    .background(NoktaTheme.superficie2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .contentShape(Rectangle())
                                }
                                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                            } else {
                                Text("Estado actual").font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoTenue)
                                    .padding(.horizontal, 4)
                            }
                        } generar: {
                            Task { await generar(r.tipo) }
                        }
                        .noktaEntrada(aparecio, 1 + i)
                    }
                }
            }
            .padding(.horizontal, 40).padding(.vertical, 32)
            .frame(maxWidth: 1240, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(NoktaTheme.fondo)
        .task {
            withAnimation(.spring(duration: 0.6, bounce: 0.12)) { aparecio = true }
            await vm.cargar()
        }
        .sheet(item: $previewItem) { item in
            PDFPreviewSheet(url: item.url, title: item.title)
        }
    }

    private func generar(_ tipo: String) async {
        if let (url, titulo) = await vm.generar(tipo, periodo: periodo(tipo)) {
            previewItem = ReportePreviewItem(url: url, title: titulo)
        }
    }
}

/// Un reporte como pila de hojas (portada real con sus números) que se abre
/// en abanico al pasar el cursor.
private struct TarjetaReporte<Selector: View>: View {
    let titulo: String
    let detalle: String
    let portadaTitulo: String
    let numeros: [(String, String)]
    let generando: Bool
    let bloqueado: Bool
    @ViewBuilder var selector: () -> Selector
    var generar: () -> Void
    @State private var encima = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                MiniPagina(titulo: portadaTitulo, numeros: numeros).opacity(0.5)
                    .rotationEffect(.degrees(encima ? -11 : -6)).offset(x: encima ? -18 : -6, y: encima ? 14 : 8)
                MiniPagina(titulo: portadaTitulo, numeros: numeros).opacity(0.75)
                    .rotationEffect(.degrees(encima ? 9 : 4)).offset(x: encima ? 16 : 6, y: encima ? 8 : 4)
                MiniPagina(titulo: portadaTitulo, numeros: numeros)
                    .offset(y: encima ? -10 : 0)
                    .shadow(color: .black.opacity(encima ? 0.35 : 0.2), radius: encima ? 22 : 12, y: encima ? 16 : 8)
            }
            .frame(height: 250)
            .frame(maxWidth: .infinity)
            .animation(.spring(duration: 0.5, bounce: 0.3), value: encima)
            .onHover { encima = $0 }
            .onTapGesture(perform: generar)

            VStack(alignment: .leading, spacing: 3) {
                Text(titulo).font(NoktaFont.poppins(16, .medium)).foregroundStyle(NoktaTheme.texto)
                Text(detalle).font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoSuave)
            }
            HStack(spacing: 8) {
                selector()
                Spacer(minLength: 0)
                Button(action: generar) {
                    ZStack {
                        if generando { ProgressView().controlSize(.small).tint(.white) }
                        else { Text("Generar PDF") }
                    }
                    .font(NoktaFont.poppins(12, .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: 36)
                    .background(LinearGradient(colors: [Color(red: 0.855, green: 0.478, blue: 0.282), Color(red: 0.72, green: 0.32, blue: 0.157)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: NoktaTheme.marca.opacity(0.3), radius: 8, y: 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(bloqueado)
            }
        }
    }
}

/// Portada del PDF en miniatura (tarjeta cálida; colores fijos porque es papel).
private struct MiniPagina: View {
    let titulo: String
    let numeros: [(String, String)]

    private let crema = Color(red: 0.953, green: 0.933, blue: 0.902)
    private let crema2 = Color(red: 0.98, green: 0.969, blue: 0.949)
    private let tinta = Color(red: 0.11, green: 0.11, blue: 0.10)
    private let naranja = Color(red: 0.72, green: 0.32, blue: 0.157)
    private let linea = Color(red: 0.937, green: 0.91, blue: 0.867)

    private static let logo: Image? = {
        guard let url = Bundle.main.url(forResource: "nokta_lockup_color_transparent", withExtension: "png") else { return nil }
        #if os(macOS)
        return NSImage(contentsOf: url).map { Image(nsImage: $0) }
        #else
        return UIImage(contentsOfFile: url.path).map { Image(uiImage: $0) }
        #endif
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let logo = Self.logo { logo.resizable().scaledToFit().frame(height: 18) }
                Spacer()
                Text("REPORTE").font(NoktaFont.poppins(5.5, .semibold)).tracking(1).foregroundStyle(naranja)
                    .padding(.horizontal, 6).padding(.vertical, 3).background(crema, in: Capsule())
            }
            Text(titulo).font(NoktaFont.poppins(12, .light)).foregroundStyle(tinta).lineLimit(2).padding(.top, 10)
                .contentTransition(.opacity)
            HStack(spacing: 4) {
                ForEach(Array(numeros.enumerated()), id: \.offset) { _, n in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(n.0).font(NoktaFont.poppins(4.5, .semibold)).tracking(0.6).foregroundStyle(naranja).lineLimit(1)
                        Text(n.1).font(NoktaFont.poppins(8.5)).foregroundStyle(tinta).lineLimit(1).minimumScaleFactor(0.6)
                            .contentTransition(.numericText())
                    }
                    .padding(5).frame(maxWidth: .infinity, alignment: .leading)
                    .background(crema2, in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.top, 8)
            VStack(alignment: .leading, spacing: 5) {
                ForEach([0.85, 1, 0.7, 0.9, 0.6, 0.8], id: \.self) { w in
                    GeometryReader { g in Capsule().fill(linea).frame(width: g.size.width * w, height: 3) }.frame(height: 3)
                }
            }
            .padding(.top, 10)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 12))
        .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8)
                .fill(LinearGradient(colors: [Color(red: 0.816, green: 0.404, blue: 0.227), naranja], startPoint: .top, endPoint: .bottom))
                .frame(width: 3)
        }
        .padding(10)
        .background(crema, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .frame(width: 190, height: 230)
    }
}
