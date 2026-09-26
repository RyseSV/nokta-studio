import SwiftUI

@Observable
final class ClienteDetailViewModel {
    let nombre: String
    var trabajos: [NoktaTrabajo] = []
    var cliente: NoktaCliente?
    var estado: String = "activo"
    var notas: String = ""
    var isLoading = true
    var marcando = false
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
            .sorted { ($0.fechaInicio ?? $0.fecha ?? "") > ($1.fechaInicio ?? $1.fecha ?? "") }
        cliente = (cc ?? []).first { $0.nombre == nombre }
        let ce = (ee ?? []).first { $0.nombre == nombre }
        estado = ce?.estado ?? "activo"
        notas = ce?.notas ?? ""
    }

    private var estadosLocales: [NoktaClienteEstado] { [NoktaClienteEstado(nombre: nombre, estado: estado, notas: nil)] }

    /// Mismas cuentas que Trabajos, Reportes y Analíticas.
    var cobrado: Double { trabajos.reduce(0) { $0 + IngresosCalculator.cobrado($1) } }
    var porCobrar: Double { trabajos.reduce(0) { $0 + IngresosCalculator.porCobrar($1, estados: estadosLocales) } }

    func esContrato(_ t: NoktaTrabajo) -> Bool { t.grupoResuelto == "B" || t.servicio == "Clases" }

    /// El trabajo que manda en la ficha: el que tiene algo por cobrar, o el más reciente.
    var principal: NoktaTrabajo? {
        trabajos.first { IngresosCalculator.porCobrar($0, estados: estadosLocales) > 0 }
            ?? trabajos.first { !esContrato($0) && $0.estado != "pagado" && ($0.saldo ?? 0) > 0 }
            ?? trabajos.first
    }

    /// "desde septiembre 2026" según su primer trabajo.
    var desde: String? {
        let fechas = trabajos.compactMap { $0.fechaInicio ?? $0.fecha }.sorted()
        guard let f = fechas.first, let am = FechaUtil.anioMes(f) else { return nil }
        return "\(FechaUtil.mesesCompletos[am.mes - 1].lowercased()) \(am.anio)"
    }

    // MARK: Pagos del trabajo principal (misma lógica que el detalle de trabajo)

    func sesiones(_ t: NoktaTrabajo) -> [NoktaSesion] {
        (t.sesiones ?? []).filter { $0.estado != "oculta" && $0.estado != "cancelado" }.sorted { $0.fecha < $1.fecha }
    }

    func quincenas(_ t: NoktaTrabajo) -> [(periodo: String, q: Int, rec: NoktaQuincena)] {
        let periodos = QuincenaEngine.generarPeriodos(fechaInicio: t.fechaInicio, estadoRelacion: estado, quincenasGuardadas: t.quincenas ?? [])
        let montoQ = (t.pagoMensual ?? 0) / 2
        return periodos.flatMap { p in
            [1, 2].map { q in
                (p, q, (t.quincenas ?? []).first { $0.periodo == p && $0.q == q }
                    ?? NoktaQuincena(periodo: p, q: q, monto: montoQ, estado: "pendiente", fechaPago: nil))
            }
        }
        .filter { $0.2.estado != "oculta" }
    }

    /// Marca pagada la próxima clase o el saldo de un trabajo suelto, usando el
    /// mismo modelo del detalle de trabajo para no duplicar reglas.
    func marcarSiguiente(_ t: NoktaTrabajo) async {
        marcando = true
        defer { marcando = false }
        let d = TrabajoDetailViewModel(trabajoId: t.id)
        await d.load()
        guard d.trabajo != nil else { return }
        if t.servicio == "Clases" {
            if let s = sesiones(d.trabajo!).first(where: { $0.estado != "pagado" }) { await d.marcarSesionPagada(s.id) }
        } else {
            await d.marcarPagado()
        }
        await load()
    }

    func cambiarEstado(_ nuevo: String) async {
        estado = nuevo
        struct Body: Encodable { let estado: String }
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp? = try? await NoktaAPI.put("/api/clientes-estados/\(nombre.urlPathComponentEncoded)", body: Body(estado: nuevo))
        // Pausar/cancelar al cliente detiene sus paquetes mensuales (grupo B).
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

/// Ficha del cliente con el mismo lenguaje que el detalle de trabajo:
/// cobrado en grande, barra de pagos, lo que sigue, datos y trabajos.
struct ClienteDetailView: View {
    let nombre: String
    var onBack: (() -> Void)?
    var alCambiar: () -> Void = {}
    @State private var vm: ClienteDetailViewModel
    @State private var aparecio = false
    @State private var crecer = false
    @State private var notaGuardada = false
    @State private var ancho: CGFloat = 800

    init(nombre: String, onBack: (() -> Void)? = nil, alCambiar: @escaping () -> Void = {}) {
        self.nombre = nombre
        self.onBack = onBack
        self.alCambiar = alCambiar
        _vm = State(initialValue: ClienteDetailViewModel(nombre: nombre))
    }

    private var colorEstado: Color { ESTADO_CLIENTE_COLOR(vm.estado) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let onBack {
                    Button(action: onBack) { Label("Clientes", systemImage: "chevron.left") }
                        .buttonStyle(.plain).font(NoktaFont.poppins(13)).foregroundStyle(NoktaTheme.marca)
                }
                header.noktaEntrada(aparecio, 0)
                resumen.noktaEntrada(aparecio, 1)
                let columnas = ancho >= 640 ? AnyLayout(HStackLayout(alignment: .top, spacing: 14)) : AnyLayout(VStackLayout(spacing: 14))
                columnas {
                    datos.noktaEntrada(aparecio, 2)
                    listaTrabajos.noktaEntrada(aparecio, 3)
                }
            }
            .padding(.horizontal, ancho < 600 ? 18 : 30).padding(.vertical, 28)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(NoktaTheme.fondo)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { ancho = $0 }
        .task {
            await vm.load()
            withAnimation(.spring(duration: 0.8, bounce: 0.1)) { aparecio = true }
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.spring(duration: 1.0, bounce: 0.05)) { crecer = true }
        }
        .sheet(item: Binding(get: {
            vm.trabajoIdMostrado.map { ClienteSheetId(id: $0) }
        }, set: { if $0 == nil { vm.trabajoIdMostrado = nil } })) { ctx in
            NavigationStack {
                TrabajoDetailView(trabajoId: ctx.id, onBack: { vm.trabajoIdMostrado = nil })
            }
            .frame(minWidth: 980, minHeight: 560)
            .onDisappear { Task { await vm.load(); alCambiar() } }
        }
    }

    // MARK: Encabezado

    private var header: some View {
        HStack(spacing: 14) {
            MonogramaCliente(nombre: nombre, tamano: ancho < 600 ? 46 : 54)
            VStack(alignment: .leading, spacing: 6) {
                Text(nombre)
                    .font(NoktaFont.poppins(ancho < 600 ? 26 : 32, .light)).tracking(-1.2)
                    .foregroundStyle(NoktaTheme.texto).lineLimit(2)
                HStack(spacing: 8) {
                    menuEstado
                    if let sub = [vm.trabajos.first?.servicio, vm.desde.map { "desde \($0)" }].compactMap({ $0 }).joined(separator: " · ").nilSiVacio {
                        Text(sub).font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoSuave).lineLimit(1)
                    }
                }
            }
        }
    }

    private var menuEstado: some View {
        Menu {
            ForEach(["activo", "pausado", "cancelado"], id: \.self) { e in
                Button(ESTADO_CLIENTE_LABEL[e] ?? e) {
                    Task { await vm.cambiarEstado(e); alCambiar() }
                }
            }
        } label: {
            HStack(spacing: 3) {
                PastillaEstado(estado: vm.estado)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(NoktaTheme.textoTenue)
            }
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("Cambiar estado del cliente")
    }

    // MARK: Resumen de cobro

    private enum Tramo { case pagado, sigue, retrasado, falta }

    private func tramos(_ t: NoktaTrabajo, activo: Bool) -> [Tramo] {
        if t.servicio == "Clases" {
            let ses = vm.sesiones(t)
            let prox = ses.first { $0.estado != "pagado" }?.id
            return ses.map { $0.estado == "pagado" ? .pagado : ($0.id == prox && activo ? .sigue : .falta) }
        }
        if t.grupoResuelto == "B" {
            let qs = vm.quincenas(t)
            let prox = qs.firstIndex { $0.rec.estado != "pagado" }
            return qs.enumerated().map { i, x in
                x.rec.estado == "pagado" ? .pagado : x.rec.estado == "retrasado" ? .retrasado : (i == prox && activo ? .sigue : .falta)
            }
        }
        return []
    }

    private var detalleTotal: String {
        var partes: [String] = []
        if vm.trabajos.count == 1, let t = vm.trabajos.first {
            if t.servicio == "Clases" {
                partes.append("de " + NoktaFormato.dinero(vm.sesiones(t).reduce(0) { $0 + ($1.monto ?? 0) }))
            } else if t.grupoResuelto != "B" {
                partes.append("de " + NoktaFormato.dinero(t.monto ?? 0))
            }
        } else if vm.trabajos.count > 1 {
            partes.append("en \(vm.trabajos.count) trabajos")
        }
        partes.append(vm.porCobrar > 0 ? "te debe " + NoktaFormato.dinero(vm.porCobrar) : "al día")
        return partes.joined(separator: " · ")
    }

    private var resumen: some View {
        let forma = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let activo = vm.estado == "activo"
        let t = vm.principal
        let trs = t.map { tramos($0, activo: activo) } ?? []
        let luz = vm.porCobrar > 0 ? NoktaTheme.aviso : colorEstado

        return VStack(alignment: .leading, spacing: 0) {
            Text("COBRADO").font(NoktaFont.poppins(10, .medium)).tracking(1.4).foregroundStyle(NoktaTheme.textoTenue)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                let v = crecer ? vm.cobrado : 0
                Text(NoktaFormato.dinero(v))
                    .font(NoktaFont.poppins(ancho < 600 ? 44 : 58, .light)).tracking(-2.6)
                    .foregroundStyle(NoktaTheme.texto)
                    .contentTransition(.numericText(value: v))
                Text(detalleTotal).font(NoktaFont.poppins(13))
                    .foregroundStyle(vm.porCobrar > 0 ? NoktaTheme.aviso.opacity(0.9) : NoktaTheme.textoTenue)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.top, 4)

            if !trs.isEmpty {
                HStack(spacing: trs.count > 12 ? 3 : 6) {
                    ForEach(Array(trs.enumerated()), id: \.offset) { i, tr in
                        let c: Color = switch tr {
                        case .pagado: NoktaTheme.exito
                        case .sigue: NoktaTheme.aviso
                        case .retrasado: NoktaTheme.error
                        case .falta: NoktaTheme.texto.opacity(0.1)
                        }
                        Capsule().fill(c).frame(height: 7)
                            .shadow(color: tr == .falta ? .clear : c.opacity(0.5), radius: 5)
                            .scaleEffect(x: crecer ? 1 : 0, anchor: .leading)
                            .animation(.spring(duration: 0.6, bounce: 0.1).delay(Double(i) * 0.06), value: crecer)
                    }
                }
                .padding(.top, 18)
            } else if let t, !vm.esContrato(t), (t.monto ?? 0) > 0 {
                let pct = min(1, IngresosCalculator.cobrado(t) / (t.monto ?? 1))
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(NoktaTheme.texto.opacity(0.08))
                        Capsule().fill(colorEstado).frame(width: g.size.width * (crecer ? pct : 0))
                            .shadow(color: colorEstado.opacity(0.5), radius: 6)
                    }
                }
                .frame(height: 7)
                .padding(.top, 18)
            }

            if let t { siguiente(t, activo: activo).padding(.top, 18) }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoktaTheme.superficie, in: forma)
        // Borde que se enciende arriba con el color de lo que importa ahora.
        .overlay(forma.strokeBorder(NoktaTheme.borde, lineWidth: 1))
        .overlay(
            forma.strokeBorder(
                RadialGradient(colors: [luz.opacity(0.9), .clear], center: .top, startRadius: 0, endRadius: crecer ? 320 : 0),
                lineWidth: 1.2)
        )
        .background(
            forma.fill(RadialGradient(colors: [luz.opacity(0.1), .clear], center: .top, startRadius: 0, endRadius: crecer ? 260 : 0))
        )
    }

    @ViewBuilder
    private func siguiente(_ t: NoktaTrabajo, activo: Bool) -> some View {
        if vm.esContrato(t) && !activo {
            linea("Contrato", vm.estado == "pausado" ? "en pausa" : "cancelado", color: colorEstado)
        } else if t.servicio == "Clases" {
            if let s = vm.sesiones(t).first(where: { $0.estado != "pagado" }) {
                VStack(alignment: .leading, spacing: 14) {
                    linea("Próxima clase", dia(s.fecha, "EEE d MMM") + " · " + NoktaFormato.dinero(s.monto ?? 0), color: NoktaTheme.aviso)
                    botonGrande("Marcar la clase del \(dia(s.fecha, "d MMM")) como pagada") {
                        Task { await vm.marcarSiguiente(t); alCambiar() }
                    }
                }
            } else {
                linea("Clases", "todas pagadas ✓", color: NoktaTheme.exito)
            }
        } else if t.grupoResuelto == "B" {
            if let x = vm.quincenas(t).first(where: { $0.rec.estado != "pagado" }) {
                VStack(alignment: .leading, spacing: 14) {
                    linea(x.rec.estado == "retrasado" ? "Quincena retrasada" : "Próxima quincena",
                          "\(x.q == 1 ? "1ª" : "2ª") de \(mes(x.periodo)) · " + NoktaFormato.dinero(x.rec.monto ?? 0),
                          color: x.rec.estado == "retrasado" ? NoktaTheme.error : NoktaTheme.aviso)
                    botonGrande("Registrar pago de esta quincena") { vm.trabajoIdMostrado = t.id }
                }
            } else {
                linea("Quincenas", "al día ✓", color: NoktaTheme.exito)
            }
        } else if t.estado != "pagado" && (t.saldo ?? 0) > 0 {
            VStack(alignment: .leading, spacing: 14) {
                linea("Falta cobrar", NoktaFormato.dinero(t.saldo ?? 0) + " · " + t.servicio, color: NoktaTheme.aviso)
                botonGrande("Marcar como pagado completo") { Task { await vm.marcarSiguiente(t); alCambiar() } }
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
            ZStack {
                if vm.marcando { ProgressView().controlSize(.small).tint(.white) }
                Text(titulo).opacity(vm.marcando ? 0 : 1)
            }
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
        .disabled(vm.marcando)
    }

    // MARK: Datos y trabajos

    private func tarjeta<C: View>(_ titulo: String, @ViewBuilder _ contenido: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(titulo).font(NoktaFont.poppins(10, .medium)).tracking(1.4).foregroundStyle(NoktaTheme.textoTenue)
            VStack(spacing: 0) { contenido() }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(NoktaTheme.superficie, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(NoktaTheme.borde, lineWidth: 1))
    }

    private func fila(_ t: String, _ v: String, primera: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(t).foregroundStyle(NoktaTheme.textoSuave)
            Spacer(minLength: 10)
            Text(v).foregroundStyle(NoktaTheme.texto).lineLimit(1).textSelection(.enabled)
        }
        .font(NoktaFont.poppins(12.5))
        .padding(.vertical, 9)
        .overlay(alignment: .top) { if !primera { Rectangle().fill(NoktaTheme.borde).frame(height: 1) } }
    }

    private var datos: some View {
        tarjeta("DATOS") {
            fila("Trabajos", "\(vm.trabajos.count)", primera: true)
            if let d = vm.desde { fila("Cliente desde", d) }
            if let wa = vm.cliente?.whatsapp, !wa.isEmpty { fila("WhatsApp", wa) }
            if let em = vm.cliente?.email, !em.isEmpty { fila("Correo", em) }
            if let c = vm.cliente?.codigo, !c.isEmpty { fila("Código de galería", c) }
            VStack(alignment: .leading, spacing: 6) {
                Text("Notas").font(NoktaFont.poppins(12.5)).foregroundStyle(NoktaTheme.textoSuave)
                TextField("", text: $vm.notas, prompt: Text("Escribe algo sobre este cliente…").foregroundStyle(NoktaTheme.textoTenue), axis: .vertical)
                    .textFieldStyle(.plain).font(NoktaFont.poppins(12.5)).foregroundStyle(NoktaTheme.texto)
                    .lineLimit(2...6)
                    .onSubmit { Task { await guardarNota() } }
                HStack {
                    Spacer()
                    Button(notaGuardada ? "Guardada ✓" : "Guardar nota") { Task { await guardarNota() } }
                        .buttonStyle(.plain).font(NoktaFont.poppins(11.5, .medium))
                        .foregroundStyle(notaGuardada ? NoktaTheme.exito : NoktaTheme.marca)
                }
            }
            .padding(.top, 10)
            .overlay(alignment: .top) { Rectangle().fill(NoktaTheme.borde).frame(height: 1) }
        }
    }

    private var listaTrabajos: some View {
        tarjeta("TRABAJOS") {
            if vm.trabajos.isEmpty {
                Text(vm.isLoading ? "Cargando…" : "Sin trabajos todavía").font(NoktaFont.poppins(12.5)).foregroundStyle(NoktaTheme.textoTenue)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 9)
            }
            ForEach(Array(vm.trabajos.enumerated()), id: \.element.id) { i, t in
                Button { vm.trabajoIdMostrado = t.id } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.servicio).font(NoktaFont.poppins(12.5, .medium)).foregroundStyle(NoktaTheme.texto).lineLimit(1)
                            Text(FechaUtil.fechaCorta(t.fechaInicio ?? t.fecha)).font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoTenue)
                        }
                        Spacer(minLength: 8)
                        Text(NoktaFormato.dinero(IngresosCalculator.cobrado(t))).font(NoktaFont.poppins(13, .light)).foregroundStyle(NoktaTheme.texto)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(NoktaTheme.textoTenue)
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(NoktaTheme.borde).frame(height: 1) } }
            }
        }
    }

    private func guardarNota() async {
        await vm.guardarNota()
        withAnimation { notaGuardada = true }
        try? await Task.sleep(for: .seconds(1.6))
        withAnimation { notaGuardada = false }
    }

    // MARK: Fechas

    private static let isoDia: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    private func dia(_ iso: String, _ formato: String) -> String {
        guard let d = Self.isoDia.date(from: String(iso.prefix(10))) else { return iso }
        let f = DateFormatter(); f.locale = Locale(identifier: "es_ES"); f.dateFormat = formato
        return f.string(from: d).replacingOccurrences(of: ".", with: "")
    }

    private func mes(_ periodo: String) -> String {
        guard let am = FechaUtil.anioMes(periodo) else { return periodo }
        return FechaUtil.mesesCompletos[am.mes - 1].lowercased()
    }
}

private extension String {
    var nilSiVacio: String? { isEmpty ? nil : self }
}

private struct ClienteSheetId: Identifiable { let id: String }
