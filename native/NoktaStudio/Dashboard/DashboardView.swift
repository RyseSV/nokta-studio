import SwiftUI
import Charts

private struct BarDatum: Identifiable { let id = UUID(); let label: String; let monto: Double }
private struct PieDatum: Identifiable { let id = UUID(); let servicio: String; let monto: Double; let color: Color }

@Observable
final class DashboardViewModel {
    var trabajos: [NoktaTrabajo] = []
    var gastos: [NoktaGasto] = []
    var estados: [NoktaClienteEstado] = []
    var mesSeleccionado: Int = Calendar.current.component(.month, from: Date()) - 1 // 0-based
    var isLoading = false
    var errorMessage: String?

    private let year = Calendar.current.component(.year, from: Date())

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let t: [NoktaTrabajo] = NoktaAPI.get("/api/trabajos")
            async let g: [NoktaGasto] = NoktaAPI.get("/api/gastos")
            async let e: [NoktaClienteEstado] = NoktaAPI.get("/api/clientes-estados")
            (trabajos, gastos, estados) = try await (t, g, e)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var periodoMes: String { FechaUtil.periodo(anio: year, mes: mesSeleccionado + 1) }

    /// Mirrors admin.html's `periodoPrev` literally, including its January
    /// year-wrap quirk (keeps the *current* year for December when the
    /// selected month is January) — a parity port, not a fix.
    var periodoPrev: String {
        let mesPrev = mesSeleccionado == 0 ? 12 : mesSeleccionado
        return FechaUtil.periodo(anio: year, mes: mesPrev)
    }

    var ingresos: Double { IngresosCalculator.ingresosDelPeriodo(periodoMes, trabajos: trabajos) }
    var ingresosPrev: Double { IngresosCalculator.ingresosDelPeriodo(periodoPrev, trabajos: trabajos) }

    var gastosDelMes: Double {
        gastos.filter { FechaUtil.periodoDeFecha($0.fecha) == periodoMes }.reduce(0) { $0 + ($1.monto ?? 0) }
    }
    var ganancia: Double { ingresos - gastosDelMes }

    var pendiente: (monto: Double, count: Int) {
        IngresosCalculator.pendienteDelMes(periodoMes, trabajos: trabajos, estados: estados)
    }

    var pctVsMesAnterior: Double {
        guard ingresosPrev > 0 else { return 0 }
        return (ingresos - ingresosPrev) / ingresosPrev * 100
    }

    fileprivate var barData: [BarDatum] {
        (0...3).reversed().map { i in
            let m = ((mesSeleccionado - i) % 12 + 12) % 12
            let y = m > mesSeleccionado ? year - 1 : year
            let periodo = FechaUtil.periodo(anio: y, mes: m + 1)
            return BarDatum(label: FechaUtil.mesesAbrev[m].capitalized, monto: IngresosCalculator.ingresosDelPeriodo(periodo, trabajos: trabajos))
        }
    }

    fileprivate var pieData: [PieDatum] {
        let porServicio = IngresosCalculator.porTipoDeServicio(trabajos)
        return porServicio.enumerated().map { idx, entry in
            PieDatum(servicio: entry.servicio, monto: entry.monto, color: NoktaPalette.servicioPie[idx % NoktaPalette.servicioPie.count])
        }
    }

    fileprivate var ultimosTrabajos: [NoktaTrabajo] { Array(trabajos.prefix(8)) }
}

struct DashboardView: View {
    @State private var vm = DashboardViewModel()
    private var anioActual: Int { Calendar.current.component(.year, from: Date()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                cardsGrid
                chartsRow
                ultimosTrabajosTable
            }
            .padding(32)
        }
        .background(NoktaPalette.bg)
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    private var header: some View {
        HStack {
            Text("Dashboard").font(NoktaFont.pageTitle).foregroundStyle(NoktaPalette.cream)
            Spacer()
            Picker("", selection: $vm.mesSeleccionado) {
                ForEach(0..<12, id: \.self) { i in
                    // Plain String, not a Text("...\(year)...") literal — SwiftUI's
                    // LocalizedStringKey interpolation formats interpolated numbers
                    // with locale grouping by default, which turned "2026" into "2,026".
                    Text(FechaUtil.mesesCompletos[i] + " " + String(anioActual)).tag(i)
                }
            }
            .pickerStyle(.menu)
            .tint(NoktaPalette.cream)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: NoktaRadius.button))
        }
    }

    private var cardsGrid: some View {
        GlassEffectContainer(spacing: 16) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
                card(
                    label: "INGRESOS MES PASADO", value: fmt(vm.ingresosPrev),
                    sub: vm.ingresosPrev > 0 ? "Cobrado el mes anterior" : "Sin ingresos el mes anterior"
                )
                card(
                    label: "INGRESOS DEL MES", value: fmt(vm.ingresos),
                    sub: vm.ingresos > 0 ? "\(vm.pctVsMesAnterior >= 0 ? "▲ +" : "▼ ")\(Int(vm.pctVsMesAnterior))% vs mes anterior" : "Pendiente de cobro",
                    subColor: vm.ingresos > 0 ? (vm.pctVsMesAnterior >= 0 ? NoktaPalette.green : NoktaPalette.red) : NoktaPalette.muted
                )
                card(
                    label: "GANANCIA NETA", value: fmt(vm.ganancia),
                    sub: "\(vm.ingresos > 0 ? Int(vm.ganancia / vm.ingresos * 100) : 0)% margen"
                )
                card(
                    label: "PENDIENTE DE COBRO", value: fmt(vm.pendiente.monto),
                    sub: "\(vm.pendiente.count) trabajo\(vm.pendiente.count == 1 ? "" : "s")",
                    subColor: NoktaPalette.yellow, valueColor: NoktaPalette.yellow
                )
            }
        }
    }

    private var chartsRow: some View {
        GlassEffectContainer(spacing: 16) {
        HStack(alignment: .top, spacing: 16) {
            chartCard(title: "Ingresos últimos 4 meses") {
                Chart(vm.barData) { d in
                    BarMark(x: .value("Mes", d.label), y: .value("Monto", d.monto))
                        .foregroundStyle(NoktaPalette.ember.opacity(0.7))
                        .cornerRadius(6)
                }
                .chartXAxis { AxisMarks { AxisValueLabel().foregroundStyle(NoktaPalette.muted) } }
                .chartYAxis {
                    AxisMarks { v in
                        AxisGridLine().foregroundStyle(NoktaPalette.border)
                        AxisValueLabel {
                            if let d = v.as(Double.self) { Text("$\(Int(d))").foregroundStyle(NoktaPalette.muted) }
                        }
                    }
                }
                .frame(height: 220)
            }
            .frame(maxWidth: .infinity)

            chartCard(title: "Por tipo de servicio") {
                Chart(vm.pieData) { d in
                    SectorMark(angle: .value("Monto", d.monto), innerRadius: .ratio(0.55), angularInset: 1.5)
                        .foregroundStyle(d.color)
                }
                .frame(height: 220)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(vm.pieData) { d in
                        HStack(spacing: 6) {
                            Circle().fill(d.color).frame(width: 8, height: 8)
                            Text(d.servicio).font(.system(size: 11)).foregroundStyle(NoktaPalette.cream)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        }
    }

    private var ultimosTrabajosTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Últimos trabajos").font(NoktaFont.chartTitle).foregroundStyle(NoktaPalette.cream)
                .padding(16)
            if vm.ultimosTrabajos.isEmpty {
                Text("No hay trabajos registrados")
                    .font(.system(size: 13)).foregroundStyle(NoktaPalette.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(24)
            } else {
                VStack(spacing: 0) {
                    tableHeaderRow
                    ForEach(vm.ultimosTrabajos) { t in
                        tableRow(t)
                        if t.id != vm.ultimosTrabajos.last?.id {
                            Divider().overlay(NoktaPalette.border)
                        }
                    }
                }
            }
        }
        .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
    }

    private var tableHeaderRow: some View {
        HStack {
            Text("CLIENTE").frame(maxWidth: .infinity, alignment: .leading)
            Text("SERVICIO").frame(maxWidth: .infinity, alignment: .leading)
            Text("FECHA").frame(maxWidth: .infinity, alignment: .leading)
            Text("MONTO").frame(maxWidth: .infinity, alignment: .leading)
            Text("ESTADO").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(NoktaFont.tableHead)
        .foregroundStyle(NoktaPalette.muted)
        .padding(.horizontal, 20).padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(NoktaPalette.border).frame(height: 1) }
    }

    private func tableRow(_ t: NoktaTrabajo) -> some View {
        HStack {
            Text(t.cliente).frame(maxWidth: .infinity, alignment: .leading)
            Text(t.servicio).frame(maxWidth: .infinity, alignment: .leading)
            Text(FechaUtil.fechaCorta(t.fecha)).frame(maxWidth: .infinity, alignment: .leading)
            Text(fmt(t.monto ?? 0)).frame(maxWidth: .infinity, alignment: .leading)
            estadoPill(t.estado).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(NoktaFont.tableCell)
        .foregroundStyle(NoktaPalette.cream)
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private func estadoPill(_ estado: String) -> some View {
        let pagado = estado == "pagado"
        return Text(pagado ? "Pagado" : "Pendiente")
            .font(NoktaFont.pill)
            .foregroundStyle(pagado ? NoktaPalette.green : NoktaPalette.yellow)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background((pagado ? NoktaPalette.green : NoktaPalette.yellow).opacity(0.15), in: Capsule())
    }

    private func chartCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(NoktaFont.chartTitle).foregroundStyle(NoktaPalette.cream)
            content()
        }
        .padding(20)
        .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
    }

    private func card(label: String, value: String, sub: String, subColor: Color = NoktaPalette.muted, valueColor: Color = NoktaPalette.cream) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted).tracking(0.5)
            Text(value).font(NoktaFont.cardValue).foregroundStyle(valueColor)
            Text(sub).font(NoktaFont.cardSub).foregroundStyle(subColor)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
    }

    private func fmt(_ v: Double) -> String { "$" + String(format: "%.2f", v) }
}
