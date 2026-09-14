import Foundation
import FoundationModels

@Generable
struct CrearClienteArgs {
    @Guide(description: "Nombre completo del cliente")
    var nombre: String
    @Guide(description: "Tipo de evento: boda, xvanios, corporativo, deportivo, graduacion, u otro")
    var tipo: String
    @Guide(description: "Días de validez del link de galería. 0 significa sin límite.")
    var dias: Int
    @Guide(description: "Número de WhatsApp del cliente, solo dígitos con código de país, o vacío")
    var whatsapp: String?
}

struct CrearClienteResponse: Decodable {
    let ok: Bool
    let link: String
}

/// Creates a client the exact same way the "Nuevo cliente" modal in
/// Galerías does — same endpoint, same generated code/link, so it shows up
/// on the web immediately.
struct CrearClienteTool: Tool {
    let name = "crear_cliente"
    let description = "Crea un nuevo cliente con galería privada en Nokta Studio (mismo flujo que el botón 'Nuevo cliente' de la sección Galerías)."
    typealias Arguments = CrearClienteArgs

    func call(arguments: CrearClienteArgs) async throws -> String {
        struct Body: Encodable { let nombre: String; let tipo: String; let dias: Int; let whatsapp: String? }
        let body = Body(nombre: arguments.nombre, tipo: arguments.tipo, dias: arguments.dias, whatsapp: arguments.whatsapp)
        let resp: CrearClienteResponse = try await NoktaAPI.post("/api/clientes", body: body)
        return "Cliente '\(arguments.nombre)' creado. Link de galería: \(resp.link)"
    }
}
