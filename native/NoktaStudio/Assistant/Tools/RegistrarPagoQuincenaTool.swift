import Foundation
import FoundationModels

@Generable
struct RegistrarPagoQuincenaArgs {
    @Guide(description: "Nombre del cliente con paquete mensual (grupo B) que acaba de pagar")
    var cliente: String
}

private struct QPeriodo {
    let periodo: String
    let q: Int
    let due: Date
    let label: String
}

/// Registers a same-day payment for a Grupo B (paquete mensual) client's
/// quincena, then generates the recibo/"factura" for it — one action for
/// the flow the user actually does: "TuBoleto pagó, dame la factura del
/// mes." Deliberately takes NO date/period argument: an earlier version
/// exposed periodo/q to the model and it hallucinated a period (e.g.
/// "2025-08") instead of leaving them unset. All date logic now runs only
/// in Swift against the device clock, using the same due-date rule the
/// server uses for alerts (día 15 para la Q1, último día del mes para la
/// Q2): it walks every quincena from the trabajo's fechaInicio up to today,
/// picks the oldest one that's due and not yet paid, and falls back to the
/// quincena currently in progress if the client is fully caught up.
struct RegistrarPagoQuincenaTool: Tool {
    let name = "registrar_pago_quincena"
    let description = "Registra el pago de una quincena de un cliente con paquete mensual (grupo B) y genera automáticamente el recibo/factura correspondiente, detectando cuál quincena corresponde y si el pago llegó a tiempo o atrasado. Úsalo cuando el usuario diga que un cliente recurrente ya pagó y pida la factura o el recibo. Nunca le pidas ni le pases una fecha o periodo: la herramienta la calcula sola."
    typealias Arguments = RegistrarPagoQuincenaArgs

    let onCreated: @Sendable (DocumentoParaPDF) -> Void

    private func lastDay(of year: Int, _ month: Int, cal: Calendar) -> Int {
        let firstOfNext = DateComponents(year: month == 12 ? year + 1 : year, month: month == 12 ? 1 : month + 1, day: 1)
        guard let firstOfNextDate = cal.date(from: firstOfNext),
              let lastDayDate = cal.date(byAdding: .day, value: -1, to: firstOfNextDate) else { return 28 }
        return cal.component(.day, from: lastDayDate)
    }

    func call(arguments: RegistrarPagoQuincenaArgs) async throws -> String {
        let trabajos: [NoktaTrabajo] = try await NoktaAPI.get("/api/trabajos")
        guard let t = trabajos.first(where: {
            $0.cliente.localizedCaseInsensitiveCompare(arguments.cliente) == .orderedSame && $0.grupoResuelto == "B"
        }) else {
            return "No encontré un paquete mensual activo para '\(arguments.cliente)'."
        }
        guard let fechaInicioStr = t.fechaInicio, fechaInicioStr.count >= 7 else {
            return "'\(t.cliente)' no tiene fecha de inicio configurada para calcular sus quincenas."
        }

        let cal = Calendar.current
        let now = Date()
        let inicioParts = fechaInicioStr.prefix(7).split(separator: "-")
        guard inicioParts.count == 2, let inicioYear = Int(inicioParts[0]), let inicioMonth = Int(inicioParts[1]) else {
            return "No pude leer la fecha de inicio de '\(t.cliente)'."
        }
        let nowComps = cal.dateComponents([.year, .month], from: now)
        guard let nowYear = nowComps.year, let nowMonth = nowComps.month else {
            return "No pude determinar la fecha de hoy."
        }

        let dfLabel = DateFormatter()
        dfLabel.dateFormat = "dd 'de' MMMM"
        dfLabel.locale = Locale(identifier: "es_ES")

        // Walk every quincena from fechaInicio through the current month.
        var periodos: [QPeriodo] = []
        var y = inicioYear, m = inicioMonth
        while y < nowYear || (y == nowYear && m <= nowMonth) {
            let periodo = String(format: "%04d-%02d", y, m)
            for q in [1, 2] {
                let day = q == 1 ? 15 : lastDay(of: y, m, cal: cal)
                if let due = cal.date(from: DateComponents(year: y, month: m, day: day, hour: 23, minute: 59, second: 59)) {
                    let label = q == 1 ? "1 al 15" : "16 al fin de mes"
                    periodos.append(QPeriodo(periodo: periodo, q: q, due: due, label: "\(label) de \(periodo)"))
                }
            }
            if m == 12 { m = 1; y += 1 } else { m += 1 }
        }

        let quincenas = t.quincenas ?? []
        func estado(for p: QPeriodo) -> String {
            quincenas.first(where: { $0.periodo == p.periodo && $0.q == p.q })?.estado ?? "pendiente"
        }

        // Oldest unpaid, already-due quincena first (client catching up on
        // arrears); otherwise the one currently in progress (paying early/on time).
        let candidate = periodos
            .filter { estado(for: $0) != "pagado" && estado(for: $0) != "oculta" && $0.due <= now }
            .min(by: { $0.due < $1.due })
            ?? periodos.last

        guard let picked = candidate else {
            return "No pude determinar qué quincena de '\(t.cliente)' corresponde pagar."
        }

        let atrasado = now > picked.due
        let montoDefault = (t.pagoMensual ?? 0) / 2
        var updatedQuincenas = quincenas
        let monto: Double
        if let idx = updatedQuincenas.firstIndex(where: { $0.periodo == picked.periodo && $0.q == picked.q }) {
            monto = updatedQuincenas[idx].monto ?? montoDefault
            updatedQuincenas[idx].estado = "pagado"
            updatedQuincenas[idx].fechaPago = ISO8601DateFormatter().string(from: now)
        } else {
            monto = montoDefault
            updatedQuincenas.append(NoktaQuincena(periodo: picked.periodo, q: picked.q, monto: monto, estado: "pagado", fechaPago: ISO8601DateFormatter().string(from: now)))
        }

        struct QBody: Encodable { let quincenas: [NoktaQuincena] }
        struct QResp: Decodable { let ok: Bool }
        let _: QResp = try await NoktaAPI.patch("/api/trabajos/\(t.id)/quincenas", body: QBody(quincenas: updatedQuincenas))

        let fechaHoyISO = String(ISO8601DateFormatter().string(from: now).prefix(10))
        let notas = atrasado
            ? "Pago recibido con atraso. Vencía el \(dfLabel.string(from: picked.due))."
            : "Pago recibido a tiempo."

        struct ServicioLinea: Encodable { let descripcion: String; let monto: Double }
        struct DocBody: Encodable {
            let tipo: String, clienteNombre: String, fechaEmision: String
            let servicios: [ServicioLinea], total: Double, notas: String?
        }
        struct DocResp: Decodable { let ok: Bool; let numero: String }
        let servicioDesc = "\(t.servicio) — quincena \(picked.label)"
        let docBody = DocBody(
            tipo: "recibo", clienteNombre: t.cliente, fechaEmision: fechaHoyISO,
            servicios: [ServicioLinea(descripcion: servicioDesc, monto: monto)], total: monto, notas: notas
        )
        let resp: DocResp = try await NoktaAPI.post("/api/documentos", body: docBody)

        let doc = DocumentoParaPDF(
            numero: resp.numero, tipo: "recibo", clienteNombre: t.cliente,
            empresa: nil, telefono: nil, email: nil, fechaEmision: fechaHoyISO,
            servicios: [(servicioDesc, monto)], notas: notas
        )
        onCreated(doc)

        let estadoTxt = atrasado ? "con atraso (vencía el \(dfLabel.string(from: picked.due)))" : "a tiempo"
        return "Quincena \(picked.label) para \(t.cliente) marcada como pagada, \(estadoTxt). Recibo \(resp.numero) por $\(String(format: "%.2f", monto)) generado — te dejo el PDF arriba."
    }
}
