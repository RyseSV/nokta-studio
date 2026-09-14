import Foundation

/// Mirrors the client-side `SVC_GRUPO` lookup in admin.html — infers a
/// Trabajo's grupo (A–E) from its servicio name so the Assistant can create
/// jobs the same way the "Nuevo trabajo" form does.
enum ServicioGrupoMap {
    static let map: [String: String] = [
        "Fotografía de eventos": "A", "Fotografía corporativa": "A", "Fotografía de producto": "A",
        "Fotografía gastronómica": "A", "Retratos": "A", "Cobertura audiovisual": "A", "Foto + Video": "A",
        "Fotografía de evento": "A", "Video de evento": "A",
        "Marketing digital": "B", "Gestión de redes": "B", "Community management": "B",
        "Paquete completo": "B", "Redes sociales": "B",
        "Edición de video": "C", "Motion graphics": "C", "Reels sueltos": "C",
        "Identidad visual": "D", "Branding": "D",
        "Diseño y desarrollo web": "E",
    ]
    static let nombres: [String: String] = [
        "A": "Eventos", "B": "Paquetes mensuales", "C": "Edición de video",
        "D": "Branding / Identidad", "E": "Desarrollo web",
    ]
    static func grupo(for servicio: String) -> String { map[servicio] ?? "A" }
}
