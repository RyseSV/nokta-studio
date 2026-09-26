import SwiftUI

// MARK: - Catálogo de tipos y servicios (mismo orden y nombres que la web)

private struct TipoTrabajo: Identifiable {
    let id: String          // grupo A–E
    let nombre: String
    let detalle: String
    let icono: String
    let servicios: [String]
}

private let tiposTrabajo: [TipoTrabajo] = [
    TipoTrabajo(id: "A", nombre: "Evento o clase", detalle: "Foto, video, clases", icono: "camera", servicios: [
        "Fotografía de eventos", "Fotografía corporativa", "Fotografía de producto",
        "Fotografía gastronómica", "Retratos", "Cobertura audiovisual", "Foto + Video", "Clases",
    ]),
    TipoTrabajo(id: "B", nombre: "Mensual", detalle: "Redes, marketing", icono: "calendar.badge.clock", servicios: [
        "Marketing digital", "Gestión de redes", "Community management", "Paquete completo",
    ]),
    TipoTrabajo(id: "C", nombre: "Video", detalle: "Edición, reels", icono: "play.rectangle", servicios: [
        "Edición de video", "Motion graphics", "Reels sueltos",
    ]),
    TipoTrabajo(id: "D", nombre: "Branding", detalle: "Logo, identidad", icono: "seal", servicios: [
        "Identidad visual", "Branding",
    ]),
    TipoTrabajo(id: "E", nombre: "Web", detalle: "Diseño y desarrollo", icono: "globe", servicios: [
        "Diseño y desarrollo web",
    ]),
]

/// Lo mínimo de un cliente para el buscador (el `_id` va como `clienteId`,
/// igual que el combobox de la web). Los que salen de trabajos anteriores
/// no tienen `_id`: se guardan solo con el nombre, como hace la web.
struct ClienteBusqueda: Decodable, Identifiable, Hashable {
    let _id: String?
    let nombre: String
    let codigo: String?
    var id: String { _id ?? "t:" + nombre }
}

/// Decodifica una lista saltándose los elementos raros en vez de fallar toda.
private struct Tolerante<T: Decodable>: Decodable {
    let valor: T?
    init(from decoder: Decoder) throws { valor = try? T(from: decoder) }
}

// MARK: - ViewModel

@Observable
final class NuevoTrabajoViewModel {
    var cliente = ""
    var elegido: ClienteBusqueda?
    var clienteId: String? { elegido?._id }
    var clientes: [ClienteBusqueda] = []

    var tipo: String?
    var servicio = ""
    var notas = ""

    // Grupo A
    var fecha = Date()
    var horaInicio = ""
    var horaFin = ""
    var lugar = ""
    var montoA = ""
    var anticipoA = ""

    // Grupo B
    var empresaB = ""
    var pagoMensual = ""
    var fechaInicio = Date()
    var diaCobro = ""
    var estadoContrato = "activo"

    // Grupo C
    var cantPiezas = ""
    var formato = "vertical"
    var montoC = ""
    var anticipoC = ""
    var fechaEntregaC = Date()

    // Grupo D/E
    var empresaDE = ""
    var alcance = ""
    var montoDE = ""
    var anticipoDE = ""
    var fechaEntregaDE = Date()

    var isSaving = false
    var guardado = false
    var errorMessage: String?

    var grupo: String { tipo ?? ServicioGrupoMap.grupo(for: servicio) }

    private static let isoDay = DateFormatter.isoDay

    // MARK: Valores que alimentan la vista previa

    /// "$1,250.50", "1250" o "1,250" → 1250.5
    static func numero(_ s: String) -> Double? {
        let limpio = s.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(limpio)
    }

    var montoTexto: String {
        switch grupo {
        case "A": montoA
        case "B": pagoMensual
        case "C": montoC
        default: montoDE
        }
    }
    var anticipoTexto: String {
        switch grupo {
        case "A": anticipoA
        case "B": ""
        case "C": anticipoC
        default: anticipoDE
        }
    }
    var monto: Double { Self.numero(montoTexto) ?? 0 }
    var anticipo: Double { Self.numero(anticipoTexto) ?? 0 }
    var saldo: Double { max(0, monto - anticipo) }

    var esContrato: Bool { grupo == "B" || servicio == "Clases" }

    /// Fecha que tendrá el trabajo en la lista (misma regla que `guardar`).
    var fechaPrincipal: Date {
        switch grupo {
        case "A": fecha
        case "B": fechaInicio
        case "C": fechaEntregaC
        default: fechaEntregaDE
        }
    }

    var listo: Bool {
        !cliente.trimmingCharacters(in: .whitespaces).isEmpty && !servicio.isEmpty && monto > 0
    }

    func elegirTipo(_ id: String) {
        guard tipo != id else { return }
        tipo = id
        let lista = tiposTrabajo.first { $0.id == id }?.servicios ?? []
        servicio = lista.count == 1 ? lista[0] : ""
        errorMessage = nil
    }

    func elegirCliente(_ c: ClienteBusqueda) {
        cliente = c.nombre
        elegido = c
    }

    func reset() {
        cliente = ""; elegido = nil; tipo = nil; servicio = ""; notas = ""
        fecha = Date(); horaInicio = ""; horaFin = ""; lugar = ""; montoA = ""; anticipoA = ""
        empresaB = ""; pagoMensual = ""; fechaInicio = Date(); diaCobro = ""; estadoContrato = "activo"
        cantPiezas = ""; formato = "vertical"; montoC = ""; anticipoC = ""; fechaEntregaC = Date()
        empresaDE = ""; alcance = ""; montoDE = ""; anticipoDE = ""; fechaEntregaDE = Date()
        errorMessage = nil
    }

    // MARK: Red

    func cargarClientes() async {
        struct SoloCliente: Decodable { let cliente: String? }
        async let c: [Tolerante<ClienteBusqueda>]? = try? NoktaAPI.get("/api/clientes")
        async let t: [Tolerante<SoloCliente>]? = try? NoktaAPI.get("/api/trabajos")
        var lista = (await c ?? []).compactMap(\.valor).filter { !$0.nombre.isEmpty }
        // También los clientes de trabajos anteriores (TuBoleto, clases…),
        // que no siempre existen en la sección Clientes.
        var vistos = Set(lista.map { $0.nombre.lowercased() })
        for nombre in (await t ?? []).compactMap({ $0.valor?.cliente?.trimmingCharacters(in: .whitespaces) }) where !nombre.isEmpty {
            if vistos.insert(nombre.lowercased()).inserted {
                lista.append(ClienteBusqueda(_id: nil, nombre: nombre, codigo: nil))
            }
        }
        clientes = lista
    }

    /// Igual que "＋ Nuevo cliente" de la web: contacto sin galería.
    func crearCliente(nombre: String, whatsapp: String) async -> String? {
        struct Body: Encodable { let nombre: String; let whatsapp: String; let tipo: String; let dias: Int }
        struct Resp: Decodable { let ok: Bool?; let cliente: ClienteBusqueda?; let error: String? }
        do {
            let r: Resp = try await NoktaAPI.post("/api/clientes", body: Body(nombre: nombre, whatsapp: whatsapp, tipo: "contacto", dias: 0))
            guard let c = r.cliente else { return r.error ?? "No se pudo crear el cliente" }
            await cargarClientes()
            elegirCliente(c)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// "9" → "09:00", "930" → "09:30", "14:5" se deja como está.
    private static func hora(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        let digitos = t.filter(\.isNumber)
        if !t.contains(":"), (1...2).contains(digitos.count), let h = Int(digitos), h < 24 {
            return String(format: "%02d:00", h)
        }
        if !t.contains(":"), (3...4).contains(digitos.count), let v = Int(digitos), v / 100 < 24, v % 100 < 60 {
            return String(format: "%02d:%02d", v / 100, v % 100)
        }
        return t
    }

    func guardar() async -> Bool {
        errorMessage = nil
        guard !cliente.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Escribe o elige el cliente"; return false
        }
        guard tipo != nil else { errorMessage = "Elige el tipo de trabajo"; return false }
        guard !servicio.isEmpty else { errorMessage = "Elige el servicio"; return false }
        guard monto > 0 else {
            errorMessage = grupo == "B" ? "Completa el pago mensual" : "Completa el monto"; return false
        }
        if !anticipoTexto.isEmpty && Self.numero(anticipoTexto) == nil {
            errorMessage = "El anticipo no es un número válido"; return false
        }
        if anticipo > monto { errorMessage = "El anticipo no puede ser mayor que el monto"; return false }

        var fields: [String: AnyEncodableValue] = [
            "cliente": .string(cliente.trimmingCharacters(in: .whitespaces)),
            "servicio": .string(servicio),
            "grupo": .string(grupo),
            "grupoNombre": .string(ServicioGrupoMap.nombres[grupo] ?? grupo),
            "notas": .string(notas),
            "estado": .string("pendiente"),
        ]
        if let clienteId { fields["clienteId"] = .string(clienteId) }

        switch grupo {
        case "A":
            fields["fecha"] = .string(Self.isoDay.string(from: fecha))
            fields["horaInicio"] = .string(Self.hora(horaInicio))
            fields["horaFin"] = .string(Self.hora(horaFin))
            fields["lugar"] = .string(lugar)
            fields["monto"] = .double(monto)
            fields["anticipo"] = .double(anticipo)
            fields["saldo"] = .double(saldo)
        case "B":
            let inicioStr = Self.isoDay.string(from: fechaInicio)
            fields["empresa"] = .string(empresaB)
            fields["pagoMensual"] = .double(monto)
            fields["monto"] = .double(monto)
            fields["fechaInicio"] = .string(inicioStr)
            fields["fecha"] = .string(inicioStr)
            fields["estadoContrato"] = .string(estadoContrato)
            if !diaCobro.isEmpty {
                guard let dia = Int(diaCobro), (1...31).contains(dia) else {
                    errorMessage = "El día de cobro va del 1 al 31"; return false
                }
                fields["diaCobro"] = .int(dia)
            }
        case "C":
            let entregaStr = Self.isoDay.string(from: fechaEntregaC)
            fields["cantPiezas"] = .string(cantPiezas)
            fields["formato"] = .string(formato)
            fields["monto"] = .double(monto)
            fields["anticipo"] = .double(anticipo)
            fields["saldo"] = .double(saldo)
            fields["fechaEntrega"] = .string(entregaStr)
            fields["fecha"] = .string(entregaStr)
        default: // D, E
            let entregaStr = Self.isoDay.string(from: fechaEntregaDE)
            fields["empresa"] = .string(empresaDE)
            fields["alcance"] = .string(alcance)
            fields["monto"] = .double(monto)
            fields["anticipo"] = .double(anticipo)
            fields["saldo"] = .double(saldo)
            fields["fechaEntrega"] = .string(entregaStr)
            fields["fecha"] = .string(entregaStr)
        }

        isSaving = true
        defer { isSaving = false }
        do {
            struct Resp: Decodable { let ok: Bool? }
            let _: Resp = try await NoktaAPI.post("/api/trabajos", body: AnyEncodableDict(fields))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

private extension DateFormatter {
    static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        return f
    }()
}

// MARK: - Pantalla

struct NuevoTrabajoView: View {
    /// Después de guardar (la web te lleva a Trabajos; aquí igual).
    var alGuardar: (() -> Void)?

    @State private var vm = NuevoTrabajoViewModel()
    @State private var aparecio = false
    @State private var ancho: CGFloat = 1000
    @State private var creandoCliente = false
    @FocusState private var focoCliente: Bool
    @State private var zonaCliente: CGRect = .zero

    var body: some View {
        let ancha = ancho >= 820
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                NoktaEncabezado(titulo: "Nuevo trabajo", subtitulo: "Llena lo básico; el saldo se calcula solo.")
                    .noktaEntrada(aparecio, 0)

                let layout = ancha
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: 28))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: 28))
                layout {
                    formulario
                        .frame(maxWidth: .infinity, alignment: .leading)
                    vistaPrevia
                        .frame(width: ancha ? 300 : nil)
                        .frame(maxWidth: ancha ? 300 : .infinity)
                        .noktaEntrada(aparecio, 3)
                }
            }
            .padding(ancha ? 32 : 20)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .coordinateSpace(.named("nuevoTrabajo"))
        // Clic en cualquier parte fuera del buscador (y su lista) lo cierra.
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .named("nuevoTrabajo")).onEnded { toque in
                if focoCliente && !zonaCliente.contains(toque.location) { focoCliente = false }
            }
        )
        .background(NoktaTheme.fondo)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { ancho = $0 }
        .task { await vm.cargarClientes() }
        .onAppear { aparecio = true }
        .sheet(isPresented: $creandoCliente) {
            NuevoClienteRapido(nombreInicial: vm.cliente) { nombre, wa in
                await vm.crearCliente(nombre: nombre, whatsapp: wa)
            }
        }
    }

    // MARK: Formulario

    private var formulario: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Etiqueta("Cliente")
                BuscadorCliente(vm: vm, foco: $focoCliente, zona: $zonaCliente, crear: { creandoCliente = true })
            }
            .zIndex(10)
            .noktaEntrada(aparecio, 1)

            VStack(alignment: .leading, spacing: 10) {
                Etiqueta("Tipo de trabajo")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 10)], spacing: 10) {
                    ForEach(tiposTrabajo) { t in
                        TarjetaTipo(tipo: t, seleccionado: vm.tipo == t.id, hayEleccion: vm.tipo != nil) {
                            withAnimation(.spring(duration: 0.45, bounce: 0.25)) { vm.elegirTipo(t.id) }
                        }
                    }
                }
                if let t = tiposTrabajo.first(where: { $0.id == vm.tipo }), t.servicios.count > 1 {
                    ChipsServicio(servicios: t.servicios, seleccion: $vm.servicio)
                        .id(t.id)
                        .padding(.top, 4)
                }
            }
            .noktaEntrada(aparecio, 2)

            if vm.tipo != nil {
                camposDelGrupo
                    .id(vm.grupo)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity))

                Campo("Notas") {
                    TextField("", text: $vm.notas, prompt: Text("Detalles adicionales (opcional)").foregroundStyle(NoktaTheme.textoTenue), axis: .vertical)
                        .lineLimit(2...5)
                }
                .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.15), value: vm.tipo)
    }

    @ViewBuilder
    private var camposDelGrupo: some View {
        let columnas = [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)]
        switch vm.grupo {
        case "A":
            LazyVGrid(columns: columnas, alignment: .leading, spacing: 16) {
                Campo("Fecha") { selectorFecha($vm.fecha) }
                CampoTexto("Hora inicio", texto: $vm.horaInicio, ejemplo: "10:00")
                CampoTexto("Hora fin", texto: $vm.horaFin, ejemplo: "14:00")
            }
            CampoTexto("Lugar", texto: $vm.lugar, ejemplo: "Dirección o nombre del local")
            filaDinero(monto: $vm.montoA, anticipo: $vm.anticipoA, columnas: columnas)
        case "B":
            LazyVGrid(columns: columnas, alignment: .leading, spacing: 16) {
                CampoTexto("Empresa", texto: $vm.empresaB, ejemplo: "Empresa del cliente")
                CampoTexto("Pago mensual", texto: $vm.pagoMensual, ejemplo: "0", dinero: true)
                CampoTexto("Día de cobro", texto: $vm.diaCobro, ejemplo: "Ej: 5", numerico: true)
                Campo("Inicio del contrato") { selectorFecha($vm.fechaInicio) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Etiqueta("Estado del contrato")
                NoktaChips(opciones: [("activo", "Activo"), ("pausado", "Pausado"), ("cancelado", "Cancelado")],
                           seleccion: $vm.estadoContrato)
            }
        case "C":
            LazyVGrid(columns: columnas, alignment: .leading, spacing: 16) {
                CampoTexto("Piezas", texto: $vm.cantPiezas, ejemplo: "Ej: 5 reels")
                Campo("Entrega estimada") { selectorFecha($vm.fechaEntregaC) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Etiqueta("Formato")
                NoktaChips(opciones: [("vertical", "Vertical"), ("horizontal", "Horizontal"), ("ambos", "Ambos")],
                           seleccion: $vm.formato)
            }
            filaDinero(monto: $vm.montoC, anticipo: $vm.anticipoC, columnas: columnas)
        default:
            LazyVGrid(columns: columnas, alignment: .leading, spacing: 16) {
                CampoTexto("Empresa", texto: $vm.empresaDE, ejemplo: "Empresa del cliente")
                Campo("Entrega estimada") { selectorFecha($vm.fechaEntregaDE) }
            }
            Campo("Alcance del proyecto") {
                TextField("", text: $vm.alcance, prompt: Text("Describe qué incluye…").foregroundStyle(NoktaTheme.textoTenue), axis: .vertical)
                    .lineLimit(2...5)
            }
            filaDinero(monto: $vm.montoDE, anticipo: $vm.anticipoDE, columnas: columnas)
        }
    }

    private func filaDinero(monto: Binding<String>, anticipo: Binding<String>, columnas: [GridItem]) -> some View {
        LazyVGrid(columns: columnas, alignment: .leading, spacing: 16) {
            CampoTexto("Monto total", texto: monto, ejemplo: "0", dinero: true)
            CampoTexto("Anticipo", texto: anticipo, ejemplo: "0", dinero: true)
            VStack(alignment: .leading, spacing: 8) {
                Etiqueta("Falta cobrar")
                Text(NoktaFormato.dinero(vm.saldo))
                    .font(NoktaFont.poppins(13, .medium))
                    .foregroundStyle(vm.saldo > 0 ? NoktaTheme.aviso : NoktaTheme.textoTenue)
                    .contentTransition(.numericText(value: vm.saldo))
                    .animation(.spring(duration: 0.4), value: vm.saldo)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(NoktaTheme.borde, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    )
            }
        }
    }

    private func selectorFecha(_ fecha: Binding<Date>) -> some View {
        DatePicker("", selection: fecha, displayedComponents: .date)
            .labelsHidden()
            .datePickerStyle(.compact)
            .environment(\.locale, Locale(identifier: "es"))
    }

    // MARK: Vista previa

    private var vistaPrevia: some View {
        VStack(alignment: .leading, spacing: 14) {
            Etiqueta("Así se verá en Trabajos")
            TarjetaPrevia(vm: vm)

            VStack(spacing: 0) {
                if vm.grupo == "B" && vm.tipo != nil {
                    filaResumen("Pago mensual", NoktaFormato.dinero(vm.monto))
                    filaResumen("Día de cobro", vm.diaCobro.isEmpty ? "—" : "Día \(vm.diaCobro)")
                    filaResumen("Contrato", ESTADO_CLIENTE_LABEL[vm.estadoContrato] ?? vm.estadoContrato.capitalized)
                } else {
                    filaResumen("Total", NoktaFormato.dinero(vm.monto))
                    filaResumen("Anticipo", NoktaFormato.dinero(vm.anticipo))
                    filaResumen("Falta cobrar", NoktaFormato.dinero(vm.saldo), color: vm.saldo > 0 ? NoktaTheme.aviso : nil)
                }
            }

            if let error = vm.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(NoktaFont.poppins(12))
                    .foregroundStyle(NoktaTheme.error)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }

            BotonGuardar(listo: vm.listo, guardando: vm.isSaving, guardado: vm.guardado) {
                Task { await guardar() }
            }

            if vm.tipo != nil || !vm.cliente.isEmpty {
                Button("Limpiar formulario") {
                    withAnimation(.spring(duration: 0.4)) { vm.reset() }
                }
                .buttonStyle(.plain)
                .font(NoktaFont.poppins(12))
                .foregroundStyle(NoktaTheme.textoTenue)
                .frame(maxWidth: .infinity)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: vm.errorMessage)
    }

    private func filaResumen(_ titulo: String, _ valor: String, color: Color? = nil) -> some View {
        HStack {
            Text(titulo).foregroundStyle(NoktaTheme.textoSuave)
            Spacer()
            Text(valor)
                .font(NoktaFont.poppins(12, .medium))
                .foregroundStyle(color ?? NoktaTheme.texto)
                .contentTransition(.numericText())
        }
        .font(NoktaFont.poppins(12))
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(NoktaTheme.borde).frame(height: 1) }
        .animation(.spring(duration: 0.4), value: valor)
    }

    private func guardar() async {
        let ok = await vm.guardar()
        guard ok else { return }
        withAnimation(.spring(duration: 0.4)) { vm.guardado = true }
        try? await Task.sleep(for: .seconds(0.9))
        vm.reset()
        vm.guardado = false
        alGuardar?()
    }
}

// MARK: - Piezas

private struct Etiqueta: View {
    let texto: String
    init(_ texto: String) { self.texto = texto }
    var body: some View {
        Text(texto.uppercased())
            .font(NoktaFont.poppins(10, .medium))
            .tracking(1.4)
            .foregroundStyle(NoktaTheme.textoTenue)
    }
}

/// Caja con el mismo aspecto para cualquier control (fecha, texto largo…).
private struct Campo<Contenido: View>: View {
    let titulo: String
    var foco = false
    @ViewBuilder var contenido: () -> Contenido

    init(_ titulo: String, foco: Bool = false, @ViewBuilder contenido: @escaping () -> Contenido) {
        self.titulo = titulo; self.foco = foco; self.contenido = contenido
    }

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: 11, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            Etiqueta(titulo)
            contenido()
                .textFieldStyle(.plain)
                .font(NoktaFont.poppins(13))
                .foregroundStyle(NoktaTheme.texto)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .background(NoktaTheme.superficie, in: forma)
                .overlay(forma.strokeBorder(foco ? NoktaTheme.marca.opacity(0.65) : NoktaTheme.borde, lineWidth: 1))
                .shadow(color: NoktaTheme.marca.opacity(foco ? 0.18 : 0), radius: 8)
                .animation(.easeOut(duration: 0.18), value: foco)
        }
    }
}

private struct CampoTexto: View {
    let titulo: String
    @Binding var texto: String
    var ejemplo: String
    var dinero = false
    var numerico = false
    @FocusState private var foco: Bool

    init(_ titulo: String, texto: Binding<String>, ejemplo: String, dinero: Bool = false, numerico: Bool = false) {
        self.titulo = titulo; self._texto = texto; self.ejemplo = ejemplo; self.dinero = dinero; self.numerico = numerico
    }

    var body: some View {
        Campo(titulo, foco: foco) {
            HStack(spacing: 4) {
                if dinero {
                    Text("$").foregroundStyle(texto.isEmpty ? NoktaTheme.textoTenue : NoktaTheme.textoSuave)
                }
                TextField("", text: $texto, prompt: Text(ejemplo).foregroundStyle(NoktaTheme.textoTenue))
                    .focused($foco)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(dinero ? .decimalPad : numerico ? .numberPad : .default)
                    #endif
            }
        }
    }
}

/// Buscador de clientes reales + "＋ Nuevo cliente", como el combobox de la web.
/// La lista se cierra al hacer clic fuera (lo maneja la pantalla con `zona`)
/// o con Esc.
private struct BuscadorCliente: View {
    @Bindable var vm: NuevoTrabajoViewModel
    var foco: FocusState<Bool>.Binding
    @Binding var zona: CGRect
    var crear: () -> Void
    @State private var marcoCampo: CGRect = .zero
    @State private var marcoLista: CGRect = .zero

    private var coincidencias: [ClienteBusqueda] {
        let q = vm.cliente.trimmingCharacters(in: .whitespaces)
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let lista = q.isEmpty ? vm.clientes : vm.clientes.filter { $0.nombre.range(of: q, options: opts) != nil }
        return Array(lista.prefix(6))
    }

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: 11, style: .continuous)
        let enfocado = foco.wrappedValue
        let abierto = enfocado && vm.elegido == nil
        HStack(spacing: 10) {
            if vm.elegido != nil {
                NoktaAvatar(nombre: vm.cliente, tamano: 26)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .light))
                    .foregroundStyle(NoktaTheme.textoTenue)
            }
            TextField("", text: $vm.cliente, prompt: Text("Busca o crea un cliente…").foregroundStyle(NoktaTheme.textoTenue))
                .textFieldStyle(.plain)
                .font(NoktaFont.poppins(13, vm.elegido != nil ? .medium : .regular))
                .foregroundStyle(NoktaTheme.texto)
                .focused(foco)
                .autocorrectionDisabled()
                .onChange(of: vm.cliente) { _, nuevo in
                    // Si edita el nombre de un cliente ya elegido, deja de estar ligado.
                    if let e = vm.elegido, e.nombre != nuevo { vm.elegido = nil }
                }
                .onSubmit {
                    if let primero = coincidencias.first, vm.elegido == nil, !vm.cliente.isEmpty {
                        withAnimation(.spring(duration: 0.3)) { vm.elegirCliente(primero) }
                    }
                    foco.wrappedValue = false
                }
                .onKeyPress(.escape) { foco.wrappedValue = false; return .handled }
            if let e = vm.elegido {
                if let codigo = e.codigo {
                    Text(codigo).font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoTenue)
                }
                Button {
                    withAnimation(.spring(duration: 0.3)) { vm.cliente = ""; vm.elegido = nil }
                    foco.wrappedValue = true
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(NoktaTheme.textoTenue)
                }
                .buttonStyle(.plain)
                .help("Cambiar cliente")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(NoktaTheme.superficie, in: forma)
        .overlay(forma.strokeBorder(enfocado ? NoktaTheme.marca.opacity(0.65) : NoktaTheme.borde, lineWidth: 1))
        .shadow(color: NoktaTheme.marca.opacity(enfocado ? 0.18 : 0), radius: 8)
        .animation(.easeOut(duration: 0.18), value: enfocado)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("nuevoTrabajo")) } action: { marcoCampo = $0; actualizarZona() }
        .overlay(alignment: .topLeading) {
            if abierto {
                lista
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("nuevoTrabajo")) } action: { marcoLista = $0; actualizarZona() }
                    .onDisappear { marcoLista = .zero; actualizarZona() }
                    .offset(y: 50)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.1), value: abierto)
    }

    private func actualizarZona() {
        zona = marcoLista == .zero ? marcoCampo : marcoCampo.union(marcoLista.offsetBy(dx: 0, dy: 50))
    }

    private var lista: some View {
        VStack(alignment: .leading, spacing: 2) {
            if coincidencias.isEmpty && !vm.cliente.isEmpty {
                Text("No hay clientes con ese nombre")
                    .font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoTenue)
                    .padding(.horizontal, 10).padding(.vertical, 6)
            }
            ForEach(coincidencias) { c in
                Button {
                    withAnimation(.spring(duration: 0.3)) { vm.elegirCliente(c) }
                    foco.wrappedValue = false
                } label: {
                    HStack(spacing: 10) {
                        NoktaAvatar(nombre: c.nombre, tamano: 24)
                        Text(c.nombre).font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.texto).lineLimit(1)
                        Spacer()
                        Text(c.codigo ?? "De tus trabajos").font(NoktaFont.poppins(10)).foregroundStyle(NoktaTheme.textoTenue)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .noktaHover(radio: 8)
            }
            Button {
                foco.wrappedValue = false
                crear()
            } label: {
                Label(vm.cliente.isEmpty ? "Nuevo cliente" : "Nuevo cliente “\(vm.cliente)”", systemImage: "plus")
                    .font(NoktaFont.poppins(12, .medium))
                    .foregroundStyle(NoktaTheme.marca)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .noktaHover(radio: 8)
        }
        .padding(6)
        .frame(width: 380, alignment: .leading)
        .background(NoktaTheme.superficie2, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(NoktaTheme.borde))
        .shadow(color: .black.opacity(0.3), radius: 22, y: 12)
    }
}

private struct TarjetaTipo: View {
    let tipo: TipoTrabajo
    let seleccionado: Bool
    let hayEleccion: Bool
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Button(action: accion) {
            VStack(alignment: .leading, spacing: 3) {
                Image(systemName: tipo.icono)
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(seleccionado ? NoktaTheme.marca : NoktaTheme.textoSuave)
                    .symbolEffect(.bounce, value: seleccionado)
                    .frame(height: 22)
                    .padding(.bottom, 8)
                Text(tipo.nombre).font(NoktaFont.poppins(12, .medium)).foregroundStyle(NoktaTheme.texto).lineLimit(1)
                Text(tipo.detalle).font(NoktaFont.poppins(10)).foregroundStyle(NoktaTheme.textoTenue).lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    forma.fill(NoktaTheme.superficie)
                    if seleccionado {
                        forma.fill(LinearGradient(colors: [NoktaTheme.marca.opacity(0.16), NoktaTheme.marca.opacity(0.02)],
                                                  startPoint: .top, endPoint: .bottom))
                    }
                }
            }
            .overlay(forma.strokeBorder(seleccionado ? NoktaTheme.marca.opacity(0.75) : (encima ? NoktaTheme.texto.opacity(0.18) : NoktaTheme.borde),
                                        lineWidth: seleccionado ? 1.5 : 1))
            .shadow(color: NoktaTheme.marca.opacity(seleccionado ? 0.3 : 0), radius: 14, y: 8)
            .offset(y: seleccionado ? -3 : (encima ? -2 : 0))
            .opacity(hayEleccion && !seleccionado && !encima ? 0.55 : 1)
            .contentShape(forma)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(duration: 0.3, bounce: 0.3)) { encima = h } }
        .animation(.spring(duration: 0.4, bounce: 0.25), value: seleccionado)
    }
}

private struct ChipsServicio: View {
    let servicios: [String]
    @Binding var seleccion: String
    @State private var visible = false

    var body: some View {
        Flujo(espacio: 7) {
            ForEach(Array(servicios.enumerated()), id: \.element) { i, s in
                let activo = s == seleccion
                Button {
                    withAnimation(.spring(duration: 0.3, bounce: 0.2)) { seleccion = s }
                } label: {
                    Text(s)
                        .font(NoktaFont.poppins(11, activo ? .medium : .regular))
                        .foregroundStyle(activo ? Color.white : NoktaTheme.textoSuave)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(activo ? AnyShapeStyle(NoktaTheme.marca) : AnyShapeStyle(NoktaTheme.superficie), in: Capsule())
                        .overlay(Capsule().strokeBorder(activo ? Color.clear : NoktaTheme.borde))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .noktaEntrada(visible, i)
            }
        }
        .onAppear { visible = true }
    }
}

/// Acomoda los chips en renglones, como texto.
private struct Flujo: Layout {
    var espacio: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ancho = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, alto: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x > 0 && x + t.width > ancho { x = 0; y += alto + espacio; alto = 0 }
            x += t.width + espacio
            maxX = max(maxX, x - espacio)
            alto = max(alto, t.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + alto)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, alto: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + t.width > bounds.maxX { x = bounds.minX; y += alto + espacio; alto = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(t))
            x += t.width + espacio
            alto = max(alto, t.height)
        }
    }
}

/// Réplica de la tarjeta de la lista de Trabajos, alimentada por el formulario.
private struct TarjetaPrevia: View {
    let vm: NuevoTrabajoViewModel
    @Environment(\.colorScheme) private var scheme

    private var icono: String {
        let s = vm.servicio.lowercased()
        if s.isEmpty { return tiposTrabajo.first { $0.id == vm.tipo }?.icono ?? "briefcase" }
        if s.contains("video") || s.contains("edición") { return "video" }
        if s.contains("redes") || s.contains("social") || s.contains("community") { return "iphone" }
        if s.contains("foto") || s.contains("retrato") { return "camera" }
        if s.contains("evento") { return "party.popper" }
        if s.contains("brand") || s.contains("identidad") || s.contains("diseño") { return "sparkles" }
        if s.contains("clase") { return "graduationcap" }
        return "briefcase"
    }

    private var estado: (texto: String, color: Color) {
        if vm.esContrato {
            let er = vm.grupo == "B" ? vm.estadoContrato : "activo"
            let color = er == "activo" ? NoktaTheme.exito : er == "pausado" ? NoktaTheme.aviso : NoktaTheme.error
            return (ESTADO_CLIENTE_LABEL[er] ?? er.capitalized, color)
        }
        return ("Pendiente", NoktaTheme.aviso)
    }

    private var cobrado: Double { vm.monto > 0 ? min(1, vm.anticipo / vm.monto) : 0 }

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: 20, style: .continuous)
        let c = estado.color
        let nombre = vm.cliente.trimmingCharacters(in: .whitespaces)
        let servicio = vm.servicio.isEmpty ? "Servicio" : vm.servicio
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: icono)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(NoktaTheme.textoSuave)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 38, height: 38)
                    .background(NoktaTheme.superficie2, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Spacer()
                NoktaEstado(texto: estado.texto, color: c, tamano: 11)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(c.opacity(0.1), in: Capsule())
            }
            Text(nombre.isEmpty ? "Cliente" : nombre)
                .font(NoktaFont.poppins(15, .medium))
                .foregroundStyle(nombre.isEmpty ? NoktaTheme.textoTenue : NoktaTheme.texto)
                .lineLimit(1).padding(.top, 16)
            Text(vm.esContrato ? "\(servicio) · Mensual" : "\(servicio) · \(fechaCorta(vm.fechaPrincipal))")
                .font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoTenue).lineLimit(1).padding(.top, 2)
            Text(NoktaFormato.dinero(vm.monto))
                .font(NoktaFont.poppins(30, .light)).tracking(-1.2)
                .foregroundStyle(vm.monto > 0 ? NoktaTheme.texto : NoktaTheme.textoTenue)
                .contentTransition(.numericText(value: vm.monto))
                .padding(.top, 14)
            if vm.esContrato {
                Text("por mes").font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoTenue)
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(NoktaTheme.texto.opacity(0.07))
                        Capsule()
                            .fill(LinearGradient(colors: [c, c.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * cobrado)
                    }
                }
                .frame(height: 5)
                .padding(.top, 12)
                HStack {
                    Text("Cobrado \(Int((cobrado * 100).rounded()))%")
                    Spacer()
                    Text("Saldo " + NoktaFormato.dinero(vm.saldo))
                }
                .font(NoktaFont.poppins(10)).foregroundStyle(NoktaTheme.textoTenue)
                .contentTransition(.numericText())
                .padding(.top, 6)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .bottomTrailing) {
                forma.fill(NoktaTheme.superficie)
                Circle()
                    .fill(c.opacity(scheme == .dark ? 0.14 : 0.09))
                    .frame(width: 200, height: 200)
                    .blur(radius: 60)
                    .offset(x: 70, y: 90)
            }
            .clipShape(forma)
        }
        // Se enciende con el color del estado cuando ya se puede guardar.
        .overlay(forma.strokeBorder(vm.listo ? c.opacity(0.55) : NoktaTheme.borde, lineWidth: vm.listo ? 1.5 : 1))
        .shadow(color: c.opacity(vm.listo ? 0.2 : 0), radius: 18, y: 8)
        .animation(.spring(duration: 0.5), value: vm.listo)
        .animation(.spring(duration: 0.7, bounce: 0.1), value: cobrado)
        .animation(.spring(duration: 0.4), value: vm.monto)
        .animation(.easeOut(duration: 0.2), value: vm.servicio)
    }

    private func fechaCorta(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.dateFormat = "EEE d MMM"
        return f.string(from: d).replacingOccurrences(of: ".", with: "").capitalized
    }
}

private struct BotonGuardar: View {
    let listo: Bool
    let guardando: Bool
    let guardado: Bool
    let accion: () -> Void
    @State private var pulso = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: 13, style: .continuous)
        Button(action: accion) {
            ZStack {
                if guardando {
                    ProgressView().controlSize(.small).tint(.white)
                } else if guardado {
                    Label("Trabajo guardado", systemImage: "checkmark").transition(.scale.combined(with: .opacity))
                } else {
                    Text("Guardar trabajo")
                }
            }
            .font(NoktaFont.poppins(13, .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                LinearGradient(colors: guardado ? [NoktaTheme.exito, NoktaTheme.exito.opacity(0.8)] : [Color(red: 0.855, green: 0.478, blue: 0.282), Color(red: 0.72, green: 0.32, blue: 0.157)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: forma
            )
            .shadow(color: (guardado ? NoktaTheme.exito : NoktaTheme.marca).opacity(listo ? (pulso ? 0.7 : 0.35) : 0), radius: pulso ? 18 : 10, y: 8)
            .saturation(listo || guardado ? 1 : 0.35)
            .opacity(listo || guardado ? 1 : 0.5)
            .contentShape(forma)
        }
        .buttonStyle(.plain)
        .disabled(guardando || guardado)
        .keyboardShortcut(.return, modifiers: .command)
        .help("Guardar (⌘↩)")
        .animation(.spring(duration: 0.4), value: listo)
        .animation(.spring(duration: 0.4), value: guardado)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulso = true }
        }
    }
}

/// Mini formulario para crear un cliente sin salir de Nuevo trabajo.
private struct NuevoClienteRapido: View {
    let nombreInicial: String
    let crear: (String, String) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var nombre = ""
    @State private var whatsapp = ""
    @State private var creando = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Nuevo cliente").font(NoktaFont.poppins(20, .light)).foregroundStyle(NoktaTheme.texto)
                Text("Se crea y queda elegido para este trabajo.")
                    .font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoSuave)
            }
            CampoTexto("Nombre", texto: $nombre, ejemplo: "Nombre del cliente")
            CampoTexto("WhatsApp", texto: $whatsapp, ejemplo: "7000-0000", numerico: true)
            if let error {
                Text(error).font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.error)
            }
            HStack {
                Button("Cancelar") { dismiss() }
                    .buttonStyle(NoktaBotonSecundario())
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    Task {
                        creando = true
                        error = await crear(nombre.trimmingCharacters(in: .whitespaces), whatsapp)
                        creando = false
                        if error == nil { dismiss() }
                    }
                } label: {
                    if creando { ProgressView().controlSize(.small) } else { Text("Crear y elegir") }
                }
                .buttonStyle(NoktaBotonPrimario())
                .keyboardShortcut(.defaultAction)
                .disabled(creando || nombre.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(26)
        .frame(minWidth: 360)
        .background(NoktaTheme.fondo)
        .onAppear { nombre = nombreInicial }
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }
}
