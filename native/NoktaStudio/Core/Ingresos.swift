import Foundation

extension NoktaTrabajo: Identifiable {}

/// Mirrors `mesAnioDeFecha`/period-string helpers used throughout admin.html.
enum FechaUtil {
    /// Parses the "YYYY-MM" prefix of a "YYYY-MM-DD" (or longer ISO) string.
    static func anioMes(_ fecha: String?) -> (anio: Int, mes: Int)? {
        guard let fecha, fecha.count >= 7 else { return nil }
        let parts = fecha.prefix(7).split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return (y, m)
    }

    static func periodo(anio: Int, mes: Int) -> String {
        String(format: "%04d-%02d", anio, mes)
    }

    static func periodoDeFecha(_ fecha: String?) -> String? {
        guard let am = anioMes(fecha) else { return nil }
        return periodo(anio: am.anio, mes: am.mes)
    }

    static let mesesAbrev = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]
    static let mesesCompletos = [
        "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
        "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre",
    ]

    /// Approximates admin.html's `fmtFecha` (`toLocaleDateString('es', {day:'2-digit',month:'short',year:'numeric'})`).
    static func fechaCorta(_ fecha: String?) -> String {
        guard let fecha, fecha.count >= 10, let am = anioMes(fecha) else { return "—" }
        let dia = Int(fecha.dropFirst(8).prefix(2)) ?? 0
        return "\(dia) \(mesesAbrev[am.mes - 1]) \(am.anio)"
    }
}

/// Direct port of admin.html's `ingresosDelPeriodo` / `pendiente` /
/// `pendienteCount` (see `loadDashboard()`). Deliberately reproduces the
/// same asymmetries the web has (e.g. an unpaid grupo A/C/D/E job still
/// counts as "ingreso" for the month it's dated in) — this is not a bug fix,
/// it's a parity port, so native and web always show the same numbers.
///
/// One deliberate exception: `pendienteDelMes`'s sesiones branch shows only
/// the single next unpaid session ("el cobro del siguiente sábado"), not
/// every unpaid session in the month like the web does. Confirmed with the
/// business owner — summing the whole month overstated what's actually
/// owed right now (e.g. showed $40 instead of $20 counting two classes that
/// hadn't even happened yet).
enum IngresosCalculator {

    /// Revenue counted for a given "YYYY-MM" period.
    static func ingresosDelPeriodo(_ periodo: String, trabajos: [NoktaTrabajo]) -> Double {
        var total = 0.0
        for t in trabajos {
            if t.grupoResuelto == "B" {
                total += (t.quincenas ?? [])
                    .filter { $0.periodo == periodo && $0.estado == "pagado" }
                    .reduce(0) { $0 + ($1.monto ?? 0) }
            } else if let sesiones = t.sesiones, !sesiones.isEmpty {
                for s in sesiones where s.estado == "pagado" && FechaUtil.periodoDeFecha(s.fecha) == periodo {
                    total += s.monto ?? 0
                }
            } else if FechaUtil.periodoDeFecha(t.fecha ?? t.fechaInicio) == periodo {
                total += t.monto ?? 0
            }
        }
        return total
    }

    struct CobroPendiente {
        let trabajoID: String
        let cliente: String
        let servicio: String
        let concepto: String
        let monto: Double
    }

    /// One source of truth for the dashboard and assistant. Recurring classes
    /// intentionally contribute only their earliest unpaid session, even outside
    /// the selected month; the breakdown makes that exception explicit.
    static func cobrosPendientes(_ periodoMes: String, trabajos: [NoktaTrabajo], estados: [NoktaClienteEstado] = []) -> [CobroPendiente] {
        var cobros: [CobroPendiente] = []
        for t in trabajos {
            func agregar(_ monto: Double, _ concepto: String) {
                guard monto.isFinite, monto > 0 else { return }
                cobros.append(CobroPendiente(trabajoID: t.id, cliente: t.cliente, servicio: t.servicio, concepto: concepto, monto: monto))
            }
            if t.grupoResuelto == "B" {
                let estado = (estados.first { $0.nombre == t.cliente }?.estado ?? t.estadoContrato ?? "activo").lowercased()
                guard estado == "activo" else { continue }
                if let inicio = FechaUtil.periodoDeFecha(t.fechaInicio), periodoMes < inicio { continue }
                for q in [1, 2] {
                    let stored = (t.quincenas ?? []).first { $0.periodo == periodoMes && $0.q == q }
                    guard stored?.estado != "pagado", stored?.estado != "oculta" else { continue }
                    agregar(stored?.monto ?? (t.pagoMensual ?? 0) / 2, "quincena \(q), \(periodoMes)")
                }
            } else if let sesiones = t.sesiones, !sesiones.isEmpty {
                if let proxima = sesiones.filter({ $0.estado != "pagado" && $0.estado != "oculta" && $0.estado != "cancelado" }).min(by: { $0.fecha < $1.fecha }) {
                    let fuera = FechaUtil.periodoDeFecha(proxima.fecha) == periodoMes ? "" : " (fuera del mes consultado)"
                    agregar(proxima.monto ?? 0, "próxima sesión sin pagar: \(proxima.fecha)\(fuera)")
                }
            } else if FechaUtil.periodoDeFecha(t.fecha) == periodoMes && t.estado == "pendiente" {
                agregar(t.saldo ?? 0, "saldo del trabajo del \(t.fecha ?? periodoMes)")
            }
        }
        return cobros
    }

    static func pendienteDelMes(_ periodoMes: String, trabajos: [NoktaTrabajo], estados: [NoktaClienteEstado] = []) -> (monto: Double, count: Int) {
        let cobros = cobrosPendientes(periodoMes, trabajos: trabajos, estados: estados)
        return (cobros.reduce(0) { $0 + $1.monto }, Set(cobros.map(\.trabajoID)).count)
    }

    /// Dinero que ya entró por un trabajo, en toda su vida: quincenas pagadas
    /// (mensuales), clases pagadas (sesiones) o monto − saldo (trabajos sueltos).
    static func cobrado(_ t: NoktaTrabajo) -> Double {
        if t.grupoResuelto == "B" {
            return (t.quincenas ?? []).filter { $0.estado == "pagado" }.reduce(0) { $0 + ($1.monto ?? 0) }
        }
        if let sesiones = t.sesiones, !sesiones.isEmpty {
            return sesiones.filter { $0.estado == "pagado" }.reduce(0) { $0 + ($1.monto ?? 0) }
        }
        let monto = t.monto ?? 0
        if t.estado == "pagado" { return monto }
        return max(0, monto - (t.saldo ?? monto))
    }

    /// Lo que ese trabajo debe ahora mismo. Mismas reglas que el Dashboard
    /// (quincenas del mes de contratos activos, solo la próxima clase sin
    /// pagar), pero un trabajo suelto cuenta su saldo sin importar el mes.
    /// Clientes pausados o cancelados no deben nada.
    static func porCobrar(_ t: NoktaTrabajo, estados: [NoktaClienteEstado]) -> Double {
        let esContrato = t.grupoResuelto == "B" || t.servicio == "Clases" || !(t.sesiones ?? []).isEmpty
        if esContrato {
            let relacion = (estados.first { $0.nombre == t.cliente }?.estado ?? t.estadoContrato ?? "activo").lowercased()
            guard relacion == "activo" else { return 0 }
            if t.grupoResuelto == "B" || !(t.sesiones ?? []).isEmpty {
                return cobrosPendientes(periodoActual, trabajos: [t], estados: estados).reduce(0) { $0 + $1.monto }
            }
        }
        return t.estado == "pagado" ? 0 : max(0, t.saldo ?? 0)
    }

    static var periodoActual: String {
        let cal = Calendar.current
        return FechaUtil.periodo(anio: cal.component(.year, from: Date()), mes: cal.component(.month, from: Date()))
    }

    static func resumenCobros(_ periodo: String, trabajos: [NoktaTrabajo], estados: [NoktaClienteEstado]) -> String {
        let cobros = cobrosPendientes(periodo, trabajos: trabajos, estados: estados)
        let total = cobros.reduce(0) { $0 + $1.monto }
        let detalle = cobros.map { "- \($0.cliente) · \($0.servicio): $\(String(format: "%.2f", $0.monto)) · \($0.concepto)." }.joined(separator: "\n")
        return "Pendiente de cobro (\(periodo)): $\(String(format: "%.2f", total)).\n"
            + (cobros.isEmpty ? "No hay cobros pendientes según estos criterios." : detalle)
            + "\nCriterio: trabajos del mes, quincenas activas del mes sin pagar ni ocultar y solo la próxima sesión sin pagar de cada trabajo, aunque esté fuera del mes. No incluye contratos pausados/cancelados ni suma los saldos globales de clases."
    }

    /// "Por tipo de servicio" pie — lifetime sum of `monto` grouped by
    /// `servicio`, not month-filtered (matches admin.html's naive grouping).
    static func porTipoDeServicio(_ trabajos: [NoktaTrabajo]) -> [(servicio: String, monto: Double)] {
        var totals: [String: Double] = [:]
        var order: [String] = []
        for t in trabajos {
            if totals[t.servicio] == nil { order.append(t.servicio) }
            totals[t.servicio, default: 0] += t.monto ?? 0
        }
        return order.map { ($0, totals[$0] ?? 0) }
    }
}
