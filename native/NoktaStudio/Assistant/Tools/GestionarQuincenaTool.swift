import Foundation
import FoundationModels

@Generable
struct GestionarQuincenaArgs {
    @Guide(description: "Nombre del cliente con paquete mensual")
    var cliente: String
    @Guide(description: "Periodo en formato YYYY-MM, ej. 2026-09")
    var periodo: String
    @Guide(description: "1 para la quincena del 1 al 15, 2 para la del 16 a fin de mes")
    var q: Int
    @Guide(description: "Acción: 'pagar', 'retrasar', 'pendiente', u 'ocultar'")
    var accion: String
}

/// Quincenas are stored as a full array on the Trabajo doc and replaced
/// wholesale via PATCH — same pattern the web's Trabajo detail page uses to
/// mark one paid/late/hidden.
struct GestionarQuincenaTool: Tool {
    let name = "gestionar_quincena"
    let description = "Marca una quincena de un cliente con paquete mensual como pagada, retrasada, pendiente, u oculta."
    typealias Arguments = GestionarQuincenaArgs

    func call(arguments: GestionarQuincenaArgs) async throws -> String {
        let estadoNuevo: String
        switch arguments.accion.lowercased() {
        case "pagar", "pagado": estadoNuevo = "pagado"
        case "retrasar", "retrasado", "retrasada": estadoNuevo = "retrasado"
        case "pendiente": estadoNuevo = "pendiente"
        case "ocultar", "oculta": estadoNuevo = "oculta"
        default: return "Acción inválida: usa pagar, retrasar, pendiente, u ocultar."
        }

        let trabajos: [NoktaTrabajo] = try await NoktaAPI.get("/api/trabajos")
        guard let t = trabajos.first(where: {
            $0.cliente.localizedCaseInsensitiveCompare(arguments.cliente) == .orderedSame && $0.grupoResuelto == "B"
        }) else {
            return "No encontré un paquete mensual activo para '\(arguments.cliente)'."
        }

        var quincenas = t.quincenas ?? []
        let montoDefault = (t.pagoMensual ?? 0) / 2
        if let idx = quincenas.firstIndex(where: { $0.periodo == arguments.periodo && $0.q == arguments.q }) {
            quincenas[idx].estado = estadoNuevo
            if estadoNuevo == "pagado" { quincenas[idx].fechaPago = ISO8601DateFormatter().string(from: Date()) }
        } else {
            quincenas.append(NoktaQuincena(
                periodo: arguments.periodo, q: arguments.q, monto: montoDefault, estado: estadoNuevo,
                fechaPago: estadoNuevo == "pagado" ? ISO8601DateFormatter().string(from: Date()) : nil
            ))
        }

        struct Body: Encodable { let quincenas: [NoktaQuincena] }
        struct Resp: Decodable { let ok: Bool }
        let _: Resp = try await NoktaAPI.patch("/api/trabajos/\(t.id)/quincenas", body: Body(quincenas: quincenas))
        return "Quincena \(arguments.periodo) (Q\(arguments.q)) de \(arguments.cliente) actualizada a: \(estadoNuevo)."
    }
}
