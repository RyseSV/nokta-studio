import SwiftUI

@Observable
final class TrabajosListViewModel {
    var trabajos: [NoktaTrabajo] = []
    var estados: [NoktaClienteEstado] = []
    var filtroGrupo: String = ""
    var filtroEstado: String = ""
    var isLoading = false

    func load() async {
        isLoading = true
        defer { isLoading = false }
        async let t: [NoktaTrabajo]? = try? NoktaAPI.get("/api/trabajos")
        async let e: [NoktaClienteEstado]? = try? NoktaAPI.get("/api/clientes-estados")
        if let t = await t { trabajos = t }
        if let e = await e { estados = e }
    }

    func estadoRelacion(_ cliente: String) -> String {
        estados.first { $0.nombre == cliente }?.estado ?? "activo"
    }

    var filtrados: [NoktaTrabajo] {
        trabajos.filter { t in
            (filtroGrupo.isEmpty || t.grupoResuelto == filtroGrupo) &&
            (filtroEstado.isEmpty || t.estado == filtroEstado)
        }
    }
}

struct TrabajosContainerView: View {
    @State private var selectedId: String?

    /// `abrir`: jump straight into one trabajo's detail (used by the
    /// Dashboard search); Back still returns to the list.
    init(abrir: String? = nil) {
        _selectedId = State(initialValue: abrir)
    }

    var body: some View {
        if let id = selectedId {
            TrabajoDetailView(trabajoId: id, onBack: { selectedId = nil })
        } else {
            TrabajosListView(onSelect: { selectedId = $0 })
        }
    }
}

struct TrabajosListView: View {
    @State private var vm = TrabajosListViewModel()
    var onSelect: (String) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Trabajos").font(NoktaFont.pageTitle).foregroundStyle(NoktaPalette.cream)

                HStack(spacing: 10) {
                    Picker("", selection: $vm.filtroGrupo) {
                        Text("Todos los grupos").tag("")
                        ForEach(["A", "B", "C", "D", "E"], id: \.self) { g in
                            Text(ServicioGrupoMap.nombres[g] ?? g).tag(g)
                        }
                    }.pickerStyle(.menu).tint(NoktaPalette.cream)

                    Picker("", selection: $vm.filtroEstado) {
                        Text("Todos los estados").tag("")
                        Text("Pendiente").tag("pendiente")
                        Text("Pagado").tag("pagado")
                    }.pickerStyle(.menu).tint(NoktaPalette.cream)
                }

                if vm.filtrados.isEmpty {
                    Text(vm.isLoading ? "Cargando…" : "No hay trabajos")
                        .font(.system(size: 13)).foregroundStyle(NoktaPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(40)
                } else {
                    VStack(spacing: 0) {
                        headerRow
                        ForEach(vm.filtrados, id: \.id) { t in
                            Button { onSelect(t.id) } label: { row(t) }
                                .buttonStyle(.plain)
                            if t.id != vm.filtrados.last?.id { Divider().overlay(NoktaPalette.border) }
                        }
                    }
                    .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
                }
            }
            .padding(32)
        }
        .background(NoktaPalette.bg)
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    private var headerRow: some View {
        HStack {
            Text("CLIENTE").frame(maxWidth: .infinity, alignment: .leading)
            Text("SERVICIO").frame(maxWidth: .infinity, alignment: .leading)
            Text("FECHA").frame(maxWidth: .infinity, alignment: .leading)
            Text("MONTO").frame(maxWidth: .infinity, alignment: .leading)
            Text("SALDO").frame(maxWidth: .infinity, alignment: .leading)
            Text("ESTADO").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(NoktaFont.tableHead).foregroundStyle(NoktaPalette.muted)
        .padding(.horizontal, 20).padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(NoktaPalette.border).frame(height: 1) }
    }

    private func row(_ t: NoktaTrabajo) -> some View {
        HStack {
            Text(t.cliente).frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(t.servicio)
                if let gn = t.grupoNombre { Text(gn).font(.system(size: 10)).foregroundStyle(NoktaPalette.muted) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(FechaUtil.fechaCorta(t.fecha)).frame(maxWidth: .infinity, alignment: .leading)
            Text(fmt(t.monto ?? 0)).frame(maxWidth: .infinity, alignment: .leading)
            Text(fmt(t.saldo ?? 0)).foregroundStyle(NoktaPalette.yellow).frame(maxWidth: .infinity, alignment: .leading)
            estadoPill(t).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(NoktaFont.tableCell).foregroundStyle(NoktaPalette.cream)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func estadoPill(_ t: NoktaTrabajo) -> some View {
        let esRecurrente = t.servicio == "Clases"
        if t.grupoResuelto == "B" || esRecurrente {
            let er = vm.estadoRelacion(t.cliente)
            let color = er == "activo" ? NoktaPalette.green : er == "pausado" ? NoktaPalette.yellow : NoktaPalette.red
            return pillView(ESTADO_CLIENTE_LABEL[er] ?? er, color)
        }
        let pagado = t.estado == "pagado"
        return pillView(pagado ? "Pagado" : "Pendiente", pagado ? NoktaPalette.green : NoktaPalette.yellow)
    }

    private func pillView(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(NoktaFont.pill)
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }

    private func fmt(_ v: Double) -> String { "$" + String(format: "%.2f", v) }
}
