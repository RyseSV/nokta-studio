import Foundation
import FoundationModels

@Generable
struct ConsultarTrabajosArgs {
    @Guide(description: "Filtrar por estado: 'pendiente', 'pagado', o vacío para todos")
    var filtroEstado: String?
    @Guide(description: "Filtrar por nombre de cliente (coincidencia parcial), o vacío para todos")
    var filtroCliente: String?
}

/// Lets the assistant answer questions about jobs/income by reading the
/// exact same `/api/trabajos` the web panel's Trabajos and Dashboard pages
/// use — no separate data source to keep in sync.
struct ConsultarTrabajosTool: Tool {
    let name = "consultar_trabajos"
    let description = "Consulta el historial de trabajos/proyectos: cliente, servicio, monto registrado y estado. Para cuánto deben o cobros actuales usa consultar_cobros; el saldo global de un trabajo recurrente no representa su cobro actual."
    typealias Arguments = ConsultarTrabajosArgs

    func call(arguments: ConsultarTrabajosArgs) async throws -> String {
        if arguments.filtroEstado?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "pendiente" {
            return try await ConsultarCobrosTool.consultar(cliente: arguments.filtroCliente)
        }
        let trabajos: [NoktaTrabajo] = try await NoktaAPI.get("/api/trabajos")
        var filtered = trabajos
        if let fe = arguments.filtroEstado, !fe.isEmpty {
            filtered = filtered.filter { $0.estado == fe }
        }
        if let fc = arguments.filtroCliente, !fc.isEmpty {
            filtered = filtered.filter { $0.cliente.localizedCaseInsensitiveContains(fc) }
        }
        if filtered.isEmpty { return "No se encontraron trabajos con esos filtros." }
        let lines = filtered.prefix(60).map { t in
            "- \(t.cliente) · \(t.servicio) · monto $\(fmt(t.monto)) · \(t.estado) · fecha \(t.fecha ?? "—")"
        }
        let totalMonto = filtered.reduce(0.0) { $0 + ($1.monto ?? 0) }
        return "\(filtered.count) trabajo(s). Monto histórico registrado: $\(fmt(totalMonto)) (no es deuda actual ni cobrado). Para cobros pendientes usa consultar_cobros.\n" + lines.joined(separator: "\n")
    }

    private func fmt(_ d: Double?) -> String { String(format: "%.2f", d ?? 0) }
}
