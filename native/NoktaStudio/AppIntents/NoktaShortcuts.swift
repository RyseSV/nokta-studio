import AppIntents

/// Registers Nokta Studio's App Intents with Siri/Shortcuts. Phrases use
/// ${applicationName} so they stay correct if the app's display name ever
/// changes. Kept to the four intents that are safe to run without opening
/// the app: two writes that mirror buttons already in the web panel
/// (marcar pagado, registrar gasto — no destructive/irreversible action is
/// exposed here), the quincena/factura flow the user specifically asked
/// for, and two read-only queries.
struct NoktaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // `cliente` is a plain String, and App Intents only allows AppEntity/
        // AppEnum parameters to be embedded directly in a phrase — so these
        // phrases don't mention the client; Siri prompts for it separately
        // using the parameter's title ("Cliente") since it has no default.
        AppShortcut(
            intent: RegistrarPagoQuincenaIntent(),
            phrases: [
                "Registra un pago de quincena en \(.applicationName)",
                "Registra un pago en \(.applicationName)",
            ],
            shortTitle: "Registrar pago de quincena",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: MarcarTrabajoPagadoIntent(),
            phrases: [
                "Marca un trabajo como pagado en \(.applicationName)",
                "Marca un pago en \(.applicationName)",
            ],
            shortTitle: "Marcar trabajo pagado",
            systemImageName: "dollarsign.circle"
        )
        AppShortcut(
            intent: RegistrarGastoIntent(),
            phrases: [
                "Registra un gasto en \(.applicationName)",
                "Agrega un gasto en \(.applicationName)",
            ],
            shortTitle: "Registrar gasto",
            systemImageName: "creditcard"
        )
        AppShortcut(
            intent: ConsultarSaldoIntent(),
            phrases: [
                "Cuánto me deben en \(.applicationName)",
                "Consulta mi saldo pendiente en \(.applicationName)",
            ],
            shortTitle: "Consultar saldo pendiente",
            systemImageName: "chart.bar"
        )
        AppShortcut(
            intent: ConsultarAlertasIntent(),
            phrases: [
                "Qué alertas tengo en \(.applicationName)",
                "Resume mis alertas en \(.applicationName)",
            ],
            shortTitle: "Consultar alertas",
            systemImageName: "bell"
        )
    }
}
