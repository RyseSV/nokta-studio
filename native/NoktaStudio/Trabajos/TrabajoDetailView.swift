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

    func editarMontoQuincena(periodo: String, q: Int, monto: Double) async {
        var qs = trabajo?.quincenas ?? []
        if let idx = qs.firstIndex(where: { $0.periodo == periodo && $0.q == q }) {
            qs[idx] = NoktaQuincena(periodo: periodo, q: q, monto: monto, estado: qs[idx].estado, fechaPago: qs[idx].fechaPago)
        } else {
            qs.append(NoktaQuincena(periodo: periodo, q: q, monto: monto, estado: "pendiente", fechaPago: nil))
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

    func revertirSesion(_ sesionId: String) async {
        let sesiones = (trabajo?.sesiones ?? []).map { s in
            s.id == sesionId ? NoktaSesion(id: s.id, fecha: s.fecha, monto: s.monto, estado: "pendiente", fechaPago: nil) : s
        }
        await guardarSesiones(sesiones)
    }

    func editarMontoSesion(_ sesionId: String, monto: Double) async {
        let sesiones = (trabajo?.sesiones ?? []).map { s in
            s.id == sesionId ? NoktaSesion(id: s.id, fecha: s.fecha, monto: monto, estado: s.estado, fechaPago: s.fechaPago) : s
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
    @State private var editarQuincenaCtx: (periodo: String, q: Int)?
    @State private var editarSesionCtx: String?
    @State private var agregarSesionShown = false
    @State private var facturaPreview: FacturaPreviewItem?
    @State private var facturaErrorMessage: String?
    @State private var eliminarTrabajoConfirm = false
    @State private var eliminarSesionConfirm: String?
    @State private var contratoSheetShown = false
    @State private var contratoErrorMessage: String?
    @State private var aparecio = false
    @State private var ancho: CGFloat = 1000

    init(trabajoId: String, onBack: @escaping () -> Void = {}) {
        self.trabajoId = trabajoId
        self.onBack = onBack
        _vm = State(initialValue: TrabajoDetailViewModel(trabajoId: trabajoId))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header.noktaEntrada(aparecio, 0)

                if let t = vm.trabajo {
                    let ancha = ancho >= 900
                    let layout = ancha
                        ? AnyLayout(HStackLayout(alignment: .top, spacing: 20))
                        : AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
                    layout {
                        VStack(spacing: 20) {
                            resumenCobro(t).noktaEntrada(aparecio, 1)
                            datosCard(t).noktaEntrada(aparecio, 2)
                        }
                        .frame(width: ancha ? 380 : nil)
                        .frame(maxWidth: ancha ? 380 : .infinity)
                        periodoPanel(t)
                            .frame(maxWidth: .infinity)
                            .noktaEntrada(aparecio, 3)
                    }
                } else if let error = vm.errorMessage {
                    NoktaVacio(icono: "exclamationmark.triangle", titulo: "No se pudo abrir el trabajo", detalle: error)
                        .noktaCard()
                } else {
                    ProgressView().tint(NoktaTheme.marca).frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(.horizontal, ancho < 600 ? 20 : 44)
            .padding(.vertical, ancho < 600 ? 16 : 36)
            .frame(maxWidth: 1240, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(NoktaTheme.fondo)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { ancho = $0 }
        .onAppear { withAnimation(.spring(duration: 0.6, bounce: 0.12)) { aparecio = true } }
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
        .sheet(item: Binding(get: {
            editarQuincenaCtx.map { PagoQuincenaContext(periodo: $0.periodo, q: $0.q) }
        }, set: { if $0 == nil { editarQuincenaCtx = nil } })) { ctx in
            EditarMontoSheet(monto: vm.quincena(periodo: ctx.periodo, q: ctx.q).monto ?? 0) { monto in
                Task { await vm.editarMontoQuincena(periodo: ctx.periodo, q: ctx.q, monto: monto) }
                editarQuincenaCtx = nil
            }
        }
        .sheet(item: Binding(get: {
            editarSesionCtx.map { EditarSesionContext(id: $0) }
        }, set: { if $0 == nil { editarSesionCtx = nil } })) { ctx in
            EditarMontoSheet(monto: (vm.trabajo?.sesiones ?? []).first { $0.id == ctx.id }?.monto ?? 0) { monto in
                Task { await vm.editarMontoSesion(ctx.id, monto: monto) }
                editarSesionCtx = nil
            }
        }
        .sheet(item: $facturaPreview) { item in
            PDFPreviewSheet(url: item.url, title: item.title)
        }
        .alert("No se pudo generar la factura", isPresented: Binding(get: { facturaErrorMessage != nil }, set: { if !$0 { facturaErrorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(facturaErrorMessage ?? "")
        }
        .alert("¿Eliminar este trabajo?", isPresented: $eliminarTrabajoConfirm) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar", role: .destructive) { Task { await vm.eliminar() } }
        }
        .alert("¿Eliminar esta sesión?", isPresented: Binding(get: { eliminarSesionConfirm != nil }, set: { if !$0 { eliminarSesionConfirm = nil } })) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar", role: .destructive) {
                if let id = eliminarSesionConfirm { Task { await vm.eliminarSesion(id) } }
            }
        }
        .sheet(isPresented: $contratoSheetShown) {
            if let t = vm.trabajo {
                ContratoSheet(trabajo: t) { datos in
                    Task { await generarContrato(datos) }
                    contratoSheetShown = false
                }
            }
        }
        .alert("No se pudo generar el contrato", isPresented: Binding(get: { contratoErrorMessage != nil }, set: { if !$0 { contratoErrorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(contratoErrorMessage ?? "")
        }
    }

    private func generarContrato(_ datos: ContratoParaPDF) async {
        do {
            let url = try await ContratoGenerator.generar(datos)
            facturaPreview = FacturaPreviewItem(url: url, title: "Contrato · \(datos.clienteNombre)")
        } catch {
            contratoErrorMessage = error.localizedDescription
        }
    }

    private func generarReciboSesion(_ s: NoktaSesion, en sesiones: [NoktaSesion]) async {
        guard let t = vm.trabajo else { return }
        let visibles = sesiones.filter { $0.estado != "oculta" && $0.estado != "cancelado" }
        let numero = (visibles.firstIndex { $0.id == s.id } ?? 0) + 1
        let html = PDFTemplates.reciboSesion(cliente: t.cliente, servicio: t.servicio, fecha: s.fecha,
                                             numero: numero, total: visibles.count, monto: s.monto ?? 0, fechaPago: s.fechaPago)
        do {
            let url = try await PDFRenderer().renderToPDF(html: html, suggestedName: "Recibo_Clase_\(s.fecha.prefix(10))_\(t.cliente)")
            facturaPreview = FacturaPreviewItem(url: url, title: "Recibo · Clase \(numero)")
        } catch {
            facturaErrorMessage = error.localizedDescription
        }
    }

    private func generarFacturaQ(periodo: String, q: Int, rec: NoktaQuincena, montoQ: Double) async {
        guard let t = vm.trabajo else { return }
        let html = PDFTemplates.facturaQuincena(
            cliente: t.cliente, empresa: t.empresa, servicio: t.servicio,
            periodo: periodo, q: q, monto: rec.monto ?? montoQ, fechaPago: rec.fechaPago
        )
        do {
            let url = try await PDFRenderer().renderToPDF(html: html, suggestedName: "Recibo_\(periodo)_Q\(q)_\(t.cliente)")
            facturaPreview = FacturaPreviewItem(url: url, title: "Recibo · Q\(q)")
        } catch {
            facturaErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Encabezado

    /// Color y texto del estado, misma regla que la lista de Trabajos.
    private func estado(_ t: NoktaTrabajo) -> (texto: String, color: Color) {
        if vm.grupo == "B" || vm.esRecurrente {
            let er = vm.estadoRelacion
            let color = er == "activo" ? NoktaTheme.exito : er == "pausado" ? NoktaTheme.aviso : NoktaTheme.error
            return (ESTADO_CLIENTE_LABEL[er] ?? er.capitalized, color)
        }
        return t.estado == "pagado" ? ("Pagado", NoktaTheme.exito) : ("Pendiente", NoktaTheme.aviso)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button(action: onBack) { Label("Trabajos", systemImage: "chevron.left") }
                    .buttonStyle(NoktaBotonSecundario())
                Spacer()
                if vm.trabajo != nil {
                    Button { contratoSheetShown = true } label: { Label("Contrato", systemImage: "doc.text") }
                        .buttonStyle(NoktaBotonSecundario())
                }
                Button { eliminarTrabajoConfirm = true } label: {
                    Label("Eliminar", systemImage: "trash").foregroundStyle(NoktaTheme.error)
                }
                .buttonStyle(NoktaBotonSecundario())
            }
            if let t = vm.trabajo {
                let e = estado(t)
                VStack(alignment: .leading, spacing: 8) {
                    Text(t.cliente)
                        .font(NoktaFont.poppins(ancho < 600 ? 28 : 34, .light)).tracking(-1)
                        .foregroundStyle(NoktaTheme.texto)
                    HStack(spacing: 10) {
                        NoktaEstado(texto: e.texto, color: e.color, tamano: 11)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(e.color.opacity(0.12), in: Capsule())
                        Text(subtitulo(t))
                            .font(NoktaFont.poppins(13)).foregroundStyle(NoktaTheme.textoSuave)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func subtitulo(_ t: NoktaTrabajo) -> String {
        if vm.esRecurrente, let precio = (t.sesiones ?? []).first?.monto {
            return "\(t.servicio) · \(NoktaFormato.dinero(precio)) por sesión"
        }
        if vm.grupo == "B" { return "\(t.servicio) · \(NoktaFormato.dinero(t.pagoMensual ?? t.monto ?? 0)) al mes" }
        return "\(t.servicio) · \(FechaUtil.fechaCorta(t.fechaEntrega ?? t.fecha))"
    }

    // MARK: - Resumen de cobro (tarjeta grande)

    private enum Tramo { case pagado, sigue, retrasado, falta }

    private var sesionesVisibles: [NoktaSesion] {
        (vm.trabajo?.sesiones ?? []).filter { $0.estado != "oculta" && $0.estado != "cancelado" }.sorted { $0.fecha < $1.fecha }
    }
    private var proximaSesion: NoktaSesion? { sesionesVisibles.first { $0.estado != "pagado" } }

    private var quincenasVisibles: [(periodo: String, q: Int, rec: NoktaQuincena)] {
        vm.periodos.flatMap { p in [1, 2].map { (p, $0, vm.quincena(periodo: p, q: $0)) } }.filter { $0.rec.estado != "oculta" }
    }
    private var proximaQuincena: (periodo: String, q: Int, rec: NoktaQuincena)? {
        quincenasVisibles.first { $0.rec.estado != "pagado" }
    }

    private func datosResumen(_ t: NoktaTrabajo, activo: Bool, cobrado: Double) -> ([Tramo], String, String) {
        var tramos: [Tramo] = []
        var total = ""
        var avance = ""
        if vm.esRecurrente {
            let ses = sesionesVisibles
            let prox = proximaSesion?.id
            tramos = ses.map { $0.estado == "pagado" ? .pagado : ($0.id == prox && activo ? .sigue : .falta) }
            total = "de " + NoktaFormato.dinero(ses.reduce(0) { $0 + ($1.monto ?? 0) })
            avance = "\(ses.filter { $0.estado == "pagado" }.count) de \(ses.count) clases pagadas"
        } else if vm.grupo == "B" {
            let qs = quincenasVisibles
            let prox = proximaQuincena.map { "\($0.periodo)-\($0.q)" }
            tramos = qs.map { x in
                x.rec.estado == "pagado" ? .pagado : x.rec.estado == "retrasado" ? .retrasado : ("\(x.periodo)-\(x.q)" == prox && activo ? .sigue : .falta)
            }
            total = "cobrado · " + NoktaFormato.dinero(t.pagoMensual ?? t.monto ?? 0) + " al mes"
            avance = "\(qs.filter { $0.rec.estado == "pagado" }.count) de \(qs.count) quincenas pagadas"
        } else {
            tramos = []
            total = "de " + NoktaFormato.dinero(t.monto ?? 0)
            let pct = (t.monto ?? 0) > 0 ? Int((cobrado / (t.monto ?? 1) * 100).rounded()) : 0
            avance = "\(pct)% cobrado"
        }

        return (tramos, total, avance)
    }

    @ViewBuilder
    private func resumenCobro(_ t: NoktaTrabajo) -> some View {
        let e = estado(t)
        let activo = !(vm.grupo == "B" || vm.esRecurrente) || vm.estadoRelacion == "activo"
        let cobrado = IngresosCalculator.cobrado(t)
        let (tramos, total, avance) = datosResumen(t, activo: activo, cobrado: cobrado)

        VStack(alignment: .leading, spacing: 0) {
            Text("COBRADO").font(NoktaFont.poppins(10, .medium)).tracking(1.4).foregroundStyle(NoktaTheme.textoTenue)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(NoktaFormato.dinero(cobrado))
                    .font(NoktaFont.poppins(ancho < 600 ? 44 : 56, .light)).tracking(-2.4)
                    .foregroundStyle(NoktaTheme.texto)
                    .contentTransition(.numericText(value: cobrado))
                Text(total).font(NoktaFont.poppins(13)).foregroundStyle(NoktaTheme.textoTenue).lineLimit(1)
            }
            .padding(.top, 4)

            Group {
                if tramos.isEmpty {
                    let monto = t.monto ?? 0
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(NoktaTheme.texto.opacity(0.08))
                            Capsule().fill(e.color)
                                .frame(width: g.size.width * (monto > 0 ? min(1, cobrado / monto) : 0))
                                .shadow(color: e.color.opacity(0.5), radius: 6)
                        }
                    }
                    .frame(height: 8)
                } else {
                    HStack(spacing: tramos.count > 12 ? 3 : 6) {
                        ForEach(Array(tramos.enumerated()), id: \.offset) { _, tr in
                            let c: Color = switch tr {
                            case .pagado: NoktaTheme.exito
                            case .sigue: NoktaTheme.aviso
                            case .retrasado: NoktaTheme.error
                            case .falta: NoktaTheme.texto.opacity(0.1)
                            }
                            Capsule().fill(c).frame(height: 8)
                                .shadow(color: tr == .falta ? .clear : c.opacity(0.5), radius: 5)
                        }
                    }
                }
            }
            .padding(.top, 18)
            .animation(.spring(duration: 0.5), value: cobrado)

            Text(avance).font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoTenue).padding(.top, 8)

            accionPrincipal(t, activo: activo).padding(.top, 20)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .noktaFoco(e.color, radio: 22)
    }

    @ViewBuilder
    private func accionPrincipal(_ t: NoktaTrabajo, activo: Bool) -> some View {
        if !activo {
            linea("Contrato", vm.estadoRelacion == "pausado" ? "en pausa" : "cancelado", color: estado(t).color)
        } else if vm.esRecurrente {
            if let p = proximaSesion {
                VStack(alignment: .leading, spacing: 14) {
                    linea("Próxima clase", diaLargo(p.fecha) + " · " + NoktaFormato.dinero(p.monto ?? 0), color: NoktaTheme.aviso)
                    botonGrande("Marcar la clase del \(diaCorto(p.fecha)) como pagada") {
                        Task { await vm.marcarSesionPagada(p.id) }
                    }
                }
            } else {
                linea("Clases", "todas pagadas ✓", color: NoktaTheme.exito)
            }
        } else if vm.grupo == "B" {
            if let x = proximaQuincena {
                VStack(alignment: .leading, spacing: 14) {
                    linea(x.rec.estado == "retrasado" ? "Quincena retrasada" : "Próxima quincena",
                          etiquetaQuincena(x.periodo, x.q) + " · " + NoktaFormato.dinero(x.rec.monto ?? (t.pagoMensual ?? 0) / 2),
                          color: x.rec.estado == "retrasado" ? NoktaTheme.error : NoktaTheme.aviso)
                    botonGrande("Registrar pago de esta quincena") { pagoQuincenaCtx = (x.periodo, x.q) }
                }
            } else {
                linea("Quincenas", "al día ✓", color: NoktaTheme.exito)
            }
        } else if t.estado != "pagado" {
            VStack(alignment: .leading, spacing: 14) {
                linea("Falta cobrar", NoktaFormato.dinero(max(0, t.saldo ?? 0)) + (t.fechaEntrega ?? t.fecha).map { " · " + diaLargo($0) }.orEmpty, color: NoktaTheme.aviso)
                botonGrande("Marcar como pagado completo") { Task { await vm.marcarPagado() } }
            }
        } else {
            linea("Cobrado", "completo ✓", color: NoktaTheme.exito)
        }
    }

    private func linea(_ a: String, _ b: String, color: Color) -> some View {
        (Text(a + " · ").foregroundStyle(NoktaTheme.textoSuave) + Text(b).foregroundStyle(color).fontWeight(.medium))
            .font(NoktaFont.poppins(13))
    }

    private func botonGrande(_ titulo: String, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Text(titulo)
                .font(NoktaFont.poppins(12.5, .medium))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity).frame(height: 42)
                .background(
                    LinearGradient(colors: [Color(red: 0.855, green: 0.478, blue: 0.282), Color(red: 0.72, green: 0.32, blue: 0.157)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .shadow(color: NoktaTheme.marca.opacity(0.35), radius: 10, y: 6)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Datos del trabajo

    private func datosCard(_ t: NoktaTrabajo) -> some View {
        var filas: [(String, String)] = [("Servicio", t.servicio + (t.grupoNombre.map { " · \($0)" } ?? ""))]
        if vm.esRecurrente {
            let ses = sesionesVisibles
            if let precio = ses.first?.monto { filas.append(("Precio por clase", NoktaFormato.dinero(precio))) }
            filas.append(("Total programado", NoktaFormato.dinero(ses.reduce(0) { $0 + ($1.monto ?? 0) }) + " (\(ses.count) clases)"))
            filas.append(("Sin pagar (todas)", NoktaFormato.dinero(ses.filter { $0.estado != "pagado" }.reduce(0) { $0 + ($1.monto ?? 0) })))
        } else {
            switch vm.grupo {
            case "A":
                filas.append(("Fecha", FechaUtil.fechaCorta(t.fecha)))
                if let hi = t.horaInicio, !hi.isEmpty { filas.append(("Horario", hi + (t.horaFin.flatMap { $0.isEmpty ? nil : " – \($0)" } ?? ""))) }
                if let l = t.lugar, !l.isEmpty { filas.append(("Lugar", l)) }
                filas.append(("Monto total", NoktaFormato.dinero(t.monto ?? 0)))
                filas.append(("Anticipo", NoktaFormato.dinero(t.anticipo ?? 0)))
                filas.append(("Saldo pendiente", NoktaFormato.dinero(t.estado == "pagado" ? 0 : (t.saldo ?? 0))))
            case "B":
                if let e = t.empresa, !e.isEmpty { filas.append(("Empresa", e)) }
                filas.append(("Pago mensual", NoktaFormato.dinero(t.pagoMensual ?? 0)))
                filas.append(("Inicio del contrato", FechaUtil.fechaCorta(t.fechaInicio)))
                if let d = t.diaCobro, !d.isEmpty { filas.append(("Día de cobro", "Día \(d)")) }
                filas.append(("Contrato", ESTADO_CLIENTE_LABEL[vm.estadoRelacion] ?? vm.estadoRelacion))
            case "C":
                if let cp = t.cantPiezas, !cp.isEmpty { filas.append(("Piezas", cp)) }
                if let f = t.formato, !f.isEmpty { filas.append(("Formato", f.capitalized)) }
                filas.append(("Entrega estimada", FechaUtil.fechaCorta(t.fechaEntrega)))
                filas.append(("Monto total", NoktaFormato.dinero(t.monto ?? 0)))
                filas.append(("Saldo", NoktaFormato.dinero(t.estado == "pagado" ? 0 : (t.saldo ?? 0))))
            default:
                if let e = t.empresa, !e.isEmpty { filas.append(("Empresa", e)) }
                filas.append(("Entrega estimada", FechaUtil.fechaCorta(t.fechaEntrega)))
                if let a = t.alcance, !a.isEmpty { filas.append(("Alcance", a)) }
                filas.append(("Monto total", NoktaFormato.dinero(t.monto ?? 0)))
                filas.append(("Saldo", NoktaFormato.dinero(t.estado == "pagado" ? 0 : (t.saldo ?? 0))))
            }
        }
        if let n = t.notas, !n.isEmpty { filas.append(("Notas", n)) }

        return VStack(alignment: .leading, spacing: 0) {
            Text("DATOS DEL TRABAJO").font(NoktaFont.poppins(10, .medium)).tracking(1.4).foregroundStyle(NoktaTheme.textoTenue)
                .padding(.bottom, 8)
            ForEach(Array(filas.enumerated()), id: \.offset) { i, f in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(f.0).foregroundStyle(NoktaTheme.textoSuave)
                    Spacer(minLength: 12)
                    Text(f.1).foregroundStyle(NoktaTheme.texto).fontWeight(.medium)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                .font(NoktaFont.poppins(12.5))
                .padding(.vertical, 11)
                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(NoktaTheme.borde).frame(height: 1) } }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .noktaFoco(NoktaTheme.marca, radio: 22)
    }

    // MARK: - Pagos (sesiones / quincenas / trabajo suelto)

    @ViewBuilder
    private func periodoPanel(_ t: NoktaTrabajo) -> some View {
        if vm.grupo == "B" {
            quincenasPanel(t)
        } else if vm.esRecurrente {
            sesionesPanel(t)
        } else {
            pagosSueltos(t)
        }
    }

    private func tituloPanel(_ texto: String, _ detalle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(texto).font(NoktaFont.poppins(10, .medium)).tracking(1.4).foregroundStyle(NoktaTheme.textoTenue)
            Spacer()
            Text(detalle).font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoTenue)
        }
        .padding(.horizontal, 4)
    }

    /// Una fila de pago: punto de estado, fecha/concepto, pastilla y acciones.
    private func filaPago<Acciones: View>(titulo: String, detalle: String, estado: (String, Color), resaltar: Bool,
                                          @ViewBuilder acciones: () -> Acciones) -> some View {
        let (txt, c) = estado
        let info = HStack(spacing: 14) {
            Circle().fill(c).frame(width: 9, height: 9).shadow(color: c.opacity(0.6), radius: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(NoktaFont.poppins(14, .medium)).foregroundStyle(NoktaTheme.texto)
                Text(detalle).font(NoktaFont.poppins(11)).foregroundStyle(resaltar ? NoktaTheme.aviso : NoktaTheme.textoTenue)
            }
            Spacer(minLength: 8)
            NoktaEstado(texto: txt, color: c, tamano: 11)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(c.opacity(0.12), in: Capsule())
        }
        let botones = HStack(spacing: 8) { acciones() }
        return Group {
            if ancho < 700 {
                VStack(alignment: .leading, spacing: 10) {
                    info
                    ScrollView(.horizontal, showsIndicators: false) { botones }
                }
            } else {
                HStack(spacing: 14) { info; botones }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(FondoFila(resaltar: resaltar))
    }

    private func masAcciones(editar: @escaping () -> Void, borrarTitulo: String, borrar: @escaping () -> Void) -> some View {
        Menu {
            Button(action: editar) { Label("Editar monto", systemImage: "pencil") }
            Button(role: .destructive, action: borrar) { Label(borrarTitulo, systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium))
                .foregroundStyle(NoktaTheme.textoSuave)
                .frame(width: 34, height: 34)
                .background(NoktaTheme.superficie2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("Más acciones")
    }

    private func sesionesPanel(_ t: NoktaTrabajo) -> some View {
        let sesiones = (t.sesiones ?? []).sorted { $0.fecha < $1.fecha }
        let prox = proximaSesion?.id
        let activo = vm.estadoRelacion == "activo"
        return VStack(alignment: .leading, spacing: 10) {
            tituloPanel("SESIONES", "\(sesiones.filter { $0.estado == "pagado" }.count) de \(sesiones.count) pagadas")
            if sesiones.isEmpty {
                NoktaVacio(icono: "calendar", titulo: "Sin sesiones registradas", detalle: "Agrega la primera clase abajo.").noktaCard()
            }
            ForEach(sesiones, id: \.id) { s in
                let pagado = s.estado == "pagado"
                let esProx = s.id == prox && activo
                filaPago(titulo: diaLargo(s.fecha),
                         detalle: NoktaFormato.dinero(s.monto ?? 0) + (esProx ? " · la que sigue" : ""),
                         estado: pagado ? ("Pagada", NoktaTheme.exito) : esProx ? ("Por cobrar", NoktaTheme.aviso) : ("Programada", NoktaTheme.textoSuave),
                         resaltar: esProx) {
                    if pagado {
                        Button { Task { await generarReciboSesion(s, en: sesiones) } } label: {
                            Label("Recibo", systemImage: "doc.richtext")
                        }
                        .buttonStyle(NoktaBotonSecundario())
                        Button("Revertir") { Task { await vm.revertirSesion(s.id) } }.buttonStyle(NoktaBotonSecundario())
                    } else {
                        Button("Marcar pagada") { Task { await vm.marcarSesionPagada(s.id) } }.buttonStyle(NoktaBotonPrimario())
                    }
                    masAcciones(editar: { editarSesionCtx = s.id }, borrarTitulo: "Eliminar sesión") { eliminarSesionConfirm = s.id }
                }
            }
            Button { agregarSesionShown = true } label: { Label("Agregar sesión", systemImage: "plus") }
                .buttonStyle(NoktaBotonSecundario())
                .padding(.top, 4)
        }
    }

    private func quincenasPanel(_ t: NoktaTrabajo) -> some View {
        let montoQ = (t.pagoMensual ?? 0) / 2
        let qs = quincenasVisibles
        let prox = proximaQuincena.map { "\($0.periodo)-\($0.q)" }
        let activo = vm.estadoRelacion == "activo"
        return VStack(alignment: .leading, spacing: 10) {
            tituloPanel("QUINCENAS", "\(qs.filter { $0.rec.estado == "pagado" }.count) de \(qs.count) pagadas")
            if qs.isEmpty {
                NoktaVacio(icono: "calendar", titulo: "Sin quincenas", detalle: "Aparecerán desde el inicio del contrato.").noktaCard()
            }
            ForEach(Array(qs.enumerated()), id: \.offset) { _, x in
                let rec = x.rec
                let esProx = "\(x.periodo)-\(x.q)" == prox && activo
                let est: (String, Color) = rec.estado == "pagado" ? ("Pagada", NoktaTheme.exito)
                    : rec.estado == "retrasado" ? ("Retrasada", NoktaTheme.error)
                    : esProx ? ("Por cobrar", NoktaTheme.aviso) : ("Pendiente", NoktaTheme.textoSuave)
                filaPago(titulo: etiquetaQuincena(x.periodo, x.q),
                         detalle: NoktaFormato.dinero(rec.monto ?? montoQ) + (rec.fechaPago.map { " · pagada " + FechaUtil.fechaCorta($0) } ?? (esProx ? " · la que sigue" : "")),
                         estado: est, resaltar: esProx) {
                    if rec.estado == "pagado" {
                        Button { Task { await generarFacturaQ(periodo: x.periodo, q: x.q, rec: rec, montoQ: montoQ) } } label: {
                            Label("Recibo", systemImage: "doc.richtext")
                        }
                        .buttonStyle(NoktaBotonSecundario())
                    } else {
                        Button("Pagada") { pagoQuincenaCtx = (x.periodo, x.q) }.buttonStyle(NoktaBotonPrimario())
                        if rec.estado != "retrasado" {
                            Button("Retrasada") { Task { await vm.marcarQuincenaRetrasada(periodo: x.periodo, q: x.q) } }
                                .buttonStyle(NoktaBotonSecundario())
                        }
                    }
                    masAcciones(editar: { editarQuincenaCtx = (x.periodo, x.q) }, borrarTitulo: "Ocultar quincena") {
                        Task { await vm.ocultarQuincena(periodo: x.periodo, q: x.q) }
                    }
                }
            }
        }
    }

    /// Trabajos sueltos: anticipo y saldo como dos pagos.
    private func pagosSueltos(_ t: NoktaTrabajo) -> some View {
        let pagado = t.estado == "pagado"
        let anticipo = t.anticipo ?? 0
        let saldo = pagado ? 0 : max(0, t.saldo ?? max(0, (t.monto ?? 0) - anticipo))
        return VStack(alignment: .leading, spacing: 10) {
            tituloPanel("PAGOS", pagado ? "cobrado completo" : "falta " + NoktaFormato.dinero(saldo))
            filaPago(titulo: "Anticipo", detalle: NoktaFormato.dinero(anticipo),
                     estado: anticipo > 0 || pagado ? ("Recibido", NoktaTheme.exito) : ("Sin anticipo", NoktaTheme.textoSuave),
                     resaltar: false) { EmptyView() }
            filaPago(titulo: "Saldo", detalle: pagado ? "Pagado completo" : NoktaFormato.dinero(saldo) + (t.fechaEntrega ?? t.fecha).map { " · " + diaLargo($0) }.orEmpty,
                     estado: pagado ? ("Pagado", NoktaTheme.exito) : ("Por cobrar", NoktaTheme.aviso),
                     resaltar: !pagado) {
                if !pagado {
                    Button("Marcar pagado") { Task { await vm.marcarPagado() } }.buttonStyle(NoktaBotonPrimario())
                }
            }
        }
    }

    // MARK: - Fechas

    private static let isoParser: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()
    private func fechaDe(_ iso: String) -> Date? { Self.isoParser.date(from: String(iso.prefix(10))) }
    private func formatear(_ iso: String, _ formato: String) -> String {
        guard let d = fechaDe(iso) else { return FechaUtil.fechaCorta(iso) }
        let f = DateFormatter(); f.locale = Locale(identifier: "es"); f.dateFormat = formato
        return f.string(from: d).replacingOccurrences(of: ".", with: "")
    }
    /// "sáb 26 sep 2026"
    private func diaLargo(_ iso: String) -> String { formatear(iso, "EEE d MMM yyyy") }
    /// "26 sep"
    private func diaCorto(_ iso: String) -> String { formatear(iso, "d MMM") }
    private func etiquetaQuincena(_ periodo: String, _ q: Int) -> String {
        let p = periodo.split(separator: "-")
        let mes = (Int(p.count > 1 ? p[1] : "1") ?? 1) - 1
        return "\(FechaUtil.mesesCompletos[max(0, min(11, mes))]) \(p.first ?? "") · \(QuincenaEngine.labelDeQ(q))"
    }
}

private struct PagoQuincenaContext: Identifiable { let periodo: String; let q: Int; var id: String { "\(periodo)-\(q)" } }
private struct EditarSesionContext: Identifiable { let id: String }
private struct FacturaPreviewItem: Identifiable { let id = UUID(); let url: URL; let title: String }

private struct EditarMontoSheet: View {
    @State var monto: Double
    let onConfirm: (Double) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Editar monto").font(.system(size: 16, weight: .semibold))
            TextField("Monto", value: $monto, format: .number).textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancelar") { dismiss() }
                Spacer()
                Button("✓ Guardar") {
                    onConfirm(monto)
                    dismiss()
                }.buttonStyle(.glassProminent).tint(NoktaPalette.ember)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}

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

/// Editable fields for a contract before it's rendered to PDF — pre-filled
/// from the trabajo where the data already exists (cliente, servicio,
/// fecha, monto), left blank where it doesn't (DUI, dirección, entregables)
/// so the user fills those in per client. This is where "editable" lives:
/// the generated PDF itself is a filled document, not a fillable form.
/// Not private — ContratosView's "+ Nuevo contrato" picker reuses it too.
struct ContratoSheet: View {
    let trabajo: NoktaTrabajo
    let onGenerar: (ContratoParaPDF) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var ciudad = "San Salvador"
    @State private var fechaContrato = Date()
    @State private var clienteNombre: String
    @State private var clienteDui = ""
    @State private var clienteTelefono = ""
    @State private var clienteEmail = ""
    @State private var clienteDireccion = ""
    @State private var servicioTipo: String
    @State private var servicioFecha: String
    @State private var servicioLugar: String
    @State private var entregables = ""
    @State private var anticipoMonto: Double
    @State private var anticipoFecha = Date()
    @State private var saldoMonto: Double
    @State private var saldoFecha = Date()
    @State private var plazoDias = "7"
    @State private var mora: Double = 10
    @State private var validationError: String?

    init(trabajo: NoktaTrabajo, onGenerar: @escaping (ContratoParaPDF) -> Void) {
        self.trabajo = trabajo
        self.onGenerar = onGenerar
        _clienteNombre = State(initialValue: trabajo.cliente)
        _servicioTipo = State(initialValue: trabajo.servicio)
        _servicioFecha = State(initialValue: FechaUtil.fechaCorta(trabajo.fecha ?? trabajo.fechaInicio))
        _servicioLugar = State(initialValue: trabajo.lugar ?? "")
        let total = trabajo.grupoResuelto == "B" ? (trabajo.pagoMensual ?? 0) : (trabajo.monto ?? 0)
        let esSesion = trabajo.servicio == "Clases" || !(trabajo.sesiones ?? []).isEmpty
        let anticipo = esSesion ? 0 : max(0, min(total, trabajo.anticipo ?? 0))
        _anticipoMonto = State(initialValue: anticipo)
        _saldoMonto = State(initialValue: total - anticipo)
    }

    private func row(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(NoktaPalette.muted)
            TextField(label, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func moneyRow(_ label: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(NoktaPalette.muted)
            TextField(label, value: value, format: .number).textFieldStyle(.roundedBorder)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Generar contrato").font(.system(size: 17, weight: .semibold)).foregroundStyle(NoktaPalette.cream)
                Text("Se llena con los datos del cliente; ajusta lo que haga falta antes de generar el PDF.")
                    .font(.system(size: 12)).foregroundStyle(NoktaPalette.muted)

                row("Ciudad del contrato", $ciudad)
                DatePicker("Fecha del contrato", selection: $fechaContrato, displayedComponents: .date)

                row("Nombre del cliente *", $clienteNombre)
                HStack(spacing: 10) { row("DUI *", $clienteDui); row("Teléfono", $clienteTelefono) }
                if let validationError {
                    Text(validationError).font(.system(size: 12)).foregroundStyle(NoktaPalette.red)
                }
                row("Correo electrónico", $clienteEmail)
                row("Dirección", $clienteDireccion)

                row("Servicio contratado", $servicioTipo)
                HStack(spacing: 10) { row("Fecha del servicio", $servicioFecha); row("Lugar", $servicioLugar) }
                row("Entregables", $entregables)

                HStack(spacing: 10) {
                    moneyRow("Anticipo (USD)", $anticipoMonto)
                    DatePicker("Fecha límite anticipo", selection: $anticipoFecha, displayedComponents: .date)
                }
                HStack(spacing: 10) {
                    moneyRow("Saldo (USD)", $saldoMonto)
                    DatePicker("Fecha límite saldo", selection: $saldoFecha, displayedComponents: .date)
                }
                HStack(spacing: 10) {
                    row("Plazo de entrega (días hábiles)", $plazoDias)
                    moneyRow("Mora por día (USD)", $mora)
                }

                HStack {
                    Button("Cancelar") { dismiss() }
                    Spacer()
                    Button("📜 Generar PDF") {
                        guard !clienteNombre.trimmingCharacters(in: .whitespaces).isEmpty,
                              !clienteDui.trimmingCharacters(in: .whitespaces).isEmpty else {
                            validationError = "Escribe el nombre y el DUI del cliente antes de generar el contrato"
                            return
                        }
                        guard [anticipoMonto, saldoMonto, mora].allSatisfy({ $0.isFinite && $0 >= 0 }) else {
                            validationError = "Escribe montos válidos mayores o iguales a cero"
                            return
                        }
                        validationError = nil
                        let f = DateFormatter(); f.dateFormat = "d 'de' MMMM 'de' yyyy"; f.locale = Locale(identifier: "es_MX")
                        onGenerar(ContratoParaPDF(
                            trabajoId: trabajo.id, ciudad: ciudad, fechaContrato: f.string(from: fechaContrato),
                            clienteNombre: clienteNombre, clienteDui: clienteDui, clienteTelefono: clienteTelefono,
                            clienteEmail: clienteEmail, clienteDireccion: clienteDireccion,
                            servicioTipo: servicioTipo, servicioFecha: servicioFecha, servicioLugar: servicioLugar,
                            entregables: entregables, anticipoMonto: anticipoMonto,
                            anticipoFecha: f.string(from: anticipoFecha), saldoMonto: saldoMonto,
                            saldoFecha: f.string(from: saldoFecha), plazoDias: plazoDias, mora: mora
                        ))
                    }.buttonStyle(.glassProminent).tint(NoktaPalette.ember)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: 460, maxHeight: 640)
    }
}

/// Fondo de cada fila de pago: la que sigue lleva el foco en amarillo.
private struct FondoFila: ViewModifier {
    let resaltar: Bool
    func body(content: Content) -> some View {
        if resaltar {
            content.noktaFoco(NoktaTheme.aviso, radio: 16)
        } else {
            content
                .background(NoktaTheme.superficie, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(NoktaTheme.borde))
                .noktaHover(radio: 16)
        }
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}
