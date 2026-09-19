import Foundation
import FoundationModels

@Generable
struct MarcarAlertaLeidaArgs {
    @Guide(description: "Si es true, marca TODAS las alertas como leídas. Si es false, describe qué alerta específica marcar en 'descripcion'.")
    var todas: Bool
    @Guide(description: "Texto para identificar una alerta específica (ej. nombre del cliente o parte del mensaje), si 'todas' es false")
    var descripcion: String?
}

/// Preserve read records so automatic alerts are not recreated on the next fetch.
struct MarcarAlertaLeidaTool: Tool {
    let name = "marcar_alerta_leida"
    let description = "Marca como leídas (o descarta) las alertas del panel: todas de una vez, o una específica que coincida con una descripción."
    typealias Arguments = MarcarAlertaLeidaArgs

    func call(arguments: MarcarAlertaLeidaArgs) async throws -> String {
        if arguments.todas {
            struct Resp: Decodable { let ok: Bool }
            let _: Resp = try await NoktaAPI.put("/api/alertas/leer", body: EmptyBody())
            return "Todas las alertas fueron marcadas como leídas."
        }
        guard let descripcion = arguments.descripcion, !descripcion.isEmpty else {
            return "Decime qué alerta marcar, o pedime marcar todas."
        }
        let alertas: [NoktaAlerta] = try await NoktaAPI.get("/api/alertas")
        guard let a = alertas.first(where: { alerta in
            !alerta.leida && [alerta.datos.cliente, alerta.datos.nombre, alerta.datos.mensaje, alerta.datos.servicio]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(descripcion) }
        }) else {
            return "No encontré una alerta que coincida con '\(descripcion)'."
        }
        struct Resp: Decodable { let ok: Bool }
        let _: Resp = try await NoktaAPI.put("/api/alertas/\(a.id)/leer", body: EmptyBody())
        return "Alerta marcada como leída."
    }
}

private struct EmptyBody: Encodable {}
