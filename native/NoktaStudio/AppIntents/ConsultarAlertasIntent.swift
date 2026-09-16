import AppIntents

/// "Oye Siri, ¿qué alertas tengo en Nokta Studio?" — read-only summary of
/// unread alerts, same data ConsultarAlertasTool reads for the in-app chat.
struct ConsultarAlertasIntent: AppIntent {
    static var title: LocalizedStringResource = "Consultar alertas"
    static var description = IntentDescription("Resume las alertas sin leer de Nokta Studio.")
    static var openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("¿Qué alertas tengo en Nokta Studio?")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let alertas: [NoktaAlerta] = try await NoktaAPI.get("/api/alertas")
        let sinLeer = alertas.filter { !$0.leida }
        guard !sinLeer.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: "No tienes alertas sin leer en Nokta Studio."))
        }
        let etiquetas: [String: String] = [
            "descarga": "descarga de galería", "link_venciendo": "link por vencer",
            "pago_pendiente": "pago pendiente", "evento_proximo": "evento próximo",
            "quincena_vencida": "quincena sin pagar",
        ]
        let resumen = Dictionary(grouping: sinLeer, by: { $0.tipo })
            .map { tipo, items in "\(items.count) \(etiquetas[tipo] ?? tipo)\(items.count == 1 ? "" : "s")" }
            .joined(separator: ", ")
        let message = "Tienes \(sinLeer.count) alerta\(sinLeer.count == 1 ? "" : "s") sin leer: \(resumen)."
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}
