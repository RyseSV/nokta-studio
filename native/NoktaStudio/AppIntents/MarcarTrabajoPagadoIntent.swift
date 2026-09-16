import AppIntents

/// "Oye Siri, marca pagado el trabajo de [cliente] en Nokta Studio."
struct MarcarTrabajoPagadoIntent: AppIntent {
    static var title: LocalizedStringResource = "Marcar trabajo como pagado"
    static var description = IntentDescription("Marca como pagado un trabajo pendiente de un cliente (no aplica a paquetes mensuales).")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Cliente")
    var cliente: String

    @Parameter(title: "Servicio", description: "Opcional, para desambiguar si el cliente tiene varios trabajos pendientes")
    var servicio: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Marcar pagado el trabajo de \(\.$cliente)") {
            \.$servicio
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await MarcarTrabajoPagadoCore.run(cliente: cliente, servicio: servicio)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}
