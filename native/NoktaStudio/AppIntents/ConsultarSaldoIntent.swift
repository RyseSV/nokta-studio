import AppIntents

/// "Oye Siri, ¿cuánto me deben en Nokta Studio?" — read-only, so it runs
/// without any confirmation. Mirrors the math ConsultarTrabajosTool /
/// the web dashboard use: non-quincena trabajos contribute their saldo,
/// grupo B (paquete mensual) trabajos contribute their unpaid quincenas.
struct ConsultarSaldoIntent: AppIntent {
    static var title: LocalizedStringResource = "Consultar saldo pendiente"
    static var description = IntentDescription("Dice cuánto dinero está pendiente de cobro en total en Nokta Studio.")
    static var openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("¿Cuánto me deben en Nokta Studio?")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trabajos: [NoktaTrabajo] = try await NoktaAPI.get("/api/trabajos")
        var total = 0.0
        var trabajosConSaldo = 0
        for t in trabajos {
            if t.grupoResuelto == "B" {
                let pendientes = (t.quincenas ?? []).filter { $0.estado != "pagado" && $0.estado != "oculta" }
                let subtotal = pendientes.reduce(0.0) { $0 + ($1.monto ?? 0) }
                if subtotal > 0 { total += subtotal; trabajosConSaldo += 1 }
            } else if let saldo = t.saldo, saldo > 0 {
                total += saldo
                trabajosConSaldo += 1
            }
        }
        let montoTxt = String(format: "%.2f", total)
        let message = trabajosConSaldo == 0
            ? "No tienes saldo pendiente de cobro en Nokta Studio."
            : "Tienes $\(montoTxt) pendientes de cobro entre \(trabajosConSaldo) trabajo\(trabajosConSaldo == 1 ? "" : "s")."
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}
