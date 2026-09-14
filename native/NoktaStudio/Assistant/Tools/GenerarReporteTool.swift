import Foundation
import FoundationModels

@Generable
struct GenerarReporteArgs {
    @Guide(description: "Tipo de reporte: 'mensual' (ingresos y gastos del mes), 'clientes' (facturado y pendiente por cliente), o 'galerias' (estado de las galerías)")
    var tipo: String
}

/// Note: the web's Reportes page turns this same data into a downloadable
/// PDF client-side (html2pdf.js) — the Assistant can't generate a PDF file
/// itself, so this gives the numbers as text; download the actual PDF from
/// the Reportes tab.
struct GenerarReporteTool: Tool {
    let name = "generar_reporte"
    let description = "Genera un resumen tipo reporte (mensual, de clientes, o de galerías) como texto. Para el PDF descargable, el usuario debe ir a la sección Reportes."
    typealias Arguments = GenerarReporteArgs

    func call(arguments: GenerarReporteArgs) async throws -> String {
        switch arguments.tipo.lowercased() {
        case "mensual":
            async let trabajosTask: [NoktaTrabajo] = NoktaAPI.get("/api/trabajos")
            async let gastosTask: [NoktaGasto] = NoktaAPI.get("/api/gastos")
            let (trabajos, gastos) = try await (trabajosTask, gastosTask)
            let mesActual = String(ISO8601DateFormatter().string(from: Date()).prefix(7))
            let tMes = trabajos.filter { ($0.fecha ?? "").hasPrefix(mesActual) }
            let gMes = gastos.filter { $0.fecha.hasPrefix(mesActual) }
            let ingresos = tMes.reduce(0.0) { $0 + ($1.monto ?? 0) }
            let gastosTotal = gMes.reduce(0.0) { $0 + ($1.monto ?? 0) }
            return """
            Reporte mensual (\(mesActual)):
            Ingresos: $\(String(format: "%.2f", ingresos))
            Gastos: $\(String(format: "%.2f", gastosTotal))
            Ganancia neta: $\(String(format: "%.2f", ingresos - gastosTotal))
            Trabajos del mes: \(tMes.count). Gastos del mes: \(gMes.count).
            Nota: para el PDF descargable, andá a la sección Reportes.
            """

        case "clientes":
            let trabajos: [NoktaTrabajo] = try await NoktaAPI.get("/api/trabajos")
            let nombres = Set(trabajos.map(\.cliente)).sorted()
            let lines = nombres.map { nombre -> String in
                let ts = trabajos.filter { $0.cliente == nombre }
                let total = ts.reduce(0.0) { $0 + ($1.monto ?? 0) }
                let pendiente = ts.filter { $0.estado == "pendiente" }.reduce(0.0) { $0 + ($1.saldo ?? 0) }
                return "- \(nombre): \(ts.count) trabajo(s), facturado $\(String(format: "%.2f", total)), pendiente $\(String(format: "%.2f", pendiente))"
            }
            return "Reporte de clientes:\n" + lines.joined(separator: "\n") + "\n\nNota: para el PDF descargable, andá a la sección Reportes."

        case "galerias":
            let clientes: [NoktaCliente] = try await NoktaAPI.get("/api/clientes")
            let lines = clientes.map { "- \($0.nombre) (\($0.codigo)): \($0.estado)" }
            return "Reporte de galerías (\(clientes.count) total):\n" + lines.joined(separator: "\n") + "\n\nNota: para el PDF descargable, andá a la sección Reportes."

        default:
            return "Tipo de reporte inválido: usa 'mensual', 'clientes', o 'galerias'."
        }
    }
}
