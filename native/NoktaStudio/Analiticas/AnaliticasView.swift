import SwiftUI
import Charts

/// Port of admin.html's "Analíticas" section (loadAnaliticas). Deliberately
/// mirrors its naive month-by-month sum of `monto` (not the smarter
/// paid-only ingresosDelPeriodo Dashboard uses) — same parity-over-cleverness
/// reasoning as IngresosCalculator: these numbers must match the web exactly.
private struct MesDatum: Identifiable { let id = UUID(); let mes: String; let monto: Double }
private struct ServicioDatum: Identifiable { let id = UUID(); let servicio: String; let monto: Double }
private struct ClienteTipoDatum: Identifiable { let id = UUID(); let tipo: String; let count: Int; let color: Color }

@Observable
final class AnaliticasViewModel {
    var trabajos: [NoktaTrabajo] = []
    var isLoading = true

    func load() async {
        isLoading = true
        defer { isLoading = false }
        if let t: [NoktaTrabajo] = try? await NoktaAPI.get("/api/trabajos") { trabajos = t }
    }

    private static let mesesAbrev = ["Ene", "Feb", "Mar", "Abr", "May", "Jun", "Jul", "Ago", "Sep", "Oct", "Nov", "Dic"]

    fileprivate var porMes: [MesDatum] {
        let anio = Calendar.current.component(.year, from: Date())
        return (0..<12).map { i in
            let monto = trabajos.filter { t in
                guard let am = FechaUtil.anioMes(t.fecha) else { return false }
                return am.mes - 1 == i && am.anio == anio
            }.reduce(0.0) { $0 + ($1.monto ?? 0) }
            return MesDatum(mes: Self.mesesAbrev[i], monto: monto)
        }
    }

    var promedioPorTrabajo: Double {
        trabajos.isEmpty ? 0 : trabajos.reduce(0) { $0 + ($1.monto ?? 0) } / Double(trabajos.count)
    }
    var trabajosCerrados: Int { trabajos.filter { $0.estado == "pagado" }.count }
    var tasaDeCobro: Int { trabajos.isEmpty ? 0 : Int(Double(trabajosCerrados) / Double(trabajos.count) * 100) }
    var servicioMasRentable: String {
        var totals: [String: Double] = [:]
        for t in trabajos { totals[t.servicio, default: 0] += t.monto ?? 0 }
        return totals.max(by: { $0.value < $1.value })?.key ?? "—"
    }

    fileprivate var porServicio: [ServicioDatum] {
        IngresosCalculator.porTipoDeServicio(trabajos).map { ServicioDatum(servicio: $0.servicio, monto: $0.monto) }
    }

    fileprivate var nuevosVsRecurrentes: [ClienteTipoDatum] {
        var counts: [String: Int] = [:]
        for t in trabajos { counts[t.cliente, default: 0] += 1 }
        let nuevos = counts.values.filter { $0 == 1 }.count
        let recurrentes = counts.count - nuevos
        return [
            ClienteTipoDatum(tipo: "Nuevos", count: nuevos, color: NoktaPalette.ember),
            ClienteTipoDatum(tipo: "Recurrentes", count: recurrentes, color: NoktaPalette.green),
        ]
    }
}

struct AnaliticasView: View {
    @State private var vm = AnaliticasViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Analíticas").font(NoktaFont.pageTitle).foregroundStyle(NoktaPalette.cream)

                if vm.isLoading && vm.trabajos.isEmpty {
                    Text("Cargando…").font(.system(size: 13)).foregroundStyle(NoktaPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .center).padding(40)
                } else {
                    chartCard(title: "Ingresos por mes (año actual)") {
                        Chart(vm.porMes) { d in
                            AreaMark(x: .value("Mes", d.mes), y: .value("Monto", d.monto))
                                .foregroundStyle(NoktaPalette.ember.opacity(0.12))
                            LineMark(x: .value("Mes", d.mes), y: .value("Monto", d.monto))
                                .foregroundStyle(NoktaPalette.ember)
                                .interpolationMethod(.catmullRom)
                            PointMark(x: .value("Mes", d.mes), y: .value("Monto", d.monto))
                                .foregroundStyle(NoktaPalette.ember)
                        }
                        .chartXAxis { AxisMarks { AxisValueLabel().foregroundStyle(NoktaPalette.muted) } }
                        .chartYAxis {
                            AxisMarks { v in
                                AxisGridLine().foregroundStyle(NoktaPalette.border)
                                AxisValueLabel { if let d = v.as(Double.self) { Text("$\(Int(d))").foregroundStyle(NoktaPalette.muted) } }
                            }
                        }
                        .frame(height: 220)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                        card(label: "PROMEDIO POR TRABAJO", value: fmt(vm.promedioPorTrabajo))
                        card(label: "TRABAJOS CERRADOS", value: "\(vm.trabajosCerrados)")
                        card(label: "TASA DE COBRO", value: "\(vm.tasaDeCobro)%")
                        card(label: "SERVICIO MÁS RENTABLE", value: vm.servicioMasRentable, valueSize: 14)
                    }

                    GlassEffectContainer(spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        chartCard(title: "Ingresos por tipo de servicio") {
                            Chart(vm.porServicio) { d in
                                BarMark(x: .value("Monto", d.monto), y: .value("Servicio", d.servicio))
                                    .foregroundStyle(NoktaPalette.ember.opacity(0.7))
                                    .cornerRadius(6)
                            }
                            .chartXAxis { AxisMarks { v in
                                AxisGridLine().foregroundStyle(NoktaPalette.border)
                                AxisValueLabel { if let d = v.as(Double.self) { Text("$\(Int(d))").foregroundStyle(NoktaPalette.muted) } }
                            } }
                            .chartYAxis { AxisMarks { AxisValueLabel().foregroundStyle(NoktaPalette.muted) } }
                            .frame(height: 200)
                        }
                        .frame(maxWidth: .infinity)

                        chartCard(title: "Clientes nuevos vs recurrentes") {
                            Chart(vm.nuevosVsRecurrentes) { d in
                                SectorMark(angle: .value("Cantidad", d.count), innerRadius: .ratio(0.55), angularInset: 1.5)
                                    .foregroundStyle(d.color)
                            }
                            .frame(height: 160)
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(vm.nuevosVsRecurrentes) { d in
                                    HStack(spacing: 6) {
                                        Circle().fill(d.color).frame(width: 8, height: 8)
                                        Text("\(d.tipo) (\(d.count))").font(.system(size: 11)).foregroundStyle(NoktaPalette.cream)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    }
                }
            }
            .padding(32)
        }
        .background(NoktaPalette.bg)
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    private func chartCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(NoktaFont.chartTitle).foregroundStyle(NoktaPalette.cream)
            content()
        }
        .padding(20)
        .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
    }

    private func card(label: String, value: String, valueSize: CGFloat = 24) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted).tracking(0.5)
            Text(value).font(.system(size: valueSize, weight: .semibold)).foregroundStyle(NoktaPalette.cream)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
    }

    private func fmt(_ v: Double) -> String { "$" + String(format: "%.2f", v) }
}
