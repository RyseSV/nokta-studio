import Foundation
import FoundationModels

@Generable
struct MarcarTrabajoPagadoArgs {
    @Guide(description: "Nombre del cliente")
    var cliente: String
    @Guide(description: "Servicio del trabajo que se pagó; no inventarlo")
    var servicio: String?
    @Guide(description: "Fecha YYYY-MM-DD de la clase que el usuario pagó; omitir si no la indicó")
    var fechaSesion: String?
    @Guide(description: "true solo si el usuario pide explícitamente pagar la próxima sesión; nunca inferirlo")
    var proximaSesion: Bool?
    @Guide(description: "Monto del pago indicado por el usuario, solo para identificar la sesión; nunca cambiar su precio")
    var monto: Double?
}

struct MarcarTrabajoPagadoTool: Tool {
    let name = "marcar_trabajo_pagado"
    let description = "Registra un pago explícitamente solicitado de un trabajo existente o de una sesión concreta. Si hay varias clases pendientes pide su fecha; nunca paga todas. Paquetes mensuales usan registrar_pago_quincena."
    typealias Arguments = MarcarTrabajoPagadoArgs

    func call(arguments: MarcarTrabajoPagadoArgs) async throws -> String {
        try await MarcarTrabajoPagadoCore.run(cliente: arguments.cliente, servicio: arguments.servicio, fechaSesion: arguments.fechaSesion, proximaSesion: arguments.proximaSesion ?? false, monto: arguments.monto)
    }
}

enum MarcarTrabajoPagadoCore {
    enum Seleccion {
        case aclarar(String)
        case trabajo(Int)
        case sesion(trabajo: Int, sesion: Int)
    }

    static func seleccionar(trabajos: [NoktaTrabajo], cliente: String, servicio: String?, fechaSesion: String?, proximaSesion: Bool, monto: Double? = nil) -> Seleccion {
        let fechaLimpia = fechaSesion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fechaSesion = fechaLimpia?.isEmpty == false ? fechaLimpia : nil
        let clientes = ClienteResolver.resolver(cliente, nombres: trabajos.map(\.cliente))
        let nombre: String
        switch clientes {
        case .encontrado(let n): nombre = n
        case .ambiguo(let opciones): return .aclarar("Hay varios clientes que coinciden: \(opciones.joined(separator: ", ")). Indica el nombre completo.")
        case .noEncontrado: return .aclarar("No encontré al cliente ‘\(cliente)’. Indica su nombre registrado.")
        }
        var candidatos = trabajos.indices.filter { trabajos[$0].cliente == nombre }
        if let servicio, !servicio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidatos = candidatos.filter { trabajos[$0].servicio.localizedCaseInsensitiveContains(servicio) }
        }
        candidatos = candidatos.filter { i in
            let t = trabajos[i]
            if let sesiones = t.sesiones, !sesiones.isEmpty { return sesiones.contains { $0.estado == "pendiente" } }
            return t.estado == "pendiente" || t.grupoResuelto == "B"
        }
        guard !candidatos.isEmpty else { return .aclarar("No encontré pagos pendientes para ese cliente y servicio.") }
        if let fechaSesion, !fechaSesion.isEmpty {
            candidatos = candidatos.filter { i in
                let t = trabajos[i]
                if let sesiones = t.sesiones, !sesiones.isEmpty { return sesiones.contains { $0.fecha == fechaSesion && $0.estado == "pendiente" } }
                return t.fecha == fechaSesion
            }
        }
        if let monto {
            guard monto.isFinite, monto > 0 else { return .aclarar("Indica un monto de pago válido.") }
            candidatos = candidatos.filter { i in
                let t = trabajos[i]
                if let sesiones = t.sesiones, !sesiones.isEmpty {
                    return sesiones.contains { $0.estado == "pendiente" && $0.monto == monto && (fechaSesion == nil || $0.fecha == fechaSesion) }
                }
                return t.saldo == monto || t.monto == monto
            }
        }
        guard !candidatos.isEmpty else { return .aclarar("No encontré una sesión o trabajo pendiente en esa fecha. No registré ningún pago.") }
        guard candidatos.count == 1 else {
            let lista = candidatos.map { "- \(trabajos[$0].servicio) · \(trabajos[$0].fecha ?? "sin fecha")" }.joined(separator: "\n")
            return .aclarar("Hay varios trabajos pendientes de \(nombre). Indica el servicio y la fecha:\n" + lista)
        }
        let indice = candidatos[0]
        let t = trabajos[indice]
        guard t.grupoResuelto != "B" else { return .aclarar("Este es un paquete mensual: indica mes y quincena y usa registrar_pago_quincena.") }
        if let sesiones = t.sesiones, !sesiones.isEmpty {
            var indices = sesiones.indices.filter { sesiones[$0].estado == "pendiente" }
            if let fechaSesion, !fechaSesion.isEmpty { indices = indices.filter { sesiones[$0].fecha == fechaSesion } }
            if let monto { indices = indices.filter { sesiones[$0].monto == monto } }
            if proximaSesion && fechaSesion == nil {
                let orden = indices.sorted { sesiones[$0].fecha < sesiones[$1].fecha }
                if let primero = orden.first { indices = orden.filter { sesiones[$0].fecha == sesiones[primero].fecha } }
            }
            guard indices.count == 1 else {
                let fechas = indices.map { sesiones[$0].fecha }.joined(separator: ", ")
                return .aclarar("Hay varias sesiones pendientes (\(fechas)). Indica la fecha de la que se pagó; no marqué ninguna.")
            }
            return .sesion(trabajo: indice, sesion: indices[0])
        }
        return .trabajo(indice)
    }

    static func run(cliente: String, servicio: String?, fechaSesion: String? = nil, proximaSesion: Bool = false, monto: Double? = nil) async throws -> String {
        let trabajos: [NoktaTrabajo] = try await NoktaAPI.get("/api/trabajos")
        struct Resp: Decodable { let ok: Bool }
        switch seleccionar(trabajos: trabajos, cliente: cliente, servicio: servicio, fechaSesion: fechaSesion, proximaSesion: proximaSesion, monto: monto) {
        case .aclarar(let mensaje): return mensaje
        case .sesion(let trabajo, let indice):
            let t = trabajos[trabajo]
            var sesiones = t.sesiones ?? []
            guard let montoSesion = sesiones[indice].monto, montoSesion.isFinite, montoSesion > 0 else { return "La sesión no tiene un monto válido. Corrígelo antes de registrar el pago." }
            sesiones[indice].estado = "pagado"
            sesiones[indice].fechaPago = ISO8601DateFormatter().string(from: Date())
            struct Body: Encodable { let sesiones: [NoktaSesion] }
            let respuesta: Resp = try await NoktaAPI.patch("/api/trabajos/\(t.id)/sesiones", body: Body(sesiones: sesiones))
            guard respuesta.ok else { return "El servidor no confirmó el pago. Revisa la sesión antes de intentarlo de nuevo." }
            return "Sesión del \(sesiones[indice].fecha) de \(t.cliente) marcada pagada: $\(String(format: "%.2f", sesiones[indice].monto ?? 0))."
        case .trabajo(let indice):
            let t = trabajos[indice]
            guard let monto = t.monto, monto.isFinite, monto > 0 else { return "El trabajo no tiene un monto válido. Corrígelo antes de registrar el pago." }
            let fields: [String: AnyEncodableValue] = ["estado": .string("pagado"), "anticipo": .double(monto), "saldo": .double(0)]
            let respuesta: Resp = try await NoktaAPI.put("/api/trabajos/\(t.id)", body: AnyEncodableDict(fields))
            guard respuesta.ok else { return "El servidor no confirmó el pago del trabajo." }
            return "‘\(t.servicio)’ de \(t.cliente) marcado como pagado ($\(String(format: "%.2f", monto)))."
        }
    }
}
