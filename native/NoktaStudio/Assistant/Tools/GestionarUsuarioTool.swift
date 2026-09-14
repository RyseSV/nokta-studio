import Foundation
import FoundationModels

@Generable
struct CrearUsuarioArgs {
    @Guide(description: "Nombre completo")
    var nombre: String
    @Guide(description: "Nombre de usuario para iniciar sesión")
    var username: String
    @Guide(description: "Contraseña inicial")
    var password: String
    @Guide(description: "Rol: 'admin' o 'editor'")
    var role: String
}

/// Only succeeds if the logged-in account is a superadmin (server-enforced
/// via `requireSuperAdmin`) — same restriction as the web's Usuarios page.
struct CrearUsuarioTool: Tool {
    let name = "crear_usuario"
    let description = "Crea un nuevo usuario del panel (solo disponible si el usuario actual es administrador)."
    typealias Arguments = CrearUsuarioArgs

    func call(arguments: CrearUsuarioArgs) async throws -> String {
        guard arguments.role == "admin" || arguments.role == "editor" else {
            return "Rol inválido: debe ser 'admin' o 'editor'."
        }
        struct Body: Encodable { let username: String, nombre: String, password: String, role: String }
        struct Resp: Decodable { let ok: Bool }
        let _: Resp = try await NoktaAPI.post("/api/usuarios", body: Body(
            username: arguments.username, nombre: arguments.nombre, password: arguments.password, role: arguments.role
        ))
        return "Usuario '\(arguments.username)' (\(arguments.nombre)) creado con rol \(arguments.role)."
    }
}
