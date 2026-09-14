import Foundation
import FoundationModels

@Generable
struct GestionarEquipoArgs {
    @Guide(description: "Nombre del miembro del equipo")
    var nombre: String
    @Guide(description: "Rol o puesto")
    var rol: String
    @Guide(description: "Tipo de pago: 'fijo' o 'comision'")
    var tipo: String
    @Guide(description: "Monto fijo o porcentaje de comisión")
    var comision: Double?
    @Guide(description: "Monto ya pagado a este miembro, en dólares")
    var pagado: Double?
    @Guide(description: "Monto pendiente de pagarle, en dólares")
    var pendiente: Double?
}

struct NoktaMiembroEquipo: Decodable { let id: String; let nombre: String }

struct GestionarEquipoTool: Tool {
    let name = "gestionar_equipo"
    let description = "Agrega un nuevo miembro al equipo, o actualiza uno existente (por nombre) con su rol, tipo de pago, comisión, pagado y pendiente."
    typealias Arguments = GestionarEquipoArgs

    func call(arguments: GestionarEquipoArgs) async throws -> String {
        struct Body: Encodable {
            let nombre: String, rol: String, tipo: String
            let comision: Double, pagado: Double, pendiente: Double
        }
        let body = Body(
            nombre: arguments.nombre, rol: arguments.rol, tipo: arguments.tipo,
            comision: arguments.comision ?? 0, pagado: arguments.pagado ?? 0, pendiente: arguments.pendiente ?? 0
        )

        let equipo: [NoktaMiembroEquipo] = try await NoktaAPI.get("/api/equipo")
        if let existente = equipo.first(where: { $0.nombre.localizedCaseInsensitiveCompare(arguments.nombre) == .orderedSame }) {
            struct Resp: Decodable { let ok: Bool }
            let _: Resp = try await NoktaAPI.put("/api/equipo/\(existente.id)", body: body)
            return "Miembro del equipo '\(arguments.nombre)' actualizado."
        } else {
            struct Resp: Decodable { let ok: Bool }
            let _: Resp = try await NoktaAPI.post("/api/equipo", body: body)
            return "'\(arguments.nombre)' agregado al equipo como \(arguments.rol)."
        }
    }
}
