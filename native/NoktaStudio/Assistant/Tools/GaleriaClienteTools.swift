import Foundation
import FoundationModels

@Generable
struct ReactivarGaleriaArgs {
    @Guide(description: "Nombre del cliente cuya galería se va a reactivar")
    var nombre: String
    @Guide(description: "Días adicionales de acceso a la galería, por defecto 7")
    var dias: Int?
}

struct ReactivarGaleriaTool: Tool {
    let name = "reactivar_galeria"
    let description = "Reactiva el link de galería de fotos de un cliente (extiende los días de acceso). No confundir con cambiar_estado_cliente, que es sobre la relación comercial."
    typealias Arguments = ReactivarGaleriaArgs

    func call(arguments: ReactivarGaleriaArgs) async throws -> String {
        let clientes: [NoktaCliente] = try await NoktaAPI.get("/api/clientes")
        guard let c = clientes.first(where: { $0.nombre.localizedCaseInsensitiveCompare(arguments.nombre) == .orderedSame }) else {
            return "No encontré una galería para '\(arguments.nombre)'."
        }
        struct Body: Encodable { let dias: Int }
        struct Resp: Decodable { let ok: Bool; let expira: String? }
        let resp: Resp = try await NoktaAPI.put("/api/clientes/\(c.codigo)/reactivar", body: Body(dias: arguments.dias ?? 7))
        return "Galería de \(arguments.nombre) reactivada. Nueva expiración: \(resp.expira ?? "—")."
    }
}

@Generable
struct EliminarGaleriaArgs {
    @Guide(description: "Nombre exacto del cliente cuya galería se va a eliminar permanentemente")
    var nombre: String
}

/// Destructive — the model is instructed (session-wide) to always confirm
/// with the user before calling any deletion tool.
struct EliminarGaleriaTool: Tool {
    let name = "eliminar_galeria"
    let description = "Elimina PERMANENTEMENTE la galería de un cliente. Es destructivo e irreversible — confirma explícitamente con el usuario antes de usar esta herramienta."
    typealias Arguments = EliminarGaleriaArgs

    func call(arguments: EliminarGaleriaArgs) async throws -> String {
        let clientes: [NoktaCliente] = try await NoktaAPI.get("/api/clientes")
        guard let c = clientes.first(where: { $0.nombre.localizedCaseInsensitiveCompare(arguments.nombre) == .orderedSame }) else {
            return "No encontré una galería para '\(arguments.nombre)'."
        }
        struct Resp: Decodable { let ok: Bool }
        let _: Resp = try await NoktaAPI.delete("/api/clientes/\(c.codigo)")
        return "Galería de \(arguments.nombre) (\(c.codigo)) eliminada."
    }
}
