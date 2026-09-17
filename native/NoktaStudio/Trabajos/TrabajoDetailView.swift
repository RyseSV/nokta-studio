import SwiftUI

@Observable
final class TrabajoDetailViewModel {
    let trabajoId: String
    var trabajo: NoktaTrabajo?
    var estadoRelacion: String = "activo"
    var isLoading = true
    var errorMessage: String?
    var didDelete = false

    init(trabajoId: String) { self.trabajoId = trabajoId }

    var esRecurrente: Bool { trabajo?.servicio == "Clases" }
    var grupo: String { trabajo?.grupoResuelto ?? "" }
    var periodos: [String] {
        QuincenaEngine.generarPeriodos(fechaInicio: trabajo?.fechaInicio, estadoRelacion: estadoRelacion, quincenasGuardadas: trabajo?.quincenas ?? [])
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let tsFetch: [NoktaTrabajo] = NoktaAPI.get("/api/trabajos")
            async let esFetch: [NoktaClienteEstado] = NoktaAPI.get("/api/clientes-estados")
            let (trabajosList, estados) = try await (tsFetch, esFetch)
            guard var t = trabajosList.first(where: { $0.id == trabajoId }) else {
                errorMessage = "Trabajo no encontrado"; return
            }
            estadoRelacion = estados.first(where: { $0.nombre == t.cliente })?.estado ?? "activo"

            if t.grupoResuelto == "B", (t.quincenas ?? []).isEmpty {
                t = try await bootstrapQuincenas(t)
            }
            if t.servicio == "Clases", (t.sesiones ?? []).isEmpty {
                t = try await bootstrapSesiones(t)
            }
            trabajo = t
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func bootstrapQuincenas(_ t: NoktaTrabajo) async throws -> NoktaTrabajo {
        let periodos = QuincenaEngine.generarPeriodos(fechaInicio: t.fechaInicio, estadoRelacion: estadoRelacion, quincenasGuardadas: [])
        let montoQ = (t.pagoMensual ?? 0) / 2
        let qs = periodos.flatMap { p in [1, 2].map { q in NoktaQuincena(periodo: p, q: q, monto: montoQ, estado: "pendiente", fechaPago: nil) } }
        struct Body: Encodable { let quincenas: [NoktaQuincena] }
        struct Resp: Decodable { let ok: Bool?; let quincenas: [NoktaQuincena]? }
        let resp: Resp = try await NoktaAPI.patch("/api/trabajos/\(t.id)/quincenas", body: Body(quincenas: qs))
        var updated = t
        updated.quincenas = resp.quincenas ?? qs
        return updated
    }

    private func bootstrapSesiones(_ t: NoktaTrabajo) async throws -> NoktaTrabajo {
        let sesion = NoktaSesion(
            id: "s\(Int(Date().timeIntervalSince1970 * 1000))",
            fecha: t.fecha ?? FechaUtil.hoyISO(),
            monto: t.monto ?? 20,
            estado: t.estado == "pagado" ? "pagado" : "pendiente",
            fechaPago: t.estado == "pagado" ? (t.creado ?? FechaUtil.ahoraISO()) : nil
        )
        struct Body: Encodable { let sesiones: [NoktaSesion] }
        struct Resp: Decodable { let ok: Bool?; let trabajo: NoktaTrabajo? }
        let resp: Resp = try await NoktaAPI.patch("/api/trabajos/\(t.id)/sesiones", body: Body(sesiones: [sesion]))
        return resp.trabajo ?? t
    }

    func marcarPagado() async {
        guard let t = trabajo else { return }
        struct Body: Encodable { let estado: String; let anticipo: Double; let saldo: Double }
        struct Resp: Decodable { let ok: Bool?; let trabajo: NoktaTrabajo? }
        if let resp: Resp = try? await NoktaAPI.put("/api/trabajos/\(t.id)", body: Body(estado: "pagado", anticipo: t.monto ?? 0, saldo: 0)) {
            trabajo = resp.trabajo ?? t
        }
        await load()
    }

    func eliminar() async {
        guard let t = trabajo else { return }
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp? = try? await NoktaAPI.delete("/api/trabajos/\(t.id)")
        didDelete = true
    }

    // MARK: Quincenas
    func guardarQuincenas(_ qs: [NoktaQuincena]) async {
        guard let t = trabajo else { return }
        struct Body: Encodable { let quincenas: [NoktaQuincena] }
        struct Resp: Decodable { let ok: Bool?; let quincenas: [NoktaQuincena]? }
        if let resp: Resp = try? await NoktaAPI.patch("/api/trabajos/\(t.id)/quincenas", body: Body(quincenas: qs)) {
            trabajo?.quincenas = resp.quincenas ?? qs
        }
    }

    func quincena(periodo: String, q: Int) -> NoktaQuincena {
        let montoQ = (trabajo?.pagoMensual ?? 0) / 2
        return (trabajo?.quincenas ?? []).first { $0.periodo == periodo && $0.q == q }
            ?? NoktaQuincena(periodo: periodo, q: q, monto: montoQ, estado: "pendiente", fechaPago: nil)
    }

    func marcarQuincenaPagada(periodo: String, q: Int, monto: Double, fecha: String) async {
        var qs = trabajo?.quincenas ?? []
        if let idx = qs.firstIndex(where: { $0.periodo == periodo && $0.q == q }) {
            qs[idx] = NoktaQuincena(periodo: periodo, q: q, monto: monto, estado: "pagado", fechaPago: fecha)
        } else {
            qs.append(NoktaQuincena(periodo: periodo, q: q, monto: monto, estado: "pagado", fechaPago: fecha))
        }
        await guardarQuincenas(qs)
    }

    func marcarQuincenaRetrasada(periodo: String, q: Int) async {
        var qs = trabajo?.quincenas ?? []
        let montoQ = (trabajo?.pagoMensual ?? 0) / 2
        if let idx = qs.firstIndex(where: { $0.periodo == periodo && $0.q == q }) {
            qs[idx] = NoktaQuincena(periodo: periodo, q: q, monto: qs[idx].monto ?? montoQ, estado: "retrasado", fechaPago: nil)
        } else {
            qs.append(NoktaQuincena(periodo: periodo, q: q, monto: montoQ, estado: "retrasado", fechaPago: nil))
        }
        await guardarQuincenas(qs)
    }

    func ocultarQuincena(periodo: String, q: Int) async {
        var qs = trabajo?.quincenas ?? []
        if let idx = qs.firstIndex(where: { $0.periodo == periodo && $0.q == q }) {
            qs[idx] = NoktaQuincena(periodo: periodo, q: q, monto: qs[idx].monto, estado: "oculta", fechaPago: qs[idx].fechaPago)
            await guardarQuincenas(qs)
        }
    }

    // MARK: Sesiones
    func guardarSesiones(_ sesiones: [NoktaSesion]) async {
        guard let t = trabajo else { return }
        struct Body: Encodable { let sesiones: [NoktaSesion] }
        struct Resp: Decodable { let ok: Bool?; let trabajo: NoktaTrabajo? }
        if let resp: Resp = try? await NoktaAPI.patch("/api/trabajos/\(t.id)/sesiones", body: Body(sesiones: sesiones)) {
            trabajo = resp.trabajo ?? t
        }
    }

    func marcarSesionPagada(_ sesionId: String) async {
        let sesiones = (trabajo?.sesiones ?? []).map { s in
            s.id == sesionId ? NoktaSesion(id: s.id, fecha: s.fecha, monto: s.monto, estado: "pagado", fechaPago: FechaUtil.ahoraISO()) : s
        }
        await guardarSesiones(sesiones)
    }

    func eliminarSesion(_ sesionId: String) async {
        let sesiones = (trabajo?.sesiones ?? []).filter { $0.id != sesionId }
        await guardarSesiones(sesiones)
    }

    func agregarSesion(fecha: String, monto: Double) async {
        let nueva = NoktaSesion(id: "s\(Int(Date().timeIntervalSince1970 * 1000))", fecha: fecha, monto: monto, estado: "pendiente", fechaPago: nil)
        await guardarSesiones((trabajo?.sesiones ?? []) + [nueva])
    }
}

private extension FechaUtil {
    static func hoyISO() -> String { DateFormatter.isoDayShared.string(from: Date()) }
    static func ahoraISO() -> String { ISO8601DateFormatter().string(from: Date()) }
}
private extension DateFormatter {
    static let isoDayShared: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.calendar = Calendar(identifier: .gregorian); f.timeZone = .current
        return f
    }()
}

struct TrabajoDetailView: View {
    let trabajoId: String
    var onBack: () -> Void = {}
    @State private var vm: TrabajoDetailViewModel
    @State private var pagoQuincenaCtx: (periodo: String, q: Int)?
    @State private var agregarSesionShown = false

    init(trabajoId: String, onBack: @escaping () -> Void = {}) {
        self.trabajoId = trabajoId
        self.onBack = onBack
        _vm = State(initialValue: TrabajoDetailViewModel(trabajoId: trabajoId))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let t = vm.trabajo {
                    HStack(alignment: .top, spacing: 20) {
                        infoCard(t)
                        if vm.grupo == "B" {
                            quincenasPanel(t)
                        } else if vm.esRecurrente {
                            sesionesPanel(t)
                        } else {
                            Text("Sin pagos periódicos para este tipo de servicio.")
                                .font(.system(size: 14)).foregroundStyle(NoktaPalette.muted)
                                .frame(maxWidth: .infinity, minHeight: 120)
                                .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
                        }
                    }
                } else if let error = vm.errorMessage {
                    Text(error).foregroundStyle(NoktaPalette.red)
                } else {
                    ProgressView().tint(NoktaPalette.ember)
                }
            }
            .padding(32)
        }
        .background(NoktaPalette.bg)
        .task { await vm.load() }
        .onChange(of: vm.didDelete) { _, deleted in if deleted { onBack() } }
        .sheet(item: Binding(get: {
            pagoQuincenaCtx.map { PagoQuincenaContext(periodo: $0.periodo, q: $0.q) }
        }, set: { if $0 == nil { pagoQuincenaCtx = nil } })) { ctx in
            PagoQuincenaSheet(monto: vm.quincena(periodo: ctx.periodo, q: ctx.q).monto ?? 0) { monto, fecha in
                Task { await vm.marcarQuincenaPagada(periodo: ctx.periodo, q: ctx.q, monto: monto, fecha: fecha) }
                pagoQuincenaCtx = nil
            }
        }
        .sheet(isPresented: $agregarSesionShown) {
            AgregarSesionSheet(monto: (vm.trabajo?.sesiones ?? []).last?.monto ?? 20) { fecha, monto in
                Task { await vm.agregarSesion(fecha: fecha, monto: monto) }
                agregarSesionShown = false
            }
        }
    }

    private var header: some View {
        HStack {
            Button("← Volver", action: onBack).buttonStyle(.glass)
            Text(vm.trabajo?.cliente ?? "Trabajo").font(NoktaFont.pageTitle).foregroundStyle(NoktaPalette.cream)
            Spacer()
            if vm.grupo != "B", !vm.esRecurrente, vm.trabajo?.estado != "pagado" {
                Button("✓ Marcar pagado") { Task { await vm.marcarPagado() } }
                    .buttonStyle(.glassProminent).tint(NoktaPalette.green)
            }
            Button("🗑 Eliminar", role: .destructive) { Task { await vm.eliminar() } }
                .buttonStyle(.glass)
        }
    }

    // MARK: - Info card

    private func infoCard(_ t: NoktaTrabajo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            pf("SERVICIO", t.servicio + (t.grupoNombre.map { " · \($0)" } ?? ""))
            switch vm.grupo {
            case "A":
                pf("FECHA", FechaUtil.fechaCorta(t.fecha))
                if let hi = t.horaInicio, !hi.isEmpty { pf("HORARIO", hi + (t.horaFin.map { " → \($0)" } ?? "")) }
                if let l = t.lugar, !l.isEmpty { pf("LUGAR", l) }
                bigNumber("MONTO TOTAL", t.monto ?? 0, NoktaPalette.cream)
                pf("ANTICIPO", "$" + String(format: "%.2f", t.anticipo ?? 0))
                bigNumber("SALDO PENDIENTE", t.saldo ?? 0, NoktaPalette.yellow, size: 18)
            case "B":
                if let e = t.empresa, !e.isEmpty { pf("EMPRESA", e) }
                bigNumber("PAGO MENSUAL", t.pagoMensual ?? 0, NoktaPalette.cream)
                pf("INICIO CONTRATO", FechaUtil.fechaCorta(t.fechaInicio))
                pf("ESTADO CONTRATO", ESTADO_CLIENTE_LABEL[vm.estadoRelacion] ?? vm.estadoRelacion)
            case "C":
                if let cp = t.cantPiezas, !cp.isEmpty { pf("PIEZAS", cp) }
                if let f = t.formato { pf("FORMATO", f) }
                pf("ENTREGA ESTIMADA", FechaUtil.fechaCorta(t.fechaEntrega))
                bigNumber("MONTO TOTAL", t.monto ?? 0, NoktaPalette.cream)
                bigNumber("SALDO", t.saldo ?? 0, NoktaPalette.yellow, size: 18)
            default:
                if let e = t.empresa, !e.isEmpty { pf("EMPRESA", e) }
                pf("ENTREGA ESTIMADA", FechaUtil.fechaCorta(t.fechaEntrega))
                if let a = t.alcance, !a.isEmpty { pf("ALCANCE", a) }
                bigNumber("MONTO TOTAL", t.monto ?? 0, NoktaPalette.cream)
                bigNumber("SALDO", t.saldo ?? 0, NoktaPalette.yellow, size: 18)
            }

            if vm.grupo == "B" || vm.esRecurrente {
                let er = vm.estadoRelacion
                estadoPillRow(ESTADO_CLIENTE_LABEL[er] ?? er, color: er == "activo" ? NoktaPalette.green : er == "pausado" ? NoktaPalette.yellow : NoktaPalette.red)
            } else {
                estadoPillRow(t.estado == "pagado" ? "Pagado" : "Pendiente", color: t.estado == "pagado" ? NoktaPalette.green : NoktaPalette.yellow)
            }
            if let notas = t.notas, !notas.isEmpty { pf("NOTAS", notas) }
        }
        .padding(20)
        .frame(width: 300, alignment: .leading)
        .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
    }

    private func pf(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted)
            Text(value).font(.system(size: 14)).foregroundStyle(NoktaPalette.cream)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(NoktaPalette.border).frame(height: 1) }
    }

    private func bigNumber(_ label: String, _ value: Double, _ color: Color, size: CGFloat = 22) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted)
            Text("$" + String(format: "%.2f", value)).font(.system(size: size, weight: .bold)).foregroundStyle(color)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(NoktaPalette.border).frame(height: 1) }
    }

    private func estadoPillRow(_ label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ESTADO").font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted)
            Text(label).font(NoktaFont.pill).foregroundStyle(color)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(color.opacity(0.15), in: Capsule())
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(NoktaPalette.border).frame(height: 1) }
    }

    // MARK: - Quincenas

    private func quincenasPanel(_ t: NoktaTrabajo) -> some View {
        let montoQ = (t.pagoMensual ?? 0) / 2
        let mesesL = ["Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"]
        return VStack(alignment: .leading, spacing: 0) {
            Text("QUINCENAS").font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted).padding(16)
            ForEach(vm.periodos, id: \.self) { periodo in
                ForEach([1, 2], id: \.self) { q in
                    let rec = vm.quincena(periodo: periodo, q: q)
                    if rec.estado != "oculta" {
                        quincenaRow(periodo: periodo, q: q, rec: rec, mesesL: mesesL, montoQ: montoQ)
                        Divider().overlay(NoktaPalette.border)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
    }

    private func quincenaRow(periodo: String, q: Int, rec: NoktaQuincena, mesesL: [String], montoQ: Double) -> some View {
        let parts = periodo.split(separator: "-")
        let mesIdx = (Int(parts.count > 1 ? parts[1] : "1") ?? 1) - 1
        let mesLabel = "\(mesesL[max(0, min(11, mesIdx))]) \(parts.first ?? "")"
        let color: Color = rec.estado == "pagado" ? NoktaPalette.green : rec.estado == "retrasado" ? NoktaPalette.overdue : NoktaPalette.yellow
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(mesLabel).font(.system(size: 14, weight: .semibold)).foregroundStyle(NoktaPalette.cream)
                Text(QuincenaEngine.labelDeQ(q)).font(.system(size: 11)).foregroundStyle(NoktaPalette.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text("$" + String(format: "%.2f", rec.monto ?? montoQ)).frame(maxWidth: .infinity, alignment: .leading)
            Text(rec.estado == "pagado" ? "Pagado" : rec.estado == "retrasado" ? "Retrasado" : "Pendiente")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
            if rec.estado != "pagado" {
                Button("Pagado") { pagoQuincenaCtx = (periodo, q) }
                    .buttonStyle(.glass).tint(NoktaPalette.green)
                if rec.estado != "retrasado" {
                    Button("Retrasado") { Task { await vm.marcarQuincenaRetrasada(periodo: periodo, q: q) } }
                        .buttonStyle(.glass)
                }
            }
            Button(role: .destructive) { Task { await vm.ocultarQuincena(periodo: periodo, q: q) } } label: {
                Image(systemName: "trash")
            }.buttonStyle(.glass)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: - Sesiones

    private func sesionesPanel(_ t: NoktaTrabajo) -> some View {
        let sesiones = (t.sesiones ?? []).sorted { $0.fecha < $1.fecha }
        return VStack(alignment: .leading, spacing: 0) {
            Text("SESIONES").font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted).padding(16)
            if sesiones.isEmpty {
                Text("Sin sesiones registradas").font(.system(size: 13)).foregroundStyle(NoktaPalette.muted)
                    .frame(maxWidth: .infinity, alignment: .center).padding(24)
            }
            ForEach(sesiones, id: \.id) { s in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(FechaUtil.fechaCorta(s.fecha)).font(.system(size: 14, weight: .semibold)).foregroundStyle(NoktaPalette.cream)
                        Text("$" + String(format: "%.2f", s.monto ?? 0)).font(.system(size: 12)).foregroundStyle(NoktaPalette.muted)
                    }
                    Spacer()
                    let pagado = s.estado == "pagado"
                    Text(pagado ? "Pagado" : "Pendiente")
                        .font(NoktaFont.pill).foregroundStyle(pagado ? NoktaPalette.green : NoktaPalette.yellow)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background((pagado ? NoktaPalette.green : NoktaPalette.yellow).opacity(0.15), in: Capsule())
                    if !pagado {
                        Button("Pagado") { Task { await vm.marcarSesionPagada(s.id) } }
                            .buttonStyle(.glass).tint(NoktaPalette.green)
                    }
                    Button(role: .destructive) { Task { await vm.eliminarSesion(s.id) } } label: {
                        Image(systemName: "trash")
                    }.buttonStyle(.glass)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                Divider().overlay(NoktaPalette.border)
            }
            Button("＋ Agregar sesión") { agregarSesionShown = true }
                .buttonStyle(.glass)
                .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
    }
}

private let ESTADO_CLIENTE_LABEL: [String: String] = ["activo": "Activo", "pausado": "Pausado", "cancelado": "Cancelado"]

private struct PagoQuincenaContext: Identifiable { let periodo: String; let q: Int; var id: String { "\(periodo)-\(q)" } }

private struct PagoQuincenaSheet: View {
    @State var monto: Double
    @State private var fecha = Date()
    let onConfirm: (Double, String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Registrar pago").font(.system(size: 16, weight: .semibold))
            TextField("Monto", value: $monto, format: .number).textFieldStyle(.roundedBorder)
            DatePicker("Fecha de pago", selection: $fecha, displayedComponents: .date)
            HStack {
                Button("Cancelar") { dismiss() }
                Spacer()
                Button("✓ Confirmar pago") {
                    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                    onConfirm(monto, f.string(from: fecha))
                    dismiss()
                }.buttonStyle(.glassProminent).tint(NoktaPalette.ember)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}

private struct AgregarSesionSheet: View {
    @State private var fecha = Date()
    @State var monto: Double
    let onConfirm: (String, Double) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Agregar sesión").font(.system(size: 16, weight: .semibold))
            DatePicker("Fecha", selection: $fecha, displayedComponents: .date)
            TextField("Monto", value: $monto, format: .number).textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancelar") { dismiss() }
                Spacer()
                Button("＋ Agregar") {
                    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                    onConfirm(f.string(from: fecha), monto)
                    dismiss()
                }.buttonStyle(.glassProminent).tint(NoktaPalette.ember)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}
