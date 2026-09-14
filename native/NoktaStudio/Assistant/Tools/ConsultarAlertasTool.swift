import Foundation
import FoundationModels

@Generable
struct ConsultarAlertasArgs {
    @Guide(description: "Si es true, solo muestra alertas no leídas")
    var soloNoLeidas: Bool?
}

struct ConsultarAlertasTool: Tool {
    let name = "consultar_alertas"
    let description = "Consulta las alertas del panel: links por vencer, pagos pendientes, quincenas sin pagar, eventos próximos, descargas de galería. Útil para resumir pendientes urgentes."
    typealias Arguments = ConsultarAlertasArgs

    func call(arguments: ConsultarAlertasArgs) async throws -> String {
        let alertas: [NoktaAlerta] = try await NoktaAPI.get("/api/alertas")
        var filtered = alertas
        if arguments.soloNoLeidas == true {
            filtered = filtered.filter { !$0.leida }
        }
        if filtered.isEmpty { return "No hay alertas." }
        let lines = filtered.prefix(40).map { a -> String in
            let desc = a.datos.mensaje ?? [a.datos.cliente ?? a.datos.nombre, a.datos.servicio].compactMap { $0 }.joined(separator: " — ")
            return "- [\(a.tipo)] \(desc) (\(a.leida ? "leída" : "no leída"))"
        }
        return "\(filtered.count) alerta(s).\n" + lines.joined(separator: "\n")
    }
}
