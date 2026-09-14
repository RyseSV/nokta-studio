import Foundation
import FoundationModels

@Generable
struct ConsultarGastosArgs {
    @Guide(description: "Filtrar por categoría (Equipo, Transporte, Software, Marketing, Otros), o vacío para todas")
    var categoria: String?
}

struct ConsultarGastosTool: Tool {
    let name = "consultar_gastos"
    let description = "Consulta los gastos registrados en Nokta Studio: concepto, categoría, monto y fecha. Útil para responder sobre gastos totales o por categoría."
    typealias Arguments = ConsultarGastosArgs

    func call(arguments: ConsultarGastosArgs) async throws -> String {
        let gastos: [NoktaGasto] = try await NoktaAPI.get("/api/gastos")
        var filtered = gastos
        if let cat = arguments.categoria, !cat.isEmpty {
            filtered = filtered.filter { $0.categoria.localizedCaseInsensitiveCompare(cat) == .orderedSame }
        }
        if filtered.isEmpty { return "No se encontraron gastos con esos filtros." }
        let lines = filtered.prefix(60).map { g in
            "- \(g.concepto) · \(g.categoria) · $\(String(format: "%.2f", g.monto ?? 0)) · \(g.fecha)"
        }
        let total = filtered.reduce(0.0) { $0 + ($1.monto ?? 0) }
        return "\(filtered.count) gasto(s). Total: $\(String(format: "%.2f", total)).\n" + lines.joined(separator: "\n")
    }
}
