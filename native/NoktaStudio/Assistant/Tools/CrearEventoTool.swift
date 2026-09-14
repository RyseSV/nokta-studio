import Foundation
import FoundationModels

@Generable
struct CrearEventoArgs {
    @Guide(description: "Nombre del cliente")
    var cliente: String
    @Guide(description: "Tipo de evento, ej. 'Fotografía de evento', 'Video de evento', 'Redes sociales', 'Edición de video', 'Paquete completo'")
    var tipo: String
    @Guide(description: "Fecha del evento en formato YYYY-MM-DD, extraída literalmente de lo que dijo el usuario (ej. si dice '2026-09-25', usa exactamente eso). Solo pregúntale la fecha si genuinamente no mencionó ninguna.")
    var fecha: String
    @Guide(description: "Hora de inicio, formato HH:MM, opcional")
    var horaInicio: String?
    @Guide(description: "Hora de fin, formato HH:MM, opcional")
    var horaFin: String?
    @Guide(description: "Lugar del evento, opcional")
    var lugar: String?
    @Guide(description: "Monto acordado en dólares, opcional")
    var monto: Double?
    @Guide(description: "Anticipo pagado en dólares, opcional")
    var anticipo: Double?
}

struct CrearEventoTool: Tool {
    let name = "crear_evento"
    let description = "Agrega un evento al calendario de Nokta Studio."
    typealias Arguments = CrearEventoArgs

    func call(arguments: CrearEventoArgs) async throws -> String {
        struct Body: Encodable {
            let titulo: String, tipo: String, fecha: String
            let horaInicio: String, horaFin: String, lugar: String
            let monto: Double, anticipo: Double
        }
        let body = Body(
            titulo: "\(arguments.cliente) — \(arguments.tipo)", tipo: arguments.tipo, fecha: arguments.fecha,
            horaInicio: arguments.horaInicio ?? "", horaFin: arguments.horaFin ?? "", lugar: arguments.lugar ?? "",
            monto: arguments.monto ?? 0, anticipo: arguments.anticipo ?? 0
        )
        struct Resp: Decodable { let ok: Bool }
        let _: Resp = try await NoktaAPI.post("/api/eventos", body: body)
        return "Evento agregado al calendario: \(arguments.cliente) — \(arguments.tipo), \(arguments.fecha)."
    }
}
