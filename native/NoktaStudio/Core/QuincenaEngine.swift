import Foundation

/// Port of admin.html's `_generarPeriodos` — builds the list of "YYYY-MM"
/// periods to display for a grupo B (paquete mensual) contract, from
/// `fechaInicio` through ~2 months ahead. If the client's relationship
/// isn't "activo" (live, from ClienteEstado — see estadoRelacion), the
/// range freezes at the month after the last period actually saved, so a
/// paused/cancelled contract stops sprouting new pending months.
enum QuincenaEngine {
    static func generarPeriodos(fechaInicio: String?, estadoRelacion: String, quincenasGuardadas: [NoktaQuincena]) -> [String] {
        let hoy = Date()
        let cal = Calendar(identifier: .gregorian)
        let hoyAnio = cal.component(.year, from: hoy)
        let hoyMes = cal.component(.month, from: hoy)

        let inicio = fechaInicio.flatMap(FechaUtil.anioMes) ?? (anio: hoyAnio, mes: hoyMes)
        var cur = (anio: inicio.anio, mes: inicio.mes)
        var fin = addMonths((anio: hoyAnio, mes: hoyMes), 2)

        if estadoRelacion != "activo" {
            let guardados = quincenasGuardadas.map(\.periodo).sorted()
            if let ultimo = guardados.last, let am = FechaUtil.anioMes(ultimo) {
                fin = addMonths((anio: am.anio, mes: am.mes), 1)
            } else {
                fin = addMonths(inicio, 1)
            }
        }

        var periodos: [String] = []
        while compare(cur, fin) < 0 {
            periodos.append(FechaUtil.periodo(anio: cur.anio, mes: cur.mes))
            cur = addMonths(cur, 1)
        }
        return periodos
    }

    /// "1 al 15" / "15 al 30" labels, matching admin.html.
    static func labelDeQ(_ q: Int) -> String { q == 1 ? "1 al 15" : "15 al 30" }

    static func addMonths(_ ym: (anio: Int, mes: Int), _ n: Int) -> (anio: Int, mes: Int) {
        let totalMonthsFromEpoch = ym.anio * 12 + (ym.mes - 1) + n
        let anio = totalMonthsFromEpoch >= 0 ? totalMonthsFromEpoch / 12 : (totalMonthsFromEpoch - 11) / 12
        let mes = totalMonthsFromEpoch - anio * 12 + 1
        return (anio, mes)
    }

    private static func compare(_ a: (anio: Int, mes: Int), _ b: (anio: Int, mes: Int)) -> Int {
        if a.anio != b.anio { return a.anio < b.anio ? -1 : 1 }
        if a.mes != b.mes { return a.mes < b.mes ? -1 : 1 }
        return 0
    }
}
