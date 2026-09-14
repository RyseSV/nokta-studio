import Foundation
import FoundationModels

@Generable
struct ConsultarClientesArgs {
    @Guide(description: "Filtrar por estado de relación: 'activo', 'pausado', 'cancelado', o vacío para todos")
    var estado: String?
}

struct ConsultarClientesTool: Tool {
    let name = "consultar_clientes"
    let description = "Consulta los clientes de galería y su estado de relación (activo, pausado, cancelado) y notas. Útil para responder qué clientes están pausados/cancelados o por qué."
    typealias Arguments = ConsultarClientesArgs

    func call(arguments: ConsultarClientesArgs) async throws -> String {
        async let clientesTask: [NoktaCliente] = NoktaAPI.get("/api/clientes")
        async let estadosTask: [NoktaClienteEstado] = NoktaAPI.get("/api/clientes-estados")
        let (clientes, estados) = try await (clientesTask, estadosTask)

        let estadoMap = Dictionary(uniqueKeysWithValues: estados.map { ($0.nombre, $0) })
        let nombres = Set(clientes.map(\.nombre)).union(estados.map(\.nombre))

        var rows = nombres.map { nombre -> (String, String, String?) in
            let e = estadoMap[nombre]
            return (nombre, e?.estado ?? "activo", e?.notas)
        }
        if let filtro = arguments.estado, !filtro.isEmpty {
            rows = rows.filter { $0.1 == filtro }
        }
        if rows.isEmpty { return "No se encontraron clientes con ese estado." }
        let lines = rows.sorted { $0.0 < $1.0 }.map { nombre, estado, notas -> String in
            var line = "- \(nombre): \(estado)"
            if let notas, !notas.isEmpty { line += " — nota: \(notas)" }
            return line
        }
        return lines.joined(separator: "\n")
    }
}
