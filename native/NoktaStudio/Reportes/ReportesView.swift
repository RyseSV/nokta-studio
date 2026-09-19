import SwiftUI

private struct ReportePreviewItem: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

@MainActor
@Observable
final class ReportesViewModel {
    var isGenerating = false
    var errorMessage: String?

    func generar(_ tipo: String) async -> (URL, String)? {
        errorMessage = nil
        isGenerating = true
        defer { isGenerating = false }
        do {
            let now = Date()
            let cal = Calendar.current
            let mesActual = cal.component(.month, from: now)
            let anioActual = cal.component(.year, from: now)
            let meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]

            let periodo = FechaUtil.periodo(anio: anioActual, mes: mesActual)
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
                titulo = "Reporte mensual — \(meses[mesActual - 1]) \(anioActual)"

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
                <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:16px;margin:24px 0">
                  <div style="background:#f5f3ef;border-radius:8px;padding:16px"><div style="font-size:11px;color:#888;letter-spacing:1px">INGRESOS</div><div style="font-size:22px;font-weight:600;color:#1C1C1A">$\(fmt(ingresos))</div></div>
                  <div style="background:#f5f3ef;border-radius:8px;padding:16px"><div style="font-size:11px;color:#888;letter-spacing:1px">GASTOS</div><div style="font-size:22px;font-weight:600;color:#c0392b">$\(fmt(gastosTotal))</div></div>
                  <div style="background:#f5f3ef;border-radius:8px;padding:16px"><div style="font-size:11px;color:#888;letter-spacing:1px">GANANCIA NETA</div><div style="font-size:22px;font-weight:600;color:#27ae60">$\(fmt(ingresos - gastosTotal))</div></div>
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
                let cobros = IngresosCalculator.cobrosPendientes(periodo, trabajos: trabajos, estados: estados)
                titulo = "Reporte de cobros por cliente — \(periodo)"
                var nombres: [String] = []
                var seen = Set<String>()
                for n in trabajos.map(\.cliente) where !seen.contains(n) { seen.insert(n); nombres.append(n) }
                let rows = nombres.isEmpty
                    ? "<tr><td colspan=\"4\" style=\"padding:12px 0;color:#888\">Sin clientes</td></tr>"
                    : nombres.map { n -> String in
                        let ts = trabajos.filter { $0.cliente == n }
                        let total = ts.reduce(0.0) { $0 + ($1.monto ?? 0) }
                        let pend = cobros.filter { $0.cliente == n }.reduce(0.0) { $0 + $1.monto }
                        let color = pend > 0 ? "#e67e22" : "#27ae60"
                        return "<tr><td style=\"padding:8px 0;font-weight:500\">\(esc(n))</td><td style=\"text-align:right\">\(ts.count)</td><td style=\"text-align:right\">$\(fmt(total))</td><td style=\"text-align:right;color:\(color)\">$\(fmt(pend))</td></tr>"
                    }.joined()
                cuerpo = """
                <p style="font-size:11px;color:#888">Cobro: saldos de trabajos del mes y quincenas activas del mes, más solo la próxima sesión sin pagar por trabajo aunque quede fuera del mes. Excluye contratos pausados/cancelados y quincenas ocultas. Total facturado conserva el monto histórico registrado de los trabajos.</p>
                <table style="margin-top:24px"><thead><tr><th>Cliente</th><th style="text-align:right">Trabajos</th><th style="text-align:right">Total facturado</th><th style="text-align:right">Cobro del mes / próxima sesión</th></tr></thead><tbody>\(rows)</tbody></table>
                """
            default:
                let clientes: [NoktaCliente] = try await NoktaAPI.get("/api/clientes")
                titulo = "Reporte de galerías — \(FechaUtil.fechaCorta(isoToday()))"
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

    private let reportes: [(tipo: String, titulo: String, detalle: String)] = [
        ("mensual", "Reporte mensual de ingresos y gastos", "Resumen financiero del mes actual"),
        ("clientes", "Reporte de clientes del período", "Facturado histórico y cobros: mes actual / próxima sesión"),
        ("galerias", "Reporte de galerías", "Galerías activas, expiradas y descargadas"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Reportes").font(NoktaFont.pageTitle).foregroundStyle(NoktaPalette.cream)

                if let error = vm.errorMessage {
                    Text(error).font(.system(size: 13)).foregroundStyle(NoktaPalette.red)
                }

                VStack(spacing: 12) {
                    ForEach(reportes, id: \.tipo) { r in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.titulo).font(.system(size: 14, weight: .medium)).foregroundStyle(NoktaPalette.cream)
                                Text(r.detalle).font(.system(size: 12)).foregroundStyle(NoktaPalette.muted)
                            }
                            Spacer()
                            Button("📥 Generar PDF") { Task { await generar(r.tipo) } }
                                .buttonStyle(.glass)
                                .disabled(vm.isGenerating)
                        }
                        .padding(16)
                        .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NoktaPalette.bg)
        .sheet(item: $previewItem) { item in
            PDFPreviewSheet(url: item.url, title: item.title)
        }
    }

    private func generar(_ tipo: String) async {
        if let (url, titulo) = await vm.generar(tipo) {
            previewItem = ReportePreviewItem(url: url, title: titulo)
        }
    }
}
