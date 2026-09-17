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
    @Guide(description: "Fecha de la sesión/entrega/inicio de contrato, formato YYYY-MM-DD, extraída literalmente de lo que dijo el usuario en cualquier formato (ej. 'el sábado 12', '2026-09-12', '12 de septiembre') — conviértela tú mismo a YYYY-MM-DD, nunca vuelvas a preguntarla si ya aparece en el mensaje. Deja este campo vacío/nulo SOLO si el usuario genuinamente no mencionó ninguna fecha; en ese caso pregúntale antes de crear el trabajo — nunca asumas el día 1 del mes ni la fecha de hoy.")
    var fecha: String?
    @Guide(description: "Monto total en dólares (no aplica igual para paquetes mensuales, ahí usa pagoMensual)")
    var monto: Double?
    @Guide(description: "Anticipo pagado, en dólares")
    var anticipo: Double?
    @Guide(description: "true SOLO si el usuario dice explícitamente que ya se pagó / que lo marques como pagado (ej. 'y márcalo como pagado', 'ya me pagaron'). Si es true y no diste anticipo, se usa el monto completo como anticipo — no hace falta un segundo paso para marcarlo pagado.")
    var pagado: Bool?
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
    let description = """
    Registra un INGRESO/trabajo financiero para un cliente (evento, clase, paquete mensual, edición de video, \
    branding o desarrollo web) — crea el registro que cuenta para dashboard, saldo pendiente y facturación. \
    Usa esta herramienta (no crear_evento) siempre que el usuario diga 'trabajo', 'cobro', 'clase', 'venta', \
    'ingreso' o pida registrar un pago, incluso si el servicio tiene fecha/hora como un evento. Puedes marcarlo \
    pagado en la misma llamada con el argumento 'pagado' — no hace falta una segunda herramienta para eso.
    """
    typealias Arguments = CrearTrabajoArgs

    func call(arguments: CrearTrabajoArgs) async throws -> String {
        let grupo = ServicioGrupoMap.grupo(for: arguments.servicio)
        let monto = arguments.pagoMensual ?? arguments.monto ?? 0
        let pagado = arguments.pagado ?? false
        let anticipo = arguments.anticipo ?? (pagado ? monto : 0)

        var fields: [String: AnyEncodableValue] = [
            "id": .string("t\(Int(Date().timeIntervalSince1970 * 1000))"),
            "cliente": .string(arguments.cliente),
            "servicio": .string(arguments.servicio),
            "grupo": .string(grupo),
            "grupoNombre": .string(ServicioGrupoMap.nombres[grupo] ?? grupo),
            "estado": .string(pagado ? "pagado" : "pendiente"),
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
        let estadoTxt = pagado ? "pagado" : "pendiente"
        return "Trabajo creado: \(arguments.cliente) — \(arguments.servicio), monto $\(String(format: "%.2f", monto)), estado \(estadoTxt)."
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
