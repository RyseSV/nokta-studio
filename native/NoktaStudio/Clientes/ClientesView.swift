import SwiftUI

let ESTADO_CLIENTE_LABEL: [String: String] = ["activo": "Activo", "pausado": "Pausado", "cancelado": "Cancelado"]
let ESTADO_CLIENTE_COLOR: (String) -> Color = { estado in
    switch estado {
    case "activo": return NoktaPalette.green
    case "pausado": return NoktaPalette.yellow
    default: return NoktaPalette.red
    }
}

struct ClienteRow: Identifiable {
    let nombre: String
    let trabajos: [NoktaTrabajo]
    let total: Double
    let pendiente: Double
    let ultimoFecha: String?
    let tipo: String
    let estado: String
    var id: String { nombre }
}

@Observable
final class ClientesViewModel {
    var trabajos: [NoktaTrabajo] = []
    var clientes: [NoktaCliente] = []
    var clienteEstados: [NoktaClienteEstado] = []
    var filtroEstado = "todos"
    var isLoading = true

    func load() async {
        isLoading = true
        defer { isLoading = false }
        async let t: [NoktaTrabajo]? = try? NoktaAPI.get("/api/trabajos")
        async let c: [NoktaCliente]? = try? NoktaAPI.get("/api/clientes")
        async let e: [NoktaClienteEstado]? = try? NoktaAPI.get("/api/clientes-estados")
        let (tt, cc, ee) = await (t, c, e)
        trabajos = tt ?? []
        clientes = cc ?? []
        clienteEstados = ee ?? []
    }

    func estadoDe(_ nombre: String) -> String {
        clienteEstados.first { $0.nombre == nombre }?.estado ?? "activo"
    }

    func whatsappDe(_ nombre: String) -> String? {
        clientes.first { $0.nombre == nombre }?.whatsapp.flatMap { $0.isEmpty ? nil : $0 }
    }

    var rows: [ClienteRow] {
        var nombres: [String] = []
        var seen = Set<String>()
        for n in (clientes.map(\.nombre) + trabajos.map(\.cliente)) where !seen.contains(n) {
            seen.insert(n); nombres.append(n)
        }
        var rows = nombres.map { nombre -> ClienteRow in
            let ts = trabajos.filter { $0.cliente == nombre }
            let total = totalGeneradoCliente(ts)
            let pendiente = ts.reduce(0.0) { s, t in
                if t.grupoResuelto == "B" {
                    return s + (t.quincenas ?? []).filter { $0.estado == "pendiente" || $0.estado == "retrasado" }.reduce(0) { $0 + ($1.monto ?? 0) }
                }
                return s + (t.saldo ?? 0)
            }
            let ultimo = ts.max { ($0.fecha ?? "") < ($1.fecha ?? "") }
            return ClienteRow(nombre: nombre, trabajos: ts, total: total, pendiente: pendiente, ultimoFecha: ultimo?.fecha ?? ultimo?.fechaInicio, tipo: ts.count > 1 ? "Frecuente" : "Nuevo", estado: estadoDe(nombre))
        }
        rows.sort { $0.total > $1.total }
        if filtroEstado != "todos" { rows = rows.filter { $0.estado == filtroEstado } }
        return rows
    }

    func cambiarEstado(_ nombre: String, _ estado: String) async {
        struct Body: Encodable { let estado: String }
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp? = try? await NoktaAPI.put("/api/clientes-estados/\(nombre.urlPathComponentEncoded)", body: Body(estado: estado))
        if let idx = clienteEstados.firstIndex(where: { $0.nombre == nombre }) {
            clienteEstados[idx].estado = estado
        } else {
            clienteEstados.append(NoktaClienteEstado(nombre: nombre, estado: estado, notas: nil))
        }
        // Sincroniza el contrato de sus paquetes mensuales (grupo B) — pausar/cancelar
        // al cliente detiene la generación de quincenas nuevas (ver QuincenaEngine).
        for t in trabajos where t.cliente == nombre && t.grupoResuelto == "B" {
            struct TBody: Encodable { let estadoContrato: String }
            struct TResp: Decodable { let ok: Bool? }
            let _: TResp? = try? await NoktaAPI.put("/api/trabajos/\(t.id)", body: TBody(estadoContrato: estado))
        }
    }
}

/// Suma pagada/lifetime por trabajo — igual a `totalGenerado` en admin.html.
func totalGeneradoCliente(_ ts: [NoktaTrabajo]) -> Double {
    ts.reduce(0.0) { s, t in
        if t.grupoResuelto == "B" {
            return s + (t.quincenas ?? []).filter { $0.estado == "pagado" }.reduce(0) { $0 + ($1.monto ?? 0) }
        }
        return s + (t.monto ?? 0)
    }
}

struct ClientesContainerView: View {
    @State private var selectedNombre: String?

    var body: some View {
        if let nombre = selectedNombre {
            ClienteDetailView(nombre: nombre, onBack: { selectedNombre = nil })
        } else {
            ClientesView(onSelect: { selectedNombre = $0 })
        }
    }
}

private let clienteTabs = [("todos", "Todos"), ("activo", "Activos"), ("pausado", "Pausados"), ("cancelado", "Cancelados")]

struct ClientesView: View {
    @State private var vm = ClientesViewModel()
    var onSelect: (String) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Clientes").font(NoktaFont.pageTitle).foregroundStyle(NoktaPalette.cream)

                HStack(spacing: 8) {
                    ForEach(clienteTabs, id: \.0) { key, label in
                        Button(label) { vm.filtroEstado = key }
                            .buttonStyle(.glass)
                            .tint(vm.filtroEstado == key ? NoktaPalette.ember : nil)
                    }
                }

                if vm.rows.isEmpty {
                    Text(vm.isLoading ? "Cargando…" : "No hay clientes registrados")
                        .font(.system(size: 13)).foregroundStyle(NoktaPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .center).padding(40)
                } else {
                    VStack(spacing: 0) {
                        headerRow
                        ForEach(vm.rows) { row in
                            rowView(row)
                            if row.id != vm.rows.last?.id { Divider().overlay(NoktaPalette.border) }
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
            Text("NOMBRE").frame(maxWidth: .infinity, alignment: .leading)
            Text("TIPO").frame(maxWidth: .infinity, alignment: .leading)
            Text("ESTADO").frame(maxWidth: .infinity, alignment: .leading)
            Text("TRABAJOS").frame(maxWidth: .infinity, alignment: .leading)
            Text("ÚLTIMO").frame(maxWidth: .infinity, alignment: .leading)
            Text("TOTAL").frame(maxWidth: .infinity, alignment: .leading)
            Text("POR COBRAR").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(NoktaFont.tableHead).foregroundStyle(NoktaPalette.muted)
        .padding(.horizontal, 20).padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(NoktaPalette.border).frame(height: 1) }
    }

    private func rowView(_ row: ClienteRow) -> some View {
        // Nota: el picker de ESTADO es un Menu (control interactivo propio) —
        // no puede vivir DENTRO de un Button que cubra toda la fila, o
        // SwiftUI absorbe el tap y ninguno de los dos responde. Cada celda
        // navegable es su propio Button hermano del Menu, no su ancestro.
        func navCell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
            Button { onSelect(row.nombre) } label: {
                content().frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        return HStack {
            navCell { Text(row.nombre) }
            navCell {
                Text(row.tipo)
                    .font(NoktaFont.pill).foregroundStyle(row.tipo == "Frecuente" ? NoktaPalette.green : Color(hex: 0x6495ED))
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background((row.tipo == "Frecuente" ? NoktaPalette.green : Color(hex: 0x6495ED)).opacity(0.15), in: Capsule())
            }
            Menu {
                ForEach(["activo", "pausado", "cancelado"], id: \.self) { e in
                    Button(ESTADO_CLIENTE_LABEL[e] ?? e) { Task { await vm.cambiarEstado(row.nombre, e) } }
                }
            } label: {
                Text(ESTADO_CLIENTE_LABEL[row.estado] ?? row.estado)
                    .font(NoktaFont.pill).foregroundStyle(ESTADO_CLIENTE_COLOR(row.estado))
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(ESTADO_CLIENTE_COLOR(row.estado).opacity(0.15), in: Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            navCell { Text("\(row.trabajos.count)") }
            navCell { Text(row.ultimoFecha != nil ? FechaUtil.fechaCorta(row.ultimoFecha) : "—") }
            navCell { Text("$" + String(format: "%.2f", row.total)).foregroundStyle(NoktaPalette.green) }
            navCell { Text("$" + String(format: "%.2f", row.pendiente)).foregroundStyle(NoktaPalette.yellow) }
        }
        .font(NoktaFont.tableCell).foregroundStyle(NoktaPalette.cream)
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}
