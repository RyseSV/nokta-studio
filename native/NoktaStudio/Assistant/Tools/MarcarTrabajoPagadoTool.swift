import Foundation
import FoundationModels

@Generable
struct MarcarTrabajoPagadoArgs {
    @Guide(description: "Nombre del cliente")
    var cliente: String
    @Guide(description: "Servicio exacto, para desambiguar si el cliente tiene varios trabajos pendientes")
    var servicio: String?
}

/// Same effect as the web's "Marcar pagado" button: estado=pagado,
/// anticipo=monto, saldo=0 (server recomputes saldo on PUT regardless).
struct MarcarTrabajoPagadoTool: Tool {
    let name = "marcar_trabajo_pagado"
    let description = "Marca como pagado un trabajo pendiente de un cliente (no aplica a paquetes mensuales, que se pagan por quincenas — usa gestionar_quincena para esos)."
    typealias Arguments = MarcarTrabajoPagadoArgs

    func call(arguments: MarcarTrabajoPagadoArgs) async throws -> String {
        let trabajos: [NoktaTrabajo] = try await NoktaAPI.get("/api/trabajos")
        var candidatos = trabajos.filter {
            $0.cliente.localizedCaseInsensitiveCompare(arguments.cliente) == .orderedSame
                && $0.estado == "pendiente" && $0.grupoResuelto != "B"
        }
        if let servicio = arguments.servicio {
            candidatos = candidatos.filter { $0.servicio.localizedCaseInsensitiveContains(servicio) }
        }
        guard !candidatos.isEmpty else {
            return "No encontré trabajos pendientes de '\(arguments.cliente)' (que no sean paquete mensual)."
        }
        guard candidatos.count == 1 else {
            let lista = candidatos.map { "- \($0.servicio) · $\($0.monto ?? 0) · \($0.fecha ?? "—")" }.joined(separator: "\n")
            return "Hay varios trabajos pendientes de \(arguments.cliente), decime cuál marcar (por servicio):\n" + lista
        }
        let t = candidatos[0]
        let fields: [String: AnyEncodableValue] = [
            "estado": .string("pagado"),
            "anticipo": .double(t.monto ?? 0),
            "saldo": .double(0),
        ]
        struct Resp: Decodable { let ok: Bool }
        let _: Resp = try await NoktaAPI.put("/api/trabajos/\(t.id)", body: AnyEncodableDict(fields))
        return "'\(t.servicio)' de \(t.cliente) marcado como pagado ($\(String(format: "%.2f", t.monto ?? 0)))."
    }
}
