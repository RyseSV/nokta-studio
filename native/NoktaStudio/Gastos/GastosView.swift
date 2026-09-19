import SwiftUI

private let gastoCategorias = ["Equipo", "Transporte", "Software", "Marketing", "Otros"]

@Observable
final class GastosViewModel {
    var gastos: [NoktaGasto] = []
    var trabajos: [NoktaTrabajo] = []
    var filtroMes = ""
    var filtroCategoria = ""
    var isLoading = true

    func load() async {
        isLoading = true
        defer { isLoading = false }
        async let g: [NoktaGasto]? = try? NoktaAPI.get("/api/gastos")
        async let t: [NoktaTrabajo]? = try? NoktaAPI.get("/api/trabajos")
        let (gg, tt) = await (g, t)
        gastos = gg ?? []
        trabajos = tt ?? []
    }

    var mesesDisponibles: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for g in gastos {
            if let p = FechaUtil.periodoDeFecha(g.fecha), !seen.contains(p) {
                seen.insert(p); result.append(p)
            }
        }
        return result.sorted()
    }

    var filtrados: [NoktaGasto] {
        gastos.filter { g in
            (filtroMes.isEmpty || FechaUtil.periodoDeFecha(g.fecha) == filtroMes) &&
            (filtroCategoria.isEmpty || g.categoria == filtroCategoria)
        }
    }

    var totalMesActual: Double {
        let periodoActual = FechaUtil.periodo(anio: Calendar.current.component(.year, from: Date()), mes: Calendar.current.component(.month, from: Date()))
        return gastos.filter { FechaUtil.periodoDeFecha($0.fecha) == periodoActual }.reduce(0) { $0 + ($1.monto ?? 0) }
    }

    var margenMesActual: String {
        let periodoActual = FechaUtil.periodo(anio: Calendar.current.component(.year, from: Date()), mes: Calendar.current.component(.month, from: Date()))
        let ingresos = trabajos.filter { FechaUtil.periodoDeFecha($0.fecha) == periodoActual }.reduce(0.0) { $0 + ($1.monto ?? 0) }
        guard ingresos > 0 else { return "—" }
        return String(format: "%.0f%% margen", (1 - totalMesActual / ingresos) * 100)
    }

    func guardar(concepto: String, categoria: String, monto: Double, fecha: String) async {
        struct Body: Encodable { let concepto: String; let categoria: String; let monto: Double; let fecha: String }
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp? = try? await NoktaAPI.post("/api/gastos", body: Body(concepto: concepto, categoria: categoria, monto: monto, fecha: fecha))
        await load()
    }

    func eliminar(_ id: String) async {
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp? = try? await NoktaAPI.delete("/api/gastos/\(id)")
        await load()
    }
}

struct GastosView: View {
    @State private var vm = GastosViewModel()
    @State private var concepto = ""
    @State private var categoria = gastoCategorias[0]
    @State private var monto = ""
    @State private var fecha = Date()
    @State private var errorMessage: String?
    @State private var eliminarConfirm: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Gastos").font(NoktaFont.pageTitle).foregroundStyle(NoktaPalette.cream)

                HStack(alignment: .top, spacing: 20) {
                    formCard
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 16) {
                            statCard("TOTAL GASTOS (MES)", "$" + String(format: "%.2f", vm.totalMesActual), NoktaPalette.red)
                            statCard("INGRESOS VS GASTOS", vm.margenMesActual, NoktaPalette.cream)
                        }

                        HStack(spacing: 10) {
                            Picker("", selection: $vm.filtroMes) {
                                Text("Todos los meses").tag("")
                                ForEach(vm.mesesDisponibles, id: \.self) { p in Text(mesLabel(p)).tag(p) }
                            }.pickerStyle(.menu).tint(NoktaPalette.cream)
                            Picker("", selection: $vm.filtroCategoria) {
                                Text("Todas las categorías").tag("")
                                ForEach(gastoCategorias, id: \.self) { Text($0).tag($0) }
                            }.pickerStyle(.menu).tint(NoktaPalette.cream)
                        }

                        tabla
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(32)
        }
        .background(NoktaPalette.bg)
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .alert("¿Eliminar este gasto?", isPresented: Binding(get: { eliminarConfirm != nil }, set: { if !$0 { eliminarConfirm = nil } })) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar", role: .destructive) {
                if let id = eliminarConfirm { Task { await vm.eliminar(id) } }
            }
        }
    }

    private func mesLabel(_ periodo: String) -> String {
        guard let am = FechaUtil.anioMes(periodo) else { return periodo }
        return "\(FechaUtil.mesesCompletos[am.mes - 1]) \(am.anio)"
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Registrar gasto").font(.system(size: 14, weight: .medium)).foregroundStyle(NoktaPalette.cream)

            field("Concepto") { TextField("Descripción del gasto", text: $concepto).textFieldStyle(.plain) }

            VStack(alignment: .leading, spacing: 6) {
                Text("CATEGORÍA").font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted)
                Picker("", selection: $categoria) {
                    ForEach(gastoCategorias, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().pickerStyle(.menu)
            }

            field("Monto ($)") { TextField("0.00", text: $monto).textFieldStyle(.plain) }

            DatePicker("Fecha", selection: $fecha, displayedComponents: .date)

            if let errorMessage {
                Text(errorMessage).font(.system(size: 12)).foregroundStyle(NoktaPalette.red)
            }

            Button("Registrar") { Task { await guardar() } }
                .buttonStyle(.glassProminent).tint(NoktaPalette.ember)
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(width: 320, alignment: .leading)
        .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted)
            content()
                .padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(NoktaPalette.cream)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: NoktaRadius.button))
        }
    }

    private func statCard(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted)
            Text(value).font(.system(size: 22, weight: .bold)).foregroundStyle(color)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
    }

    private var tabla: some View {
        VStack(spacing: 0) {
            HStack {
                Text("CONCEPTO").frame(maxWidth: .infinity, alignment: .leading)
                Text("CATEGORÍA").frame(maxWidth: .infinity, alignment: .leading)
                Text("FECHA").frame(maxWidth: .infinity, alignment: .leading)
                Text("MONTO").frame(maxWidth: .infinity, alignment: .leading)
                Text("").frame(width: 30)
            }
            .font(NoktaFont.tableHead).foregroundStyle(NoktaPalette.muted)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(NoktaPalette.border).frame(height: 1) }

            if vm.filtrados.isEmpty {
                Text(vm.isLoading ? "Cargando…" : "No hay gastos")
                    .font(.system(size: 13)).foregroundStyle(NoktaPalette.muted)
                    .frame(maxWidth: .infinity, alignment: .center).padding(40)
            } else {
                ForEach(vm.filtrados, id: \.id) { g in
                    HStack {
                        Text(g.concepto).frame(maxWidth: .infinity, alignment: .leading)
                        Text(g.categoria).frame(maxWidth: .infinity, alignment: .leading)
                        Text(FechaUtil.fechaCorta(g.fecha)).frame(maxWidth: .infinity, alignment: .leading)
                        Text("$" + String(format: "%.2f", g.monto ?? 0)).foregroundStyle(NoktaPalette.red).frame(maxWidth: .infinity, alignment: .leading)
                        Button { eliminarConfirm = g.id } label: { Image(systemName: "xmark") }
                            .buttonStyle(.glass).frame(width: 30)
                    }
                    .font(NoktaFont.tableCell).foregroundStyle(NoktaPalette.cream)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    if g.id != vm.filtrados.last?.id { Divider().overlay(NoktaPalette.border) }
                }
            }
        }
        .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
    }

    private func guardar() async {
        errorMessage = nil
        guard !concepto.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Escribe el concepto"; return }
        guard let m = Double(monto), m > 0 else { errorMessage = "Completa el monto"; return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        await vm.guardar(concepto: concepto, categoria: categoria, monto: m, fecha: f.string(from: fecha))
        concepto = ""; monto = ""; fecha = Date()
    }
}
