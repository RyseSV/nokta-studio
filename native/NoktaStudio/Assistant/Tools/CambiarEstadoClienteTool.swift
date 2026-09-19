import Foundation
import FoundationModels

@Generable
struct CambiarEstadoClienteArgs {
    @Guide(description: "Nombre del cliente mencionado por el usuario; se resolverá contra los clientes existentes, sin inventarlo")
    var nombre: String
    @Guide(description: "Nuevo estado de la relación: activo, pausado, o cancelado")
    var estado: String
    @Guide(description: "Nota opcional explicando el motivo (ej: 'dejó de responder desde julio')")
    var notas: String?
}

/// Same endpoint the Clientes page's inline status selector calls — a
/// client paused/cancelled from the Assistant shows up that way on the web
/// immediately, and vice versa.
struct CambiarEstadoClienteTool: Tool {
    let name = "cambiar_estado_cliente"
    let description = "Cambia el estado de relación de un cliente (activo, pausado, cancelado) y opcionalmente agrega una nota. Úsalo cuando el usuario quiera pausar, cancelar o reactivar un cliente."
    typealias Arguments = CambiarEstadoClienteArgs

    func call(arguments: CambiarEstadoClienteArgs) async throws -> String {
        let estado = arguments.estado.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ["activo", "pausado", "cancelado"].contains(estado) else {
            return "Estado inválido: debe ser activo, pausado o cancelado. No cambié ningún dato."
        }
        async let trabajos: [NoktaTrabajo] = NoktaAPI.get("/api/trabajos")
        async let estados: [NoktaClienteEstado] = NoktaAPI.get("/api/clientes-estados")
        async let clientes: [NoktaCliente] = NoktaAPI.get("/api/clientes")
        let (listaTrabajos, listaEstados, listaClientes) = try await (trabajos, estados, clientes)
        let resolucion = ClienteResolver.resolver(arguments.nombre, nombres: listaTrabajos.map(\.cliente) + listaEstados.map(\.nombre) + listaClientes.map(\.nombre))
        guard case .encontrado(let nombre) = resolucion else {
            return resolucion.mensajeSiNoResuelto ?? "Indica el cliente que quieres actualizar."
        }
        struct Body: Encodable { let estado: String; let notas: String? }
        struct Respuesta: Decodable { let ok: Bool; let clienteEstado: NoktaClienteEstado }
        // The live relationship state is authoritative for dashboard and alerts.
        // Omitted notes are not sent, so pausing/reactivating preserves existing notes.
        let respuesta: Respuesta = try await NoktaAPI.put(
            "/api/clientes-estados/\(nombre.urlPathComponentEncoded)",
            body: Body(estado: estado, notas: arguments.notas)
        )
        guard respuesta.ok, respuesta.clienteEstado.nombre == nombre,
              respuesta.clienteEstado.estado == estado,
              arguments.notas == nil || respuesta.clienteEstado.notas == arguments.notas else {
            throw CambioError.respuestaNoConfirmada
        }
        return "Cliente '\(nombre)' actualizado a estado: \(estado)."
    }

    enum CambioError: LocalizedError {
        case respuestaNoConfirmada
        var errorDescription: String? {
            "El servidor no confirmó el estado y la nota solicitados. Consulta el cliente antes de reintentar."
        }
    }
}
