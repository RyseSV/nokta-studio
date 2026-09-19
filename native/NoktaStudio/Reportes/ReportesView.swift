import SwiftUI

private struct ReportePreviewItem: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

@Observable
final class ReportesViewModel {
    var isGenerating = false
    var errorMessage: String?

    func generar(_ tipo: String) async -> (URL, String)? {
        errorMessage = nil
        isGenerating = true
        defer { isGenerating = false }
        do {
            async let t: [NoktaTrabajo]? = try? NoktaAPI.get("/api/trabajos")
            async let g: [NoktaGasto]? = try? NoktaAPI.get("/api/gastos")
            async let c: [NoktaCliente]? = try? NoktaAPI.get("/api/clientes")
            let (trabajos, gastos, clientes) = await (t ?? [], g ?? [], c ?? [])

            let now = Date()
            let cal = Calendar.current
            let mesActual = cal.component(.month, from: now)
            let anioActual = cal.component(.year, from: now)
            let meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]

            let titulo: String
            let cuerpo: String

            switch tipo {
            case "mensual":
                let tMes = trabajos.filter { t in
                    guard let am = FechaUtil.anioMes(t.fecha) else { return false }
                    return am.mes == mesActual && am.anio == anioActual
                }
                let gMes = gastos.filter { g in
                    guard let am = FechaUtil.anioMes(g.fecha) else { return false }
                    return am.mes == mesActual && am.anio == anioActual
                }
                let ingresos = tMes.reduce(0.0) { $0 + ($1.monto ?? 0) }
                let gastosTotal = gMes.reduce(0.0) { $0 + ($1.monto ?? 0) }
                titulo = "Reporte mensual — \(meses[mesActual - 1]) \(anioActual)"

                let trabajosRows = tMes.isEmpty
                    ? "<tr><td colspan=\"5\" style=\"padding:12px 0;color:#888\">Sin trabajos este mes</td></tr>"
                    : tMes.map { t in
                        "<tr><td style=\"padding:8px 0\">\(esc(t.cliente))</td><td>\(esc(t.servicio))</td><td>\(esc(t.fecha ?? "—"))</td><td style=\"text-align:right\">$\(fmt(t.monto ?? 0))</td><td style=\"text-align:right\">\(t.estado == "pagado" ? "✓ Pagado" : "Pendiente")</td></tr>"
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
                <h3>TRABAJOS</h3>
                <table style="margin-bottom:24px"><thead><tr><th>Cliente</th><th>Servicio</th><th>Fecha</th><th style="text-align:right">Monto</th><th style="text-align:right">Estado</th></tr></thead><tbody>\(trabajosRows)</tbody></table>
                <h3>GASTOS</h3>
                <table><thead><tr><th>Concepto</th><th>Categoría</th><th>Fecha</th><th style="text-align:right">Monto</th></tr></thead><tbody>\(gastosRows)</tbody></table>
                """
            case "clientes":
                titulo = "Reporte de clientes — \(FechaUtil.fechaCorta(isoToday()))"
                var nombres: [String] = []
                var seen = Set<String>()
                for n in trabajos.map(\.cliente) where !seen.contains(n) { seen.insert(n); nombres.append(n) }
                let rows = nombres.isEmpty
                    ? "<tr><td colspan=\"4\" style=\"padding:12px 0;color:#888\">Sin clientes</td></tr>"
                    : nombres.map { n -> String in
                        let ts = trabajos.filter { $0.cliente == n }
                        let total = ts.reduce(0.0) { $0 + ($1.monto ?? 0) }
                        let pend = ts.filter { $0.estado == "pendiente" }.reduce(0.0) { $0 + ($1.saldo ?? 0) }
                        let color = pend > 0 ? "#e67e22" : "#27ae60"
                        return "<tr><td style=\"padding:8px 0;font-weight:500\">\(esc(n))</td><td style=\"text-align:right\">\(ts.count)</td><td style=\"text-align:right\">$\(fmt(total))</td><td style=\"text-align:right;color:\(color)\">$\(fmt(pend))</td></tr>"
                    }.joined()
                cuerpo = "<table style=\"margin-top:24px\"><thead><tr><th>Cliente</th><th style=\"text-align:right\">Trabajos</th><th style=\"text-align:right\">Total facturado</th><th style=\"text-align:right\">Pendiente</th></tr></thead><tbody>\(rows)</tbody></table>"
            default:
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
        ("mensual", "Reporte mensual de ingresos y gastos", "Resumen financiero del mes seleccionado"),
        ("clientes", "Reporte de clientes del período", "Lista de clientes, trabajos y montos"),
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
