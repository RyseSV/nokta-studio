import Foundation

/// Only complete, unambiguous read requests bypass the language model.
/// Client/date-specific requests and mutations still go through its tools.
enum ConsultaCobrosRouting {
    private static func normalizar(_ prompt: String) -> String {
        prompt.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func esConsultaDirecta(_ prompt: String, siguiendoCobros: Bool) -> Bool {
        let consultas: Set<String> = [
            "cuanto me deben", "cuanto me deben este mes", "cuanto me deben en este mes",
            "cuanto tengo pendiente de cobro", "cuanto tengo pendiente de cobro este mes",
            "saldo pendiente", "saldo pendiente este mes", "pendiente de cobro",
            "pendiente de cobro este mes", "quien me debe este mes", "quienes me deben este mes"
        ]
        return consultas.contains(normalizar(prompt)) || (siguiendoCobros && esSeguimiento(prompt))
    }

    static func esSeguimiento(_ prompt: String) -> Bool {
        let seguimientos: Set<String> = [
            "pq", "por que", "porque", "trabajos", "detalle", "desglose", "dame el desglose",
            "explicame", "quienes", "quien", "cuales", "por que ese monto"
        ]
        return seguimientos.contains(normalizar(prompt))
    }
}
