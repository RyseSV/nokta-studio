import Foundation
import FoundationModels

@Generable
struct RegistrarGastoArgs {
    @Guide(description: "Descripción del gasto")
    var concepto: String
    @Guide(description: "Categoría: Equipo, Transporte, Software, Marketing, u Otros")
    var categoria: String
    @Guide(description: "Monto en dólares")
    var monto: Double
    @Guide(description: "Fecha en formato YYYY-MM-DD, SOLO si el usuario menciona una fecha explícita (ej. 'el 3 de marzo', 'ayer'). Si el usuario NO menciona ninguna fecha, deja este campo completamente vacío/nulo — NUNCA inventes ni asumas un día como el 1 del mes; el sistema usará automáticamente la fecha de hoy.")
    var fecha: String?
}

struct RegistrarGastoTool: Tool {
    let name = "registrar_gasto"
    let description = "Registra un gasto del negocio (equipo, transporte, software, marketing, u otros)."
    typealias Arguments = RegistrarGastoArgs

    func call(arguments: RegistrarGastoArgs) async throws -> String {
        let fecha = arguments.fecha ?? String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        struct Body: Encodable { let concepto: String; let categoria: String; let monto: Double; let fecha: String }
        struct Resp: Decodable { let ok: Bool }
        let _: Resp = try await NoktaAPI.post("/api/gastos", body: Body(concepto: arguments.concepto, categoria: arguments.categoria, monto: arguments.monto, fecha: fecha))
        return "Gasto registrado: \(arguments.concepto) — $\(String(format: "%.2f", arguments.monto)) (\(arguments.categoria))."
    }
}
