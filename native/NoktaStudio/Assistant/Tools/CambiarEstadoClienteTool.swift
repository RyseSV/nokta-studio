import Foundation
import FoundationModels

@Generable
struct CambiarEstadoClienteArgs {
    @Guide(description: "Nombre exacto del cliente, tal como aparece en Nokta Studio")
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
        guard ["activo", "pausado", "cancelado"].contains(arguments.estado) else {
            return "Estado inválido: debe ser activo, pausado o cancelado."
        }
        struct Body: Encodable { let estado: String; let notas: String? }
        // Match JS's encodeURIComponent (used by the web's own call to this
        // endpoint): encode everything except RFC 3986 unreserved chars, so
        // a "/" in the name can't be misread as an extra path segment.
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let encodedNombre = arguments.nombre.addingPercentEncoding(withAllowedCharacters: unreserved) ?? arguments.nombre
        let path = "/api/clientes-estados/\(encodedNombre)"
        let _: OKResponse = try await NoktaAPI.put(path, body: Body(estado: arguments.estado, notas: arguments.notas))
        return "Cliente '\(arguments.nombre)' actualizado a estado: \(arguments.estado)."
    }
}
