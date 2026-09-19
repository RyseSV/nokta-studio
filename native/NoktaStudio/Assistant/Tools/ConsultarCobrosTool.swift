import Foundation
import FoundationModels

@Generable
struct ConsultarCobrosArgs {
    @Guide(description: "Mes en formato YYYY-MM; vacío para el mes actual")
    var periodo: String?
    @Guide(description: "Nombre de cliente, coincidencia parcial; vacío para todos")
    var cliente: String?
}

struct ConsultarCobrosTool: Tool {
    let name = "consultar_cobros"
    let description = "Consulta cuánto deben, cobros y pagos pendientes con total y desglose verificable. Usa el mismo cálculo del Dashboard: próxima clase sin pagar y contratos activos."
    typealias Arguments = ConsultarCobrosArgs

    func call(arguments: ConsultarCobrosArgs) async throws -> String {
        try await Self.consultar(periodo: arguments.periodo, cliente: arguments.cliente)
    }

    static func consultar(periodo: String? = nil, cliente: String? = nil) async throws -> String {
        let solicitado = periodo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let mes = solicitado.isEmpty ? IngresosCalculator.periodoActual : solicitado
        guard mes.range(of: #"^\d{4}-(0[1-9]|1[0-2])$"#, options: .regularExpression) != nil else {
            throw ConsultaError.periodoInvalido
        }
            async let t: [NoktaTrabajo] = NoktaAPI.get("/api/trabajos")
            async let e: [NoktaClienteEstado] = NoktaAPI.get("/api/clientes-estados")
            let (trabajos, estados) = try await (t, e)
            let filtro = cliente?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let seleccion = filtro.isEmpty ? trabajos : trabajos.filter { $0.cliente.localizedCaseInsensitiveContains(filtro) }
            if !filtro.isEmpty && seleccion.isEmpty { return "No encontré trabajos para el cliente ‘\(filtro)’." }
            return IngresosCalculator.resumenCobros(mes, trabajos: seleccion, estados: estados)
    }

    enum ConsultaError: LocalizedError {
        case periodoInvalido
        var errorDescription: String? { "Indica el mes de cobro como YYYY-MM, por ejemplo 2026-09." }
    }
}
