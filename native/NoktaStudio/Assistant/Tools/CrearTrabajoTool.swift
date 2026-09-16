import Foundation
import FoundationModels

@Generable
struct CrearTrabajoArgs {
    @Guide(description: "Nombre del cliente")
    var cliente: String
    @Guide(description: """
    Servicio exacto. Eventos: 'Fotografía de eventos', 'Fotografía corporativa', 'Fotografía de producto', \
    'Fotografía gastronómica', 'Retratos', 'Cobertura audiovisual', 'Foto + Video', 'Clases' (para ingresos \
    por dar clases o capacitaciones, ej. clases de IA). Paquetes mensuales: \
    'Marketing digital', 'Gestión de redes', 'Community management', 'Paquete completo'. Edición de video: \
    'Edición de video', 'Motion graphics', 'Reels sueltos'. Branding: 'Identidad visual', 'Branding'. Web: \
    'Diseño y desarrollo web'.
    """)
    var servicio: String
    @Guide(description: "Fecha del evento/entrega/inicio de contrato, formato YYYY-MM-DD, SOLO si el usuario la mencionó explícitamente. Si no la mencionó, deja este campo vacío/nulo y pregúntale la fecha en tu respuesta en vez de adivinar una — nunca asumas el día 1 del mes ni la fecha de hoy para esto.")
    var fecha: String?
    @Guide(description: "Monto total en dólares (no aplica igual para paquetes mensuales, ahí usa pagoMensual)")
    var monto: Double?
    @Guide(description: "Anticipo pagado, en dólares")
    var anticipo: Double?
    @Guide(description: "Solo para paquetes mensuales (grupo B): pago mensual en dólares")
    var pagoMensual: Double?
    @Guide(description: "Solo para paquetes mensuales: día del mes en que se cobra (1-31)")
    var diaCobro: Int?
    @Guide(description: "Empresa del cliente, si aplica")
    var empresa: String?
    @Guide(description: "Lugar del evento, si aplica")
    var lugar: String?
    @Guide(description: "Notas adicionales")
    var notas: String?
}

/// Creates a Trabajo the same way the "Nuevo trabajo" page does — infers
/// grupo (A–E) from servicio and fills only the fields that group uses.
struct CrearTrabajoTool: Tool {
    let name = "crear_trabajo"
    let description = "Crea un nuevo trabajo/proyecto para un cliente (evento, paquete mensual, edición de video, branding o desarrollo web)."
    typealias Arguments = CrearTrabajoArgs

    func call(arguments: CrearTrabajoArgs) async throws -> String {
        let grupo = ServicioGrupoMap.grupo(for: arguments.servicio)
        let monto = arguments.pagoMensual ?? arguments.monto ?? 0
        let anticipo = arguments.anticipo ?? 0

        var fields: [String: AnyEncodableValue] = [
            "id": .string("t\(Int(Date().timeIntervalSince1970 * 1000))"),
            "cliente": .string(arguments.cliente),
            "servicio": .string(arguments.servicio),
            "grupo": .string(grupo),
            "grupoNombre": .string(ServicioGrupoMap.nombres[grupo] ?? grupo),
            "estado": .string("pendiente"),
            "monto": .double(monto),
            "anticipo": .double(anticipo),
            "saldo": .double(max(0, monto - anticipo)),
            "creado": .string(ISO8601DateFormatter().string(from: Date())),
        ]
        if let fecha = arguments.fecha { fields["fecha"] = .string(fecha) }
        if let notas = arguments.notas { fields["notas"] = .string(notas) }
        if let empresa = arguments.empresa { fields["empresa"] = .string(empresa) }
        if let lugar = arguments.lugar { fields["lugar"] = .string(lugar) }

        if grupo == "B" {
            fields["pagoMensual"] = .double(monto)
            fields["fechaInicio"] = .string(arguments.fecha ?? "")
            fields["estadoContrato"] = .string("activo")
            if let dia = arguments.diaCobro { fields["diaCobro"] = .int(dia) }
        }

        struct Resp: Decodable { let ok: Bool }
        let _: Resp = try await NoktaAPI.post("/api/trabajos", body: AnyEncodableDict(fields))
        return "Trabajo creado: \(arguments.cliente) — \(arguments.servicio), monto $\(String(format: "%.2f", monto))."
    }
}

/// Minimal type-erased JSON value for building request bodies whose field
/// set depends on the Trabajo's grupo (A–E) — mirrors the same trick used
/// by the (now-removed) SwiftUI Nuevo Trabajo form.
enum AnyEncodableValue {
    case string(String), double(Double), int(Int), bool(Bool)
}

struct AnyEncodableDict: Encodable {
    let fields: [String: AnyEncodableValue]
    init(_ fields: [String: AnyEncodableValue]) { self.fields = fields }
    struct Key: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        for (key, value) in fields {
            guard let codingKey = Key(stringValue: key) else { continue }
            switch value {
            case .string(let s): try container.encode(s, forKey: codingKey)
            case .double(let d): try container.encode(d, forKey: codingKey)
            case .int(let i): try container.encode(i, forKey: codingKey)
            case .bool(let b): try container.encode(b, forKey: codingKey)
            }
        }
    }
}
