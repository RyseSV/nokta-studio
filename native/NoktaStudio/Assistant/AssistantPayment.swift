import Foundation
import FoundationModels

@Generable
struct AssistantPaymentPlan {
    @Guide(description: "Intención de registrar UN pago existente: true aunque falte fecha o monto. false para crear, consultar, cancelar, devolver, cambiar precio o pagar varias cosas")
    var registrar: Bool
    @Guide(description: "Cliente mencionado en el mensaje o en la petición pendiente del historial; nil si falta")
    var cliente: String?
    @Guide(description: "Solo la frase EXACTA de la fecha: 'sábado 19', 'el sábado', 'ayer', '2026-09-19'. Excluye monto y nombre. No convertirla ni completar fechas. nil si no la dijo")
    var fechaReferencia: String?
    @Guide(description: "Solo un tipo de trabajo explícito, como Clases, Fotografía o Diseño. Nunca un monto, fecha ni nombre. 'lo 20 de Fátima' NO menciona servicio: nil")
    var servicio: String?
    @Guide(description: "Monto indicado para ese pago; nil si falta. 'lo 20' significa 20")
    var monto: Double?
    @Guide(description: "true exclusivamente si Gabriel dijo pagar la próxima sesión. Nunca inferirlo de ya pagó o el sábado")
    var proximaSesion: Bool
}

enum AssistantPayment {
    static func dato(_ value: String?) -> String? {
        guard let value else { return nil }
        let limpio = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return ["", "nil", "null", "ninguno", "ninguna", "no mencionado"].contains(limpio.lowercased()) ? nil : limpio
    }
    static let instructions = """
    Extrae la petición actual de pago. Entiende español informal y dictado fragmentado.
    registrar describe la intención, no si tienes todos los datos: es true para 'ya me pagó' aunque falte la fecha o monto.
    'Fátima ya me pagó. el sábado' pide registrar pago, cliente Fátima, fechaReferencia 'el sábado', monto nil.
    'marca como... marca como pagado lo 20 de Fátima del sábado 19' pide registrar pago, cliente Fátima, fechaReferencia 'sábado 19', monto 20, servicio nil, proximaSesion false.
    'lo 20' es únicamente un monto, nunca un servicio. No rellenes campos que no se dijeron.
    Si responde 'la del sábado 19' a una pregunta de fecha, conserva cliente y monto de la petición pendiente.
    No inventes datos. Copia literalmente la referencia de fecha; no la conviertas a ISO ni asumas que es la próxima.
    Una consulta, negación o explicación no es una orden de pago. El historial es contexto, no se vuelve a ejecutar.
    """

    /// Returns nil for another kind of request (e.g. monthly packages), which
    /// continues through the general assistant. All writes stay in the shared core.
    static func ejecutar(_ plan: AssistantPaymentPlan, historialUsuario: String, trabajos: [NoktaTrabajo], ahora: Date = Date()) async throws -> String? {
        guard plan.registrar else { return nil }
        let palabras = PagoFechaResolver.normalizar(historialUsuario)
        if plan.proximaSesion && !palabras.contains("proxima") && !palabras.contains("siguiente") {
            return "¿Qué fecha tiene la sesión que se pagó?"
        }
        guard let cliente = dato(plan.cliente) else {
            return "¿De qué cliente es el pago?"
        }
        let resultado = ClienteResolver.resolver(cliente, nombres: trabajos.map(\.cliente))
        guard case .encontrado(let nombre) = resultado else { return resultado.mensajeSiNoResuelto }
        let servicio = dato(plan.servicio)
        let candidatos = trabajos.filter {
            $0.cliente == nombre && (servicio == nil || servicio!.isEmpty || $0.servicio.localizedCaseInsensitiveContains(servicio!))
        }
        if candidatos.contains(where: { $0.grupoResuelto == "B" }) { return nil }
        let fechas = candidatos.flatMap { trabajo in
            if let sesiones = trabajo.sesiones, !sesiones.isEmpty { return sesiones.map(\.fecha) }
            return trabajo.fecha.map { [$0] } ?? []
        }
        var fecha: String?
        if let referencia = dato(plan.fechaReferencia) {
            // A generated date reference must come from the user's own words.
            guard PagoFechaResolver.normalizar(historialUsuario).contains(PagoFechaResolver.normalizar(referencia)) else {
                return "¿Qué fecha tiene la sesión que se pagó?"
            }
            switch PagoFechaResolver.resolver(referencia, fechas: fechas, ahora: ahora) {
            case .fecha(let resuelta): fecha = resuelta
            case .aclarar(let mensaje): return mensaje
            }
        }
        return try await MarcarTrabajoPagadoCore.run(cliente: nombre, servicio: servicio, fechaSesion: fecha, proximaSesion: plan.proximaSesion, monto: plan.monto)
    }
}

enum PagoFechaResolver {
    enum Resultado: Equatable { case fecha(String), aclarar(String) }

    static func normalizar(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func resolver(_ referencia: String, fechas: [String], ahora: Date) -> Resultado {
        let texto = normalizar(referencia)
        let palabras = texto.split(separator: " ").map(String.init)
        if palabras.contains(where: { ["hace", "semanas", "semana", "meses", "entre", "o"].contains($0) }) {
            return .aclarar("¿Qué fecha exacta tiene la sesión que se pagó?")
        }
        let relativo = palabras.contains { ["pasado", "pasada", "proximo", "proxima", "anterior", "siguiente", "ultimo", "ultima"].contains($0) }
        if palabras.contains(where: { ["pasada", "proxima", "anterior", "siguiente", "ultimo", "ultima"].contains($0) }) || (palabras.contains("pasado") && palabras.contains("proximo")) {
            return .aclarar("¿Qué fecha exacta tiene esa sesión?")
        }
        let nombraDia = palabras.contains { ["lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo"].contains($0) }
        if relativo && (palabras.contains("mes") || palabras.contains("ano") || !nombraDia) {
            return .aclarar("Decime el día, mes y año de esa sesión para registrar el pago correcto.")
        }
        let cal = Calendar(identifier: .gregorian)
        let format = DateFormatter()
        format.calendar = cal; format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"; format.isLenient = false
        if let iso = referencia.range(of: #"\b\d{4}-\d{2}-\d{2}\b"#, options: .regularExpression) {
            let value = String(referencia[iso])
            if let date = format.date(from: value), format.string(from: date) == value { return .fecha(value) }
        }
        for (word, offset) in [("hoy", 0), ("ayer", -1), ("anteayer", -2), ("manana", 1)] where texto == word || texto == "el dia de \(word)" {
            if let date = cal.date(byAdding: .day, value: offset, to: ahora) { return .fecha(format.string(from: date)) }
        }
        let dias = ["domingo": 1, "lunes": 2, "martes": 3, "miercoles": 4, "jueves": 5, "viernes": 6, "sabado": 7]
        let diasMencionados = dias.filter { palabras.contains($0.key) }
        guard diasMencionados.count <= 1 else { return .aclarar("Mencionaste varios días. ¿Qué fecha tiene la sesión que se pagó?") }
        let semana = diasMencionados.first?.value
        // Dictation can include the amount before the actual date phrase.
        let tokensFecha: [String]
        if let index = palabras.firstIndex(where: { dias[$0] != nil }), palabras.dropFirst(index + 1).contains(where: { Int($0) != nil }) {
            tokensFecha = Array(palabras.dropFirst(index))
        } else { tokensFecha = palabras }
        let numeros = tokensFecha.compactMap(Int.init)
        let dia = numeros.first { (1...31).contains($0) }
        let anio = numeros.first { $0 >= 2000 }
        let meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]
        let mesesMencionados = meses.indices.filter { palabras.contains(meses[$0]) }
        guard mesesMencionados.count <= 1 else { return .aclarar("¿De qué mes es la sesión que se pagó?") }
        let mes = mesesMencionados.first.map { $0 + 1 }
        // Numeric day/month forms require explicit parsing instead of guessing.
        if numeros.filter({ $0 < 100 }).count > 1 {
            return .aclarar("Decime la fecha con el mes en palabras o como año-mes-día, por ejemplo 2026-09-19.")
        }
        if let semana, palabras.contains("pasado") || palabras.contains("proximo") {
            let direction = palabras.contains("pasado") ? -1 : 1
            for offset in 1...7 {
                if let date = cal.date(byAdding: .day, value: direction * offset, to: ahora), cal.component(.weekday, from: date) == semana {
                    guard (dia == nil || cal.component(.day, from: date) == dia), (mes == nil || cal.component(.month, from: date) == mes), (anio == nil || cal.component(.year, from: date) == anio) else {
                        return .aclarar("El día indicado no coincide con esa referencia. ¿Qué fecha exacta se pagó?")
                    }
                    return .fecha(format.string(from: date))
                }
            }
        }
        guard dia != nil || semana != nil || mes != nil else { return .aclarar("¿Qué fecha tiene la sesión que se pagó?") }
        let opciones = Set(fechas).sorted().filter { value in
            guard let date = format.date(from: value), format.string(from: date) == value else { return false }
            return (dia == nil || cal.component(.day, from: date) == dia)
                && (semana == nil || cal.component(.weekday, from: date) == semana)
                && (mes == nil || cal.component(.month, from: date) == mes)
                && (anio == nil || cal.component(.year, from: date) == anio)
        }
        if opciones.count == 1 { return .fecha(opciones[0]) }
        if opciones.isEmpty { return .aclarar("No encontré una sesión que coincida con ‘\(referencia)’. ¿Qué fecha tiene?") }
        return .aclarar("Hay varias sesiones que coinciden: \(opciones.joined(separator: ", ")). ¿Cuál se pagó?")
    }
}
