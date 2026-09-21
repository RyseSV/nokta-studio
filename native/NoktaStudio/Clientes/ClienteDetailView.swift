import SwiftUI

@Observable
final class ClienteDetailViewModel {
    let nombre: String
    var trabajos: [NoktaTrabajo] = []
    var cliente: NoktaCliente?
    var estado: String = "activo"
    var notas: String = ""
    var isLoading = true
    var trabajoIdMostrado: String?

    init(nombre: String) { self.nombre = nombre }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        async let t: [NoktaTrabajo]? = try? NoktaAPI.get("/api/trabajos")
        async let c: [NoktaCliente]? = try? NoktaAPI.get("/api/clientes")
        async let e: [NoktaClienteEstado]? = try? NoktaAPI.get("/api/clientes-estados")
        let (tt, cc, ee) = await (t, c, e)
        trabajos = (tt ?? []).filter { $0.cliente == nombre }
        cliente = (cc ?? []).first { $0.nombre == nombre }
        let ce = (ee ?? []).first { $0.nombre == nombre }
        estado = ce?.estado ?? "activo"
        notas = ce?.notas ?? ""
    }

    var total: Double { totalGeneradoCliente(trabajos) }

    var cobrado: Double {
        trabajos.reduce(0.0) { s, t in
            if t.grupoResuelto == "B" {
                return s + (t.quincenas ?? []).filter { $0.estado == "pagado" }.reduce(0) { $0 + ($1.monto ?? 0) }
            }
            return s + (t.estado == "pagado" ? (t.monto ?? 0) : (t.anticipo ?? 0))
        }
    }

    var porCobrar: Double {
        trabajos.reduce(0.0) { s, t in
            if t.grupoResuelto == "B" {
                return s + (t.quincenas ?? []).filter { $0.estado != "pagado" && $0.estado != "oculta" }.reduce(0) { $0 + ($1.monto ?? 0) }
            }
            return s + (t.saldo ?? 0)
        }
    }

    var retrasadas: Int {
        trabajos.reduce(0) { $0 + ($1.quincenas ?? []).filter { $0.estado == "retrasado" }.count }
    }

    func cambiarEstado(_ nuevo: String) async {
        estado = nuevo
        struct Body: Encodable { let estado: String }
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp? = try? await NoktaAPI.put("/api/clientes-estados/\(nombre.urlPathComponentEncoded)", body: Body(estado: nuevo))
        struct TBody: Encodable { let estadoContrato: String }
        struct TResp: Decodable { let ok: Bool? }
        await withTaskGroup(of: Void.self) { group in
            for t in trabajos where t.grupoResuelto == "B" {
                group.addTask { let _: TResp? = try? await NoktaAPI.put("/api/trabajos/\(t.id)", body: TBody(estadoContrato: nuevo)) }
            }
        }
    }

    func guardarNota() async {
        struct Body: Encodable { let estado: String; let notas: String }
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp? = try? await NoktaAPI.put("/api/clientes-estados/\(nombre.urlPathComponentEncoded)", body: Body(estado: estado, notas: notas))
    }
}

struct ClienteDetailView: View {
    let nombre: String
    var onBack: () -> Void = {}
    @State private var vm: ClienteDetailViewModel

    init(nombre: String, onBack: @escaping () -> Void = {}) {
        self.nombre = nombre
        self.onBack = onBack
        _vm = State(initialValue: ClienteDetailViewModel(nombre: nombre))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if vm.isLoading {
                    ProgressView().tint(NoktaPalette.ember)
                } else {
                    HStack(alignment: .top, spacing: 20) {
                        infoCard
                        VStack(alignment: .leading, spacing: 20) {
                            statsRow
                            trabajosCard
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(32)
        }
        .background(NoktaPalette.bg)
        .task { await vm.load() }
        .sheet(item: Binding(get: {
            vm.trabajoIdMostrado.map { ClienteSheetId(id: $0) }
        }, set: { if $0 == nil { vm.trabajoIdMostrado = nil } })) { ctx in
            NavigationStack {
                TrabajoDetailView(trabajoId: ctx.id, onBack: { vm.trabajoIdMostrado = nil })
            }
            .frame(minWidth: 980, minHeight: 560)
        }
    }

    private var header: some View {
        HStack {
            Button("← Volver", action: onBack).buttonStyle(.glass)
            Text(nombre).font(NoktaFont.pageTitle).foregroundStyle(NoktaPalette.cream)
            Spacer()
            if let wa = vm.cliente?.whatsapp, !wa.isEmpty, let url = URL(string: "https://wa.me/\(wa)") {
                Link(destination: url) { Text("💬 WhatsApp") }
                    .buttonStyle(.glassProminent).tint(NoktaPalette.green)
            }
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ESTADO DE LA RELACIÓN").font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted)
                Menu {
                    ForEach(["activo", "pausado", "cancelado"], id: \.self) { e in
                        Button(ESTADO_CLIENTE_LABEL[e] ?? e) { Task { await vm.cambiarEstado(e) } }
                    }
                } label: {
                    Text(ESTADO_CLIENTE_LABEL[vm.estado] ?? vm.estado)
                        .font(NoktaFont.pill).foregroundStyle(ESTADO_CLIENTE_COLOR(vm.estado))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(ESTADO_CLIENTE_COLOR(vm.estado).opacity(0.15), in: Capsule())
                }
            }
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(NoktaPalette.border).frame(height: 1) }

            VStack(alignment: .leading, spacing: 6) {
                Text("NOTAS").font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted)
                TextField("Ej: dejó de responder desde julio…", text: $vm.notas, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(3...6)
                    .padding(8)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: NoktaRadius.button))
                Button("Guardar nota") { Task { await vm.guardarNota() } }
                    .buttonStyle(.glass)
            }
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(NoktaPalette.border).frame(height: 1) }

            if let empresa = vm.cliente?.empresa, !empresa.isEmpty { pf("EMPRESA", empresa) }
            if let wa = vm.cliente?.whatsapp, !wa.isEmpty { pf("WHATSAPP", wa) }
            if let email = vm.cliente?.email, !email.isEmpty { pf("EMAIL", email) }

            VStack(alignment: .leading, spacing: 6) {
                Text("SERVICIOS").font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted)
                let servicios = Array(Set(vm.trabajos.map { ServicioGrupoMap.nombres[$0.grupoResuelto] ?? "—" })).sorted()
                if servicios.isEmpty {
                    Text("—").font(.system(size: 14)).foregroundStyle(NoktaPalette.cream)
                } else {
                    HStack { ForEach(servicios, id: \.self) { s in
                        Text(s).font(.system(size: 11)).foregroundStyle(Color(hex: 0x6495ED))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color(hex: 0x6495ED).opacity(0.15), in: Capsule())
                    } }
                }
            }
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(NoktaPalette.border).frame(height: 1) }

            VStack(alignment: .leading, spacing: 4) {
                Text("TIPO").font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted)
                let tipo = vm.trabajos.count > 1 ? "Frecuente" : "Nuevo"
                Text(tipo).font(NoktaFont.pill).foregroundStyle(tipo == "Frecuente" ? NoktaPalette.green : Color(hex: 0x6495ED))
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background((tipo == "Frecuente" ? NoktaPalette.green : Color(hex: 0x6495ED)).opacity(0.15), in: Capsule())
            }
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(NoktaPalette.border).frame(height: 1) }

            VStack(alignment: .leading, spacing: 4) {
                Text("TRABAJOS").font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted)
                Text("\(vm.trabajos.count)").font(.system(size: 28, weight: .bold)).foregroundStyle(NoktaPalette.cream)
            }
            .padding(.vertical, 14)
        }
        .padding(20)
        .frame(width: 320, alignment: .leading)
        .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
    }

    private func pf(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted)
            Text(value).font(.system(size: 14)).foregroundStyle(NoktaPalette.cream)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(NoktaPalette.border).frame(height: 1) }
    }

    private var statsRow: some View {
        HStack(spacing: 16) {
            statCard("TOTAL GENERADO", vm.total, NoktaPalette.green)
            statCard("YA COBRADO", vm.cobrado, NoktaPalette.cream)
            statCard("POR COBRAR", vm.porCobrar, NoktaPalette.yellow)
            if vm.retrasadas > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RETRASADAS").font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted)
                    Text("\(vm.retrasadas)").font(.system(size: 22, weight: .bold)).foregroundStyle(NoktaPalette.overdue)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
            }
        }
    }

    private func statCard(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted)
            Text("$" + String(format: "%.2f", value)).font(.system(size: 22, weight: .bold)).foregroundStyle(color)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
    }

    private var trabajosCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("HISTORIAL DE TRABAJOS").font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted).padding(16)
            if vm.trabajos.isEmpty {
                Text("Sin trabajos").font(.system(size: 13)).foregroundStyle(NoktaPalette.muted)
                    .frame(maxWidth: .infinity, alignment: .center).padding(24)
            } else {
                ForEach(vm.trabajos, id: \.id) { t in
                    Button { vm.trabajoIdMostrado = t.id } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.servicio).font(.system(size: 14))
                                if let gn = ServicioGrupoMap.nombres[t.grupoResuelto] {
                                    Text(gn).font(.system(size: 10)).foregroundStyle(NoktaPalette.muted)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Text(FechaUtil.fechaCorta(t.fecha ?? t.fechaInicio)).frame(maxWidth: .infinity, alignment: .leading)
                            Text("$" + String(format: "%.2f", t.grupoResuelto == "B" ? (t.quincenas ?? []).filter { $0.estado == "pagado" }.reduce(0) { $0 + ($1.monto ?? 0) } : (t.monto ?? 0)))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(t.estado == "pagado" ? "Pagado" : "Pendiente")
                                .font(NoktaFont.pill).foregroundStyle(t.estado == "pagado" ? NoktaPalette.green : NoktaPalette.yellow)
                                .padding(.horizontal, 10).padding(.vertical, 3)
                                .background((t.estado == "pagado" ? NoktaPalette.green : NoktaPalette.yellow).opacity(0.15), in: Capsule())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(NoktaFont.tableCell).foregroundStyle(NoktaPalette.cream)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if t.id != vm.trabajos.last?.id { Divider().overlay(NoktaPalette.border) }
                }
            }
        }
        .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
    }
}

private struct ClienteSheetId: Identifiable { let id: String }
