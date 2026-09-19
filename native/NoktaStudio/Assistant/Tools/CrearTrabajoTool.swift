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
    Crea un trabajo o una sesión nueva SOLO cuando el usuario lo solicita explícitamente. \
    Una frase como 'Fátima ya me pagó' registra el pago de una sesión existente con marcar_trabajo_pagado; \
    NO crea un nuevo trabajo. Exige fecha y monto indicados; no inventes valores. \
    Para consultas de cobros pendientes usa consultar_cobros.
    """
    typealias Arguments = CrearTrabajoArgs

    func call(arguments: CrearTrabajoArgs) async throws -> String {
        let grupo = ServicioGrupoMap.grupo(for: arguments.servicio)
        let montoSolicitado = grupo == "B" ? (arguments.pagoMensual ?? arguments.monto) : arguments.monto
        if let error = CrearTrabajoValidacion.error(cliente: arguments.cliente, servicio: arguments.servicio, fecha: arguments.fecha, monto: montoSolicitado, anticipo: arguments.anticipo, pagado: arguments.pagado) { return error }
        guard let monto = montoSolicitado else { return "Indica el monto para crear el trabajo." }
        let pagado = arguments.pagado ?? (arguments.anticipo == monto)
        let anticipo = arguments.anticipo ?? (pagado ? monto : 0)

        // 'Clases' es recurrente (ej. clase semanal): cada pago nuevo es una
        // SESIÓN dentro del mismo trabajo del cliente, igual que hace el
        // panel "Sesiones" en admin.html — no un trabajo separado por cada
        // fecha, o el dashboard y el historial del cliente se duplican.
        if arguments.servicio == "Clases" {
            if let anticipo = arguments.anticipo, anticipo > 0, anticipo < monto {
                return "Las sesiones registran pagos completos. Indica si la nueva clase está pagada o pendiente; no registré un anticipo parcial."
            }
            return try await agregarSesion(arguments: arguments, monto: monto, pagado: pagado)
        }

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
        let respuesta: Resp = try await NoktaAPI.post("/api/trabajos", body: AnyEncodableDict(fields))
        guard respuesta.ok else { return "El servidor no confirmó la creación. Revisa Trabajos antes de intentarlo de nuevo." }
        let estadoTxt = pagado ? "pagado" : "pendiente"
        return "Trabajo creado: \(arguments.cliente) — \(arguments.servicio), monto $\(String(format: "%.2f", monto)), estado \(estadoTxt)."
    }

    private func agregarSesion(arguments: CrearTrabajoArgs, monto: Double, pagado: Bool) async throws -> String {
        guard let fecha = arguments.fecha else { return "Indica la fecha de la nueva sesión." }
        let ahora = ISO8601DateFormatter().string(from: Date())
        let nuevaSesion = NoktaSesion(
            id: "s\(Int(Date().timeIntervalSince1970 * 1000))",
            fecha: fecha, monto: monto,
            estado: pagado ? "pagado" : "pendiente",
            fechaPago: pagado ? ahora : nil
        )

        let trabajos: [NoktaTrabajo] = try await NoktaAPI.get("/api/trabajos")
        let resultado = ClienteResolver.resolver(arguments.cliente, nombres: trabajos.map(\.cliente))
        let nombre: String
        switch resultado {
        case .encontrado(let existente): nombre = existente
        case .ambiguo(let opciones): return "Hay varios clientes: \(opciones.joined(separator: ", ")). Indica el nombre completo."
        case .noEncontrado: nombre = arguments.cliente
        }
        let candidatos = trabajos.filter { $0.servicio == "Clases" && $0.cliente == nombre }
        guard candidatos.count <= 1 else { return "Hay varios trabajos de clases de \(nombre). Indica el trabajo exacto desde Trabajos antes de agregar una sesión." }
        let existente = candidatos.first
        if candidatos.contains(where: { t in
            (t.sesiones ?? []).contains { $0.fecha == fecha } || ((t.sesiones ?? []).isEmpty && t.fecha == fecha)
        }) {
            return "Ya existe una clase de \(nombre) el \(fecha). No creé otra. Si estás registrando su pago, usa marcar_trabajo_pagado con esa fecha."
        }

        struct SesionesBody: Encodable { let sesiones: [NoktaSesion] }
        struct Resp: Decodable { let ok: Bool }

        if let t = existente {
            var sesiones = t.sesiones ?? []
            if sesiones.isEmpty {
                guard let fechaAnterior = t.fecha, CrearTrabajoValidacion.fechaValida(fechaAnterior), let montoAnterior = t.monto, montoAnterior.isFinite, montoAnterior > 0 else {
                    return "El trabajo anterior no tiene fecha o monto válido. Corrígelo desde Trabajos antes de agregar una nueva sesión."
                }
                // El trabajo ya existía de antes del panel de Sesiones (un solo
                // pago suelto) — lo convertimos en la primera sesión, igual que
                // _autoGenerarSesiones en admin.html, antes de agregar la nueva.
                sesiones = [NoktaSesion(
                    id: "s\(Int((ISO8601DateFormatter().date(from: t.creado ?? ahora) ?? Date()).timeIntervalSince1970 * 1000))",
                    fecha: fechaAnterior, monto: montoAnterior,
                    estado: t.estado,
                    fechaPago: t.estado == "pagado" ? (t.creado ?? ahora) : nil
                )]
            }
            sesiones.append(nuevaSesion)
            let respuesta: Resp = try await NoktaAPI.patch("/api/trabajos/\(t.id)/sesiones", body: SesionesBody(sesiones: sesiones))
            guard respuesta.ok else { return "El servidor no confirmó la nueva sesión. Revisa Trabajos antes de intentarlo de nuevo." }
            let estadoTxt = pagado ? "pagado" : "pendiente"
            return "Sesión agregada al trabajo de \(arguments.cliente) — \(fecha), $\(String(format: "%.2f", monto)), estado \(estadoTxt)."
        }

        let grupo = ServicioGrupoMap.grupo(for: "Clases")
        let fields: [String: AnyEncodableValue] = [
            "id": .string("t\(Int(Date().timeIntervalSince1970 * 1000))"),
            "cliente": .string(nombre),
            "servicio": .string("Clases"),
            "grupo": .string(grupo),
            "grupoNombre": .string(ServicioGrupoMap.nombres[grupo] ?? grupo),
            "estado": .string(pagado ? "pagado" : "pendiente"),
            "monto": .double(monto),
            "anticipo": .double(pagado ? monto : 0),
            "saldo": .double(pagado ? 0 : monto),
            "fecha": .string(fecha),
            "creado": .string(ahora),
        ]
        let respuesta: Resp = try await NoktaAPI.post("/api/trabajos", body: AnyEncodableDict(fields))
        guard respuesta.ok else { return "El servidor no confirmó la creación. Revisa Trabajos antes de intentarlo de nuevo." }
        let estadoTxt = pagado ? "pagado" : "pendiente"
        return "Trabajo creado: \(arguments.cliente) — Clases, $\(String(format: "%.2f", monto)), estado \(estadoTxt)."
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

/// Validation happens before all API writes; missing values never become defaults.
enum CrearTrabajoValidacion {
    static func fechaValida(_ fecha: String) -> Bool {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        f.isLenient = false
        guard let date = f.date(from: fecha) else { return false }
        return f.string(from: date) == fecha
    }

    static func error(cliente: String, servicio: String, fecha: String?, monto: Double?, anticipo: Double?, pagado: Bool? = nil) -> String? {
        guard !cliente.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Indica el nombre del cliente." }
        guard !servicio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Indica el servicio del nuevo trabajo." }
        guard let fecha, fechaValida(fecha) else { return "Indica una fecha válida para el nuevo trabajo o sesión (YYYY-MM-DD). No creé ningún registro." }
        guard let monto, monto.isFinite, monto > 0 else { return "Indica un monto mayor que cero para el nuevo trabajo o sesión. No creé ningún registro." }
        if let anticipo, !anticipo.isFinite || anticipo < 0 || anticipo > monto { return "El anticipo debe estar entre cero y el monto total." }
        if pagado == true, let anticipo, anticipo != monto {
            return "Indicaste que está pagado, pero el anticipo no coincide con el monto total. Confirma el importe pagado; no creé ningún registro."
        }
        if pagado == false, anticipo == monto {
            return "Indicaste pendiente, pero el anticipo cubre el total. Confirma si el trabajo está pagado; no creé ningún registro."
        }
        return nil
    }
}
