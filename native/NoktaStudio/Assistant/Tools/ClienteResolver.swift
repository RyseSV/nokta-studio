import Foundation

/// Resolves user shorthand to an existing, canonical name before a mutation.
/// No edit-distance guesses: an unknown or ambiguous name requires clarification.
enum ClienteResolver {
    enum Resultado: Equatable {
        case encontrado(String)
        case ambiguo([String])
        case noEncontrado

        var mensajeSiNoResuelto: String? {
            switch self {
            case .encontrado: return nil
            case .ambiguo(let nombres):
                return "Hay varios clientes que coinciden: \(nombres.joined(separator: ", ")). Indica el nombre completo del cliente. No cambié ningún dato."
            case .noEncontrado:
                return "No encontré un cliente existente con ese nombre. Indica su nombre tal como aparece en Clientes. No cambié ningún dato."
            }
        }
    }

    private static func tokens(_ value: String) -> [String] {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    static func resolver(_ consulta: String, nombres: [String]) -> Resultado {
        let consulta = consulta.trimmingCharacters(in: .whitespacesAndNewlines)
        let partes = tokens(consulta)
        guard !partes.isEmpty else { return .noEncontrado }
        let candidatos = Array(Set(nombres.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })).sorted()
        // Preserve exact spelling when two real clients differ only by case/accent.
        if candidatos.contains(consulta) { return .encontrado(consulta) }

        let normalizados = candidatos.filter { tokens($0) == partes }
        if !normalizados.isEmpty { return resultado(normalizados) }

        // "Tu Boleto" and "TuBoleto" can refer to the same registered name.
        let compactos = candidatos.filter { tokens($0).joined() == partes.joined() }
        if !compactos.isEmpty { return resultado(compactos) }

        // Each supplied token must match the beginning of a distinct name token.
        // This permits "Fati Lo" without treating "Ana" as a match for "Mariana".
        let parciales = candidatos.filter { nombre in
            var disponibles = tokens(nombre)
            for parte in partes.sorted(by: { $0.count > $1.count }) {
                guard let index = disponibles.firstIndex(where: { $0.hasPrefix(parte) }) else { return false }
                disponibles.remove(at: index)
            }
            return true
        }
        return resultado(parciales)
    }

    private static func resultado(_ nombres: [String]) -> Resultado {
        if nombres.count == 1 { return .encontrado(nombres[0]) }
        return nombres.isEmpty ? .noEncontrado : .ambiguo(nombres)
    }
}
