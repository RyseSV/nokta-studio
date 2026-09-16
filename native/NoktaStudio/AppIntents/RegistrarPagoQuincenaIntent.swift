import AppIntents

/// "Oye Siri, TuBoleto pagó en Nokta Studio" — runs the exact same logic as
/// the in-app Asistente's registrar_pago_quincena tool (see
/// RegistrarPagoQuincenaCore), so a quincena payment can be logged and its
/// recibo generated without opening the app. Cookie auth is transparent:
/// NoktaAPI syncs the session cookie from the WKWebView's persistent cookie
/// store on every call, so this works as long as the user has logged into
/// the app at least once.
struct RegistrarPagoQuincenaIntent: AppIntent {
    static var title: LocalizedStringResource = "Registrar pago de quincena"
    static var description = IntentDescription("Marca como pagada la quincena pendiente de un cliente con paquete mensual y genera su recibo.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Cliente")
    var cliente: String

    static var parameterSummary: some ParameterSummary {
        Summary("Registrar pago de \(\.$cliente) en Nokta Studio")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try await RegistrarPagoQuincenaCore.run(cliente: cliente)
        return .result(dialog: IntentDialog(stringLiteral: result.message))
    }
}
