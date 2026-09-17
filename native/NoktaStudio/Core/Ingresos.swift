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

    /// Pending-collection amount + job count for the *current* selected month only.
    static func pendienteDelMes(_ periodoMes: String, trabajos: [NoktaTrabajo]) -> (monto: Double, count: Int) {
        var monto = 0.0
        var count = 0
        for t in trabajos {
            if t.grupoResuelto == "B" {
                let montoQ = (t.pagoMensual ?? 0) / 2
                var pendienteEsteTrabajo = false
                for q in [1, 2] {
                    let stored = (t.quincenas ?? []).first { $0.periodo == periodoMes && $0.q == q }
                    if let stored {
                        if stored.estado != "pagado" && stored.estado != "oculta" {
                            monto += stored.monto ?? montoQ
                            pendienteEsteTrabajo = true
                        }
                    } else {
                        monto += montoQ
                        pendienteEsteTrabajo = true
                    }
                }
                if pendienteEsteTrabajo { count += 1 }
            } else if let sesiones = t.sesiones, !sesiones.isEmpty {
                var pendienteEsteTrabajo = false
                for s in sesiones where s.estado != "pagado" && FechaUtil.periodoDeFecha(s.fecha) == periodoMes {
                    monto += s.monto ?? 0
                    pendienteEsteTrabajo = true
                }
                if pendienteEsteTrabajo { count += 1 }
            } else if FechaUtil.periodoDeFecha(t.fecha) == periodoMes && t.estado == "pendiente" {
                monto += t.saldo ?? 0
                count += 1
            }
        }
        return (monto, count)
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
