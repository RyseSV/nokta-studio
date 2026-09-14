import Foundation
import FoundationModels

@Generable
struct LineaServicioArgs {
    @Guide(description: "Descripción del servicio o producto")
    var descripcion: String
    @Guide(description: "Monto en dólares de esta línea")
    var monto: Double
}

@Generable
struct CrearDocumentoArgs {
    @Guide(description: "Tipo de documento: 'cotizacion' o 'recibo'")
    var tipo: String
    @Guide(description: "Nombre del cliente")
    var clienteNombre: String
    @Guide(description: "Empresa del cliente, opcional")
    var empresa: String?
    @Guide(description: "Líneas de servicio con descripción y monto cada una")
    var servicios: [LineaServicioArgs]
    @Guide(description: "Notas o condiciones, opcional")
    var notas: String?
}

/// Same endpoint the web's Documentos form posts to (auto-numbered
/// NK-COT-### / NK-REC-###). Unlike the web (which renders the PDF
/// client-side only when you click "Descargar"), this also renders the PDF
/// immediately and hands it to `onCreated` so the chat can show a
/// download card right away — see `AssistantViewModel.attachPDF`.
struct CrearDocumentoTool: Tool {
    let name = "crear_documento"
    let description = "Crea una cotización o un recibo de pago en Nokta Studio con líneas de servicio y total, y genera el PDF para descargar. Úsalo cuando el usuario pida generar una cotización o un recibo."
    typealias Arguments = CrearDocumentoArgs

    let onCreated: @Sendable (DocumentoParaPDF) -> Void

    func call(arguments: CrearDocumentoArgs) async throws -> String {
        guard arguments.tipo == "cotizacion" || arguments.tipo == "recibo" else {
            return "Tipo inválido: debe ser 'cotizacion' o 'recibo'."
        }
        guard !arguments.servicios.isEmpty else {
            return "No puedo crear un documento sin al menos una línea de servicio."
        }

        struct ServicioLinea: Encodable { let descripcion: String; let monto: Double }
        struct Body: Encodable {
            let tipo: String, clienteNombre: String, empresa: String?
            let fechaEmision: String, servicios: [ServicioLinea], total: Double, notas: String?
        }
        struct Resp: Decodable { let ok: Bool; let numero: String }

        let servicios = arguments.servicios.map { ServicioLinea(descripcion: $0.descripcion, monto: $0.monto) }
        let total = servicios.reduce(0.0) { $0 + $1.monto }
        let df = ISO8601DateFormatter()
        let fecha = String(df.string(from: Date()).prefix(10))

        let body = Body(
            tipo: arguments.tipo, clienteNombre: arguments.clienteNombre, empresa: arguments.empresa,
            fechaEmision: fecha, servicios: servicios, total: total, notas: arguments.notas
        )
        let resp: Resp = try await NoktaAPI.post("/api/documentos", body: body)

        let doc = DocumentoParaPDF(
            numero: resp.numero, tipo: arguments.tipo, clienteNombre: arguments.clienteNombre,
            empresa: arguments.empresa, telefono: nil, email: nil, fechaEmision: fecha,
            servicios: arguments.servicios.map { ($0.descripcion, $0.monto) }, notas: arguments.notas
        )
        onCreated(doc)

        let titulo = arguments.tipo == "cotizacion" ? "Cotización" : "Recibo"
        return "\(titulo) \(resp.numero) creado para \(arguments.clienteNombre) por un total de $\(String(format: "%.2f", total)). Te dejo el PDF arriba para descargar."
    }
}
