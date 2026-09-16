import AppIntents

enum GastoCategoria: String, AppEnum {
    case equipo = "Equipo"
    case transporte = "Transporte"
    case software = "Software"
    case marketing = "Marketing"
    case otros = "Otros"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Categoría de gasto"
    static var caseDisplayRepresentations: [GastoCategoria: DisplayRepresentation] = [
        .equipo: "Equipo",
        .transporte: "Transporte",
        .software: "Software",
        .marketing: "Marketing",
        .otros: "Otros",
    ]
}

/// "Oye Siri, registra un gasto en Nokta Studio."
struct RegistrarGastoIntent: AppIntent {
    static var title: LocalizedStringResource = "Registrar gasto"
    static var description = IntentDescription("Registra un gasto del negocio en Nokta Studio.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Concepto")
    var concepto: String

    @Parameter(title: "Categoría", default: .otros)
    var categoria: GastoCategoria

    @Parameter(title: "Monto", controlStyle: .field)
    var monto: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Registrar gasto de \(\.$monto) por \(\.$concepto)") {
            \.$categoria
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await RegistrarGastoCore.run(concepto: concepto, categoria: categoria.rawValue, monto: monto, fecha: nil)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}
