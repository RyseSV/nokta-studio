import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

private let noktaBaseURL = "https://nokta-studio.onrender.com"
private let tipoLabels: [String: String] = [
    "boda": "Boda", "xvanios": "XV Años", "corporativo": "Corporativo",
    "deportivo": "Deportivo", "graduacion": "Graduación", "otro": "Evento",
]

func copyToClipboard(_ text: String) {
    #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #else
    UIPasteboard.general.string = text
    #endif
}

/// En qué punto está una galería (calculado, no solo el `estado` guardado:
/// el servidor marca "expirado" solo cuando alguien abre un link vencido).
enum SituacionGaleria {
    case activa, porVencer, descargada, vencida

    var texto: String {
        switch self {
        case .activa: "Activa"
        case .porVencer: "Vence pronto"
        case .descargada: "Descargada"
        case .vencida: "Vencida"
        }
    }
    var color: Color {
        switch self {
        case .activa: NoktaTheme.exito
        case .porVencer: NoktaTheme.aviso
        case .descargada: NoktaPalette.blue
        case .vencida: NoktaTheme.error
        }
    }
    var icono: String {
        switch self {
        case .activa: "eye"
        case .porVencer: "hourglass"
        case .descargada: "arrow.down.circle"
        case .vencida: "clock.badge.xmark"
        }
    }
}

/// Algo que pasó con una galería, para "Actividad reciente".
struct EventoGaleria: Identifiable {
    let id = UUID()
    let fecha: Date
    let nombre: String
    let texto: String
    let color: Color
}

@Observable
final class GaleriasViewModel {
    var clientes: [NoktaCliente] = []
    var filtro = "todas"
    var busqueda = ""
    var isLoading = true

    /// Días o menos para considerar que una galería "vence pronto".
    static let diasAviso = 7

    var galClientes: [NoktaCliente] { clientes.filter { $0.tipo != "contacto" } }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        if let c: [NoktaCliente] = try? await NoktaAPI.get("/api/clientes") { clientes = c }
    }

    private static let iso: ISO8601DateFormatter = ISO8601DateFormatter()
    private static let isoFraccion: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    static func fecha(_ s: String?) -> Date? {
        guard let s else { return nil }
        return isoFraccion.date(from: s) ?? iso.date(from: s)
    }

    func diasRestantes(_ c: NoktaCliente) -> Int? {
        guard let d = Self.fecha(c.expira) else { return nil }
        return max(0, Int(ceil(d.timeIntervalSinceNow / 86400)))
    }
    func vencida(_ c: NoktaCliente) -> Bool {
        if let d = Self.fecha(c.expira) { return d < Date() }
        return c.estado == "expirado"
    }
    func descargo(_ c: NoktaCliente) -> Bool { !(c.descargas ?? []).isEmpty }

    func situacion(_ c: NoktaCliente) -> SituacionGaleria {
        if vencida(c) { return .vencida }
        if descargo(c) { return .descargada }
        if let d = diasRestantes(c), d <= Self.diasAviso { return .porVencer }
        return .activa
    }

    /// Por vencer y sin descargar: lo que hay que atender primero.
    var urgentes: [NoktaCliente] {
        galClientes.filter { situacion($0) == .porVencer }
            .sorted { (diasRestantes($0) ?? 0) < (diasRestantes($1) ?? 0) }
    }

    var demas: [NoktaCliente] {
        let q = busqueda.trimmingCharacters(in: .whitespaces)
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let urg = Set(urgentes.map(\.codigo))
        return galClientes.filter { c in
            let coincide = q.isEmpty || c.nombre.range(of: q, options: opts) != nil || c.codigo.range(of: q, options: opts) != nil
            guard coincide else { return false }
            switch filtro {
            case "activas": return situacion(c) == .activa || situacion(c) == .porVencer
            case "descargadas": return situacion(c) == .descargada
            case "vencidas": return situacion(c) == .vencida
            case "reactivadas": return !(c.reactivaciones ?? []).isEmpty
            default: return !urg.contains(c.codigo) || !q.isEmpty
            }
        }
    }

    var activas: Int { galClientes.filter { !vencida($0) }.count }
    var descargadas: Int { galClientes.filter(descargo).count }
    var visitas: Int { galClientes.reduce(0) { $0 + ($1.visitas ?? []).count } }
    var vencidas: Int { galClientes.filter(vencida).count }

    /// Lo último que pasó: galerías creadas, visitas, descargas, reactivaciones y vencimientos.
    var actividad: [EventoGaleria] {
        var ev: [EventoGaleria] = []
        for c in galClientes {
            if let d = Self.fecha(c.creado) { ev.append(.init(fecha: d, nombre: c.nombre, texto: "galería creada", color: NoktaTheme.marca)) }
            if let v = (c.visitas ?? []).compactMap({ Self.fecha($0.fecha) }).max() {
                let n = (c.visitas ?? []).count
                ev.append(.init(fecha: v, nombre: c.nombre, texto: n == 1 ? "abrió su galería" : "abrió su galería (\(n) veces)", color: NoktaTheme.exito))
            }
            for x in c.descargas ?? [] {
                if let d = Self.fecha(x.fecha) {
                    ev.append(.init(fecha: d, nombre: c.nombre, texto: x.tipo == "todo" || x.tipo == nil ? "descargó todas las fotos" : "descargó fotos", color: NoktaPalette.blue))
                }
            }
            for r in c.reactivaciones ?? [] {
                if let d = Self.fecha(r.fecha) { ev.append(.init(fecha: d, nombre: c.nombre, texto: "reactivada por \(r.dias) días", color: NoktaTheme.aviso)) }
            }
            if vencida(c), !descargo(c), let d = Self.fecha(c.expira) {
                ev.append(.init(fecha: d, nombre: c.nombre, texto: "venció sin descargar", color: NoktaTheme.error))
            }
        }
        return Array(ev.sorted { $0.fecha > $1.fecha }.prefix(8))
    }

    func reactivar(_ codigo: String, dias: Int) async {
        struct Body: Encodable { let dias: Int }
        struct Resp: Decodable { let ok: Bool?; let expira: String? }
        let _: Resp? = try? await NoktaAPI.put("/api/clientes/\(codigo)/reactivar", body: Body(dias: dias))
        await load()
    }

    func eliminar(_ codigo: String) async {
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp? = try? await NoktaAPI.delete("/api/clientes/\(codigo)")
        await load()
    }

    func crear(nombre: String, tipo: String, dias: Int, whatsapp: String) async -> String? {
        struct Body: Encodable { let nombre: String; let tipo: String; let dias: Int; let whatsapp: String }
        struct Resp: Decodable { let ok: Bool?; let cliente: NoktaCliente?; let link: String? }
        let resp: Resp? = try? await NoktaAPI.post("/api/clientes", body: Body(nombre: nombre, tipo: tipo, dias: dias, whatsapp: whatsapp))
        await load()
        return resp?.cliente?.codigo
    }

    // MARK: Links y mensajes

    static func link(_ c: NoktaCliente) -> String { "\(noktaBaseURL)/galeria?codigo=\(c.codigo)" }

    /// Texto listo para WhatsApp según lo que le queremos decir al cliente.
    func mensaje(_ c: NoktaCliente, _ tipo: TipoMensaje) -> String {
        let dias = diasRestantes(c)
        let evento = tipoLabels[c.tipo ?? ""] ?? c.tipo ?? ""
        switch tipo {
        case .vencePronto:
            let cuando = dias == nil ? "pronto" : dias == 0 ? "hoy" : dias == 1 ? "mañana" : "en \(dias!) días"
            return "Hola \(c.nombre) 👋 Te recuerdo que tu galería de \(evento) vence \(cuando). Descargá tus fotos antes de que se cierre el acceso:\n\(Self.link(c))\n\nTu código de acceso es: \(c.codigo)"
        case .masDias:
            let hasta = Self.fecha(c.expira).map { "hasta el \(Self.diaLargo($0))" } ?? "sin límite de tiempo"
            return "Hola \(c.nombre) 👋 Te di más días para tu galería de \(evento): ahora podés entrar \(hasta). Aquí está el link:\n\(Self.link(c))\n\nTu código de acceso es: \(c.codigo)"
        case .listas:
            let limite = dias != nil ? "El acceso estará disponible por \(dias!) días." : "El acceso no tiene límite de tiempo."
            return "Hola \(c.nombre), tus fotos de \(evento) ya están listas 📸\nPodés verlas y descargarlas en este link:\n\(Self.link(c))\n\nTu código de acceso es: \(c.codigo)\n\(limite)"
        }
    }

    static func whatsappURL(_ c: NoktaCliente, texto: String) -> URL? {
        guard let wa = c.whatsapp?.filter(\.isNumber), !wa.isEmpty else { return nil }
        var comps = URLComponents(string: "https://wa.me/\(wa.count == 8 ? "503" + wa : wa)")
        comps?.queryItems = [URLQueryItem(name: "text", value: texto)]
        return comps?.url
    }

    static func diaLargo(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "es"); f.dateFormat = "EEEE d 'de' MMMM"
        return f.string(from: d)
    }
    static func diaCorto(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "es"); f.dateFormat = "d MMM"
        return f.string(from: d).replacingOccurrences(of: ".", with: "")
    }
}

/// Lo que dice el mensaje de WhatsApp.
enum TipoMensaje: String, CaseIterable, Hashable {
    case vencePronto, listas, masDias
    var texto: String {
        switch self {
        case .vencePronto: "Vence pronto"
        case .listas: "Ya están listas"
        case .masDias: "Le di más días"
        }
    }
}

/// Qué panel lateral está abierto.
enum PanelGaleria: Equatable {
    case nueva
    case dias(String)
    case recordatorio(String, TipoMensaje)
}

private let galFiltros: [(valor: String, texto: String)] = [
    ("todas", "Todas"), ("activas", "Activas"), ("descargadas", "Descargadas"), ("vencidas", "Vencidas"), ("reactivadas", "Reactivadas"),
]

/// Galerías ("lo urgente primero", 2026-10): la que vence pronto sin
/// descargar sale en grande con borde de luz; a la derecha los números y la
/// actividad reciente.
struct GaleriasView: View {
    @State private var vm = GaleriasViewModel()
    @State private var panel: PanelGaleria?
    @State private var eliminarConfirm: NoktaCliente?
    @State private var copiado: String?
    @State private var aparecio = false
    @State private var ancho: CGFloat = 1000
    @Environment(\.openURL) private var openURL

    private var ancha: Bool { ancho >= 900 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                NoktaEncabezado(titulo: "Galerías", subtitulo: subtitulo) {
                    NoktaBuscador(texto: $vm.busqueda, placeholder: "Buscar cliente o código…")
                        .frame(maxWidth: ancho < 600 ? .infinity : 240)
                    Button { abrir(.nueva) } label: { Label("Nueva galería", systemImage: "plus") }
                        .buttonStyle(NoktaBotonPrimario())
                }
                .noktaEntrada(aparecio, 0)

                let fila = ancha
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: 18))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
                fila {
                    columnaPrincipal.frame(maxWidth: .infinity)
                    columnaLado.frame(width: ancha ? 300 : nil).frame(maxWidth: ancha ? 300 : .infinity)
                }
            }
            .padding(.horizontal, ancho < 600 ? 20 : 40)
            .padding(.vertical, ancho < 600 ? 16 : 32)
            .frame(maxWidth: 1240, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(NoktaTheme.fondo)
        .overlay(alignment: .bottom) {
            if let copiado {
                Text(copiado)
                    .font(NoktaFont.poppins(12, .medium)).foregroundStyle(NoktaTheme.fondo)
                    .padding(.horizontal, 14).frame(height: 34)
                    .background(NoktaTheme.texto, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { ancho = $0 }
        .task {
            await vm.load()
            withAnimation(.spring(duration: 0.7, bounce: 0.1)) { aparecio = true }
        }
        .refreshable { await vm.load() }
        .overlay { panelLateral }
        .alert("¿Eliminar esta galería?", isPresented: Binding(get: { eliminarConfirm != nil }, set: { if !$0 { eliminarConfirm = nil } })) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar", role: .destructive) {
                if let c = eliminarConfirm { Task { await vm.eliminar(c.codigo) } }
            }
        } message: {
            Text("El código dejará de funcionar y el cliente ya no podrá entrar.")
        }
    }

    private var subtitulo: String {
        if vm.isLoading && vm.galClientes.isEmpty { return "Cargando tus galerías…" }
        let u = vm.urgentes.count
        if u > 0 { return "\(u) por vencer sin descargar" }
        let n = vm.galClientes.count
        return n == 0 ? "Crea la primera galería para un cliente" : "\(n) galería\(n == 1 ? "" : "s") · todo al día"
    }

    private func etiqueta(_ t: String, _ detalle: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(t).font(NoktaFont.poppins(10, .medium)).tracking(1.4).foregroundStyle(NoktaTheme.textoTenue)
            Spacer()
            if let detalle { Text(detalle).font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoTenue) }
        }
    }

    // MARK: Columna principal

    private var columnaPrincipal: some View {
        VStack(alignment: .leading, spacing: 14) {
            if vm.isLoading && vm.galClientes.isEmpty {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(NoktaTheme.superficie)
                        .frame(height: 90).modifier(NoktaBrillo())
                }
            } else {
                if !vm.urgentes.isEmpty && vm.busqueda.isEmpty {
                    etiqueta("POR VENCER", "Sin descargar todavía").noktaEntrada(aparecio, 1)
                    ForEach(Array(vm.urgentes.enumerated()), id: \.element.codigo) { i, c in
                        tarjetaUrgente(c).noktaEntrada(aparecio, 2 + i)
                    }
                }
                HStack {
                    etiqueta(vm.urgentes.isEmpty || !vm.busqueda.isEmpty ? "TUS GALERÍAS" : "LAS DEMÁS", "\(vm.demas.count)")
                }
                .padding(.top, vm.urgentes.isEmpty ? 0 : 8)
                .noktaEntrada(aparecio, 3)
                NoktaChips(opciones: galFiltros, seleccion: $vm.filtro).noktaEntrada(aparecio, 3)
                if vm.demas.isEmpty {
                    NoktaVacio(icono: "photo.on.rectangle", titulo: vm.galClientes.isEmpty ? "Aún no hay galerías" : "Nada por aquí",
                               detalle: vm.galClientes.isEmpty ? "Crea una galería y mándale el link a tu cliente." : "Prueba con otro filtro o búsqueda.")
                        .noktaCard()
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(vm.demas.enumerated()), id: \.element.codigo) { i, c in
                            fila(c).noktaEntrada(aparecio, 4 + i)
                        }
                    }
                    .animation(.snappy(duration: 0.35), value: vm.demas.map(\.codigo))
                }
            }
        }
    }

    private func tarjetaUrgente(_ c: NoktaCliente) -> some View {
        let dias = vm.diasRestantes(c) ?? 0
        let total = Double(max(c.reactivaciones?.last?.dias ?? 30, dias, 1))
        let visitas = (c.visitas ?? []).count
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                pastilla(.porVencer)
                Spacer()
                Text(c.codigo).font(.system(size: 12, design: .monospaced)).foregroundStyle(NoktaTheme.textoSuave)
                    .textSelection(.enabled)
            }
            Text(c.nombre).font(NoktaFont.poppins(24, .light)).tracking(-0.8).foregroundStyle(NoktaTheme.texto)
                .lineLimit(1).padding(.top, 14)
            Text("\(tipoLabels[c.tipo ?? ""] ?? "Galería") · " + (visitas == 0 ? "todavía no la abre" : "la abrió \(visitas) \(visitas == 1 ? "vez" : "veces") pero no ha descargado"))
                .font(NoktaFont.poppins(12.5)).foregroundStyle(NoktaTheme.textoSuave).padding(.top, 2)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(dias)").font(NoktaFont.poppins(54, .light)).tracking(-2.5).foregroundStyle(NoktaTheme.aviso)
                    .contentTransition(.numericText(value: Double(dias)))
                Text(dias == 0 ? "vence hoy" : dias == 1 ? "día para que venza" : "días para que venza")
                    .font(NoktaFont.poppins(13)).foregroundStyle(NoktaTheme.textoSuave)
            }
            .padding(.top, 10)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(NoktaTheme.texto.opacity(0.08))
                    Capsule().fill(LinearGradient(colors: [NoktaTheme.exito, NoktaTheme.aviso], startPoint: .leading, endPoint: .trailing))
                        .frame(width: aparecio ? g.size.width * max(0.04, 1 - Double(dias) / total) : 0)
                        .animation(.spring(duration: 1.2, bounce: 0).delay(0.3), value: aparecio)
                }
            }
            .frame(height: 6).padding(.top, 12)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { accionesUrgente(c) }
                VStack(alignment: .leading, spacing: 8) { accionesUrgente(c) }
            }
            .padding(.top, 18)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [NoktaTheme.aviso.opacity(0.08), .clear], startPoint: .topLeading, endPoint: .center),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .noktaBordeLuz(NoktaTheme.aviso, radio: 22, siempre: true)
    }

    @ViewBuilder
    private func accionesUrgente(_ c: NoktaCliente) -> some View {
        if !(c.whatsapp ?? "").isEmpty {
            Button { abrir(.recordatorio(c.codigo, .vencePronto)) } label: { Label("Mandarle recordatorio", systemImage: "message") }
                .buttonStyle(BotonBrasa())
        }
        Button { abrir(.dias(c.codigo)) } label: { Label("Darle más días", systemImage: "clock.arrow.circlepath") }
            .buttonStyle(NoktaBotonSecundario())
        Button { copiar(GaleriasViewModel.link(c), "Link copiado") } label: { Label("Copiar link", systemImage: "link") }
            .buttonStyle(NoktaBotonSecundario())
    }

    private func fila(_ c: NoktaCliente) -> some View {
        let s = vm.situacion(c)
        let dias = vm.diasRestantes(c)
        let reac = (c.reactivaciones ?? []).count
        return HStack(spacing: 12) {
            Image(systemName: s.icono)
                .font(.system(size: 14, weight: .regular)).foregroundStyle(s.color)
                .frame(width: 38, height: 38)
                .background(s.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(c.nombre).font(NoktaFont.poppins(13.5, .medium)).foregroundStyle(NoktaTheme.texto).lineLimit(1)
                    if reac > 0 {
                        Text("↺ \(reac)").font(NoktaFont.poppins(10, .medium)).foregroundStyle(NoktaTheme.aviso)
                            .help("Reactivada \(reac) \(reac == 1 ? "vez" : "veces")")
                    }
                }
                Text("\(c.codigo) · \((c.visitas ?? []).count) visitas")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(NoktaTheme.textoTenue).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                pastilla(s)
                Text(detalleDias(s, dias, c)).font(NoktaFont.poppins(10.5)).foregroundStyle(NoktaTheme.textoTenue)
            }
            menuAcciones(c)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(NoktaTheme.superficie, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(NoktaTheme.borde))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .noktaHover(radio: 16)
        .contextMenu { acciones(c) }
    }

    private func detalleDias(_ s: SituacionGaleria, _ dias: Int?, _ c: NoktaCliente) -> String {
        switch s {
        case .vencida: return "reactívala para dar más días"
        case .descargada:
            if let f = c.descargas?.last?.fecha { return "descargó el \(FechaUtil.fechaCorta(String(f.prefix(10))))" }
            return "ya descargó"
        default:
            guard let dias else { return "sin límite" }
            return dias == 1 ? "1 día" : "\(dias) días"
        }
    }

    private func pastilla(_ s: SituacionGaleria) -> some View {
        HStack(spacing: 5) {
            Circle().fill(s.color).frame(width: 5, height: 5)
            Text(s.texto)
        }
        .font(NoktaFont.poppins(10.5, .medium)).foregroundStyle(s.color)
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(s.color.opacity(0.12), in: Capsule())
        .fixedSize()
    }

    private func menuAcciones(_ c: NoktaCliente) -> some View {
        Menu { acciones(c) } label: {
            Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium))
                .foregroundStyle(NoktaTheme.textoSuave)
                .frame(width: 32, height: 32)
                .background(NoktaTheme.superficie2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    @ViewBuilder
    private func acciones(_ c: NoktaCliente) -> some View {
        if let url = URL(string: GaleriasViewModel.link(c)) {
            Button { openURL(url) } label: { Label("Ver galería", systemImage: "eye") }
        }
        Button { copiar(GaleriasViewModel.link(c), "Link copiado") } label: { Label("Copiar link", systemImage: "link") }
        Button { copiar(c.codigo, "Código copiado") } label: { Label("Copiar código", systemImage: "key") }
        if !(c.whatsapp ?? "").isEmpty {
            Button { abrir(.recordatorio(c.codigo, vm.situacion(c) == .porVencer ? .vencePronto : .listas)) } label: { Label("Enviar por WhatsApp", systemImage: "message") }
        }
        Button { abrir(.dias(c.codigo)) } label: { Label(vm.vencida(c) ? "Reactivar" : "Darle más días", systemImage: "clock.arrow.circlepath") }
        Divider()
        Button(role: .destructive) { eliminarConfirm = c } label: { Label("Eliminar", systemImage: "trash") }
    }

    private func copiar(_ texto: String, _ aviso: String) {
        copyToClipboard(texto)
        withAnimation(.spring(duration: 0.3)) { copiado = aviso }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeOut(duration: 0.3)) { if copiado == aviso { copiado = nil } }
        }
    }

    // MARK: Panel lateral

    private func abrir(_ p: PanelGaleria?) {
        withAnimation(.spring(duration: 0.45, bounce: 0.08)) { panel = p }
    }

    @ViewBuilder
    private var panelLateral: some View {
        if let p = panel {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                    .onTapGesture { abrir(nil) }
                    .transition(.opacity)
                Group {
                    switch p {
                    case .nueva:
                        PanelNuevaGaleria(cerrar: { abrir(nil) }, crear: { n, t, d, w in
                            await vm.crear(nombre: n, tipo: t, dias: d, whatsapp: w)
                        }, avisar: { codigo in abrir(.recordatorio(codigo, .listas)) })
                    case .dias(let codigo):
                        if let c = vm.galClientes.first(where: { $0.codigo == codigo }) {
                            PanelMasDias(cliente: c, vm: vm, cerrar: { abrir(nil) },
                                         avisar: { abrir(.recordatorio(codigo, .masDias)) })
                        }
                    case .recordatorio(let codigo, let tipo):
                        if let c = vm.galClientes.first(where: { $0.codigo == codigo }) {
                            PanelRecordatorio(cliente: c, vm: vm, tipoInicial: tipo, cerrar: { abrir(nil) })
                                .id(codigo + tipo.rawValue)
                        }
                    }
                }
                .frame(width: min(ancho * 0.92, 460))
                .frame(maxHeight: 620)
                .fixedSize(horizontal: false, vertical: true)
                .background(NoktaTheme.superficie, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(NoktaTheme.borde))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 34, y: 14)
                .padding(20)
                .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
            .onKeyPress(.escape) { abrir(nil); return .handled }
        }
    }

    // MARK: Columna lateral

    private var columnaLado: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                numero("ACTIVAS", vm.activas, NoktaTheme.exito)
                numero("DESCARGADAS", vm.descargadas, NoktaPalette.blue)
                numero("VISITAS", vm.visitas, NoktaTheme.texto)
                numero("VENCIDAS", vm.vencidas, NoktaTheme.error)
            }
            .noktaEntrada(aparecio, 2)
            actividad.noktaEntrada(aparecio, 3)
        }
    }

    private func numero(_ t: String, _ v: Int, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(t).font(NoktaFont.poppins(10, .medium)).tracking(1.2).foregroundStyle(NoktaTheme.textoTenue)
            Text("\(aparecio ? v : 0)").font(NoktaFont.poppins(28, .light)).tracking(-1).foregroundStyle(c)
                .contentTransition(.numericText(value: Double(aparecio ? v : 0)))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .noktaCard()
    }

    private var actividad: some View {
        let ev = vm.actividad
        return VStack(alignment: .leading, spacing: 0) {
            Text("ACTIVIDAD RECIENTE").font(NoktaFont.poppins(10, .medium)).tracking(1.4).foregroundStyle(NoktaTheme.textoTenue)
                .padding(.bottom, 8)
            if ev.isEmpty {
                Text(vm.isLoading ? "Cargando…" : "Todavía no hay movimiento").font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoTenue)
                    .padding(.vertical, 8)
            }
            ForEach(Array(ev.enumerated()), id: \.element.id) { i, e in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(e.color).frame(width: 7, height: 7)
                        .shadow(color: e.color.opacity(0.7), radius: 4)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 1) {
                        (Text(e.nombre).fontWeight(.medium).foregroundStyle(NoktaTheme.texto)
                         + Text(" " + e.texto).foregroundStyle(NoktaTheme.textoSuave))
                            .font(NoktaFont.poppins(12))
                        Text(cuando(e.fecha)).font(NoktaFont.poppins(10.5)).foregroundStyle(NoktaTheme.textoTenue)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(NoktaTheme.borde).frame(height: 1) } }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .noktaCard()
    }

    private func cuando(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "es")
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: Date())
    }
}

/// Botón naranja degradado (como "Marcar como pagada" en el detalle de trabajo).
private struct BotonBrasa: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NoktaFont.poppins(12, .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(
                LinearGradient(colors: [Color(red: 0.855, green: 0.478, blue: 0.282), Color(red: 0.72, green: 0.32, blue: 0.157)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .shadow(color: NoktaTheme.marca.opacity(0.3), radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

// MARK: - Paneles laterales (nueva galería, más días, recordatorio)

/// Marco común: título, texto corto, contenido y botones abajo.
private struct MarcoPanel<Contenido: View, Pie: View>: View {
    let titulo: String
    let subtitulo: String
    var cerrar: () -> Void
    @ViewBuilder var contenido: () -> Contenido
    @ViewBuilder var pie: () -> Pie

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(titulo).font(NoktaFont.poppins(24, .light)).tracking(-0.8).foregroundStyle(NoktaTheme.texto)
                    Text(subtitulo).font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoSuave)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(action: cerrar) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(NoktaTheme.textoSuave)
                        .frame(width: 30, height: 30)
                        .background(NoktaTheme.superficie2, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain).help("Cerrar (Esc)")
            }
            .padding(.horizontal, 24).padding(.top, 26)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) { contenido() }
                    .padding(.horizontal, 24).padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            HStack(spacing: 8) { Spacer(minLength: 0); pie() }
                .padding(.horizontal, 24).padding(.vertical, 16)
                .overlay(alignment: .top) { Rectangle().fill(NoktaTheme.borde).frame(height: 1) }
        }
    }
}

private func rotuloPanel(_ t: String) -> some View {
    Text(t.uppercased()).font(NoktaFont.poppins(10, .medium)).tracking(1.3).foregroundStyle(NoktaTheme.textoTenue)
}

private struct CampoPanel: View {
    let titulo: String
    let placeholder: String
    @Binding var texto: String
    var enfocar = false
    @FocusState private var foco: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            rotuloPanel(titulo)
            TextField("", text: $texto, prompt: Text(placeholder).foregroundStyle(NoktaTheme.textoTenue))
                .textFieldStyle(.plain)
                .font(NoktaFont.poppins(13)).foregroundStyle(NoktaTheme.texto)
                .focused($foco)
                .padding(.horizontal, 12).frame(height: 40)
                .background(NoktaTheme.superficie2, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(foco ? NoktaTheme.marca.opacity(0.6) : NoktaTheme.borde, lineWidth: 1))
                .animation(.easeOut(duration: 0.15), value: foco)
        }
        .onAppear { if enfocar { foco = true } }
    }
}

/// Pastillas de opción (una elegida), que pueden bajar de línea.
private struct OpcionesPanel<V: Hashable>: View {
    let opciones: [(V, String)]
    @Binding var seleccion: V

    var body: some View {
        FlujoPanel(espacio: 6) {
            ForEach(opciones, id: \.0) { v, t in
                let on = v == seleccion
                Button { withAnimation(.snappy(duration: 0.25)) { seleccion = v } } label: {
                    Text(t)
                        .font(NoktaFont.poppins(12, on ? .medium : .regular))
                        .foregroundStyle(on ? NoktaTheme.fondo : NoktaTheme.textoSuave)
                        .padding(.horizontal, 13).frame(height: 32)
                        .background(on ? NoktaTheme.texto : NoktaTheme.superficie2, in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? .clear : NoktaTheme.borde))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Acomoda elementos en filas que bajan de línea cuando no caben.
private struct FlujoPanel: Layout {
    var espacio: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ancho = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, alto: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > ancho { x = 0; y += alto + espacio; alto = 0 }
            x += s.width + espacio; alto = max(alto, s.height); maxX = max(maxX, x - espacio)
        }
        return CGSize(width: min(maxX, ancho), height: y + alto)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, alto: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += alto + espacio; alto = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + espacio; alto = max(alto, s.height)
        }
    }
}

/// Crear galería, con el pase de cómo le llega al cliente.
private struct PanelNuevaGaleria: View {
    let cerrar: () -> Void
    let crear: (String, String, Int, String) async -> String?
    let avisar: (String) -> Void

    @State private var nombre = ""
    @State private var tipo = "boda"
    @State private var dias = 30
    @State private var whatsapp = ""
    @State private var error: String?
    @State private var codigo: String?
    @State private var creando = false

    private let tipos: [(String, String)] = [("boda", "Boda"), ("xvanios", "XV Años"), ("graduacion", "Graduación"),
                                             ("corporativo", "Corporativo"), ("deportivo", "Deportivo"), ("otro", "Otro")]

    var body: some View {
        MarcoPanel(titulo: codigo == nil ? "Nueva galería" : "Galería creada",
                   subtitulo: codigo == nil ? "Se crea un código privado para que tu cliente vea y descargue sus fotos."
                                            : "Sube las fotos a su carpeta y mándale el link.",
                   cerrar: cerrar) {
            if let codigo {
                pase(codigoMostrado: codigo)
                Button { copyToClipboard(codigo) } label: { Label("Copiar código", systemImage: "key") }
                    .buttonStyle(NoktaBotonSecundario())
            } else {
                CampoPanel(titulo: "Cliente", placeholder: "Ej. Boda Andrea & Luis", texto: $nombre, enfocar: true)
                VStack(alignment: .leading, spacing: 7) { rotuloPanel("Evento"); OpcionesPanel(opciones: tipos, seleccion: $tipo) }
                VStack(alignment: .leading, spacing: 7) {
                    rotuloPanel("Acceso")
                    OpcionesPanel(opciones: [(15, "15 días"), (30, "30 días"), (60, "60 días"), (0, "Sin límite")], seleccion: $dias)
                }
                CampoPanel(titulo: "WhatsApp del cliente", placeholder: "7000 0000 o con código de país", texto: $whatsapp)
                VStack(alignment: .leading, spacing: 8) {
                    rotuloPanel("Así le llega")
                    pase(codigoMostrado: nil)
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.circle").font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.error)
                }
            }
        } pie: {
            if let codigo {
                if !whatsapp.filter(\.isNumber).isEmpty {
                    Button { avisar(codigo) } label: { Label("Mandarle el link", systemImage: "message") }
                        .buttonStyle(NoktaBotonSecundario())
                }
                Button("Listo", action: cerrar).buttonStyle(NoktaBotonPrimario())
            } else {
                Button("Cancelar", action: cerrar).buttonStyle(NoktaBotonSecundario())
                Button { Task { await guardar() } } label: {
                    Label(creando ? "Creando…" : "Crear galería", systemImage: "plus")
                }
                .buttonStyle(BotonBrasa())
                .disabled(creando)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    /// El pase: anillo con los días de acceso, nombre y código.
    private func pase(codigoMostrado: String?) -> some View {
        let nombreVisto = nombre.trimmingCharacters(in: .whitespaces)
        return HStack(spacing: 14) {
            ZStack {
                Circle().stroke(NoktaTheme.texto.opacity(0.08), lineWidth: 4)
                Circle().trim(from: 0, to: dias == 0 ? 1 : min(1, Double(dias) / 60))
                    .stroke(NoktaTheme.exito, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: NoktaTheme.exito.opacity(0.5), radius: 5)
                    .animation(.spring(duration: 0.6), value: dias)
                VStack(spacing: -1) {
                    Text(dias == 0 ? "∞" : "\(dias)").font(NoktaFont.poppins(17, .light)).foregroundStyle(NoktaTheme.texto)
                        .contentTransition(.numericText(value: Double(dias)))
                    Text("DÍAS").font(NoktaFont.poppins(7, .medium)).foregroundStyle(NoktaTheme.textoTenue)
                }
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(nombreVisto.isEmpty ? "Nombre del cliente" : nombreVisto)
                    .font(NoktaFont.poppins(14, .medium))
                    .foregroundStyle(nombreVisto.isEmpty ? NoktaTheme.textoTenue : NoktaTheme.texto).lineLimit(1)
                Text(tipos.first { $0.0 == tipo }?.1 ?? "").font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoSuave)
                Text(codigoMostrado ?? "El código se crea al guardar")
                    .font(.system(size: codigoMostrado == nil ? 10.5 : 15, design: .monospaced))
                    .foregroundStyle(codigoMostrado == nil ? NoktaTheme.textoTenue : NoktaTheme.marca)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(NoktaTheme.superficie2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(NoktaTheme.borde))
    }

    private func guardar() async {
        error = nil
        let n = nombre.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { error = "Escribe el nombre del cliente"; return }
        var wa = whatsapp.filter(\.isNumber)
        if wa.count == 8 { wa = "503" + wa }
        creando = true
        defer { creando = false }
        if let c = await crear(n, tipo, dias, wa) {
            withAnimation(.spring(duration: 0.4)) { codigo = c }
        } else {
            error = "No se pudo crear la galería. Revisa tu conexión."
        }
    }
}

/// Darle más días: muestra la fecha de antes y la nueva.
private struct PanelMasDias: View {
    let cliente: NoktaCliente
    let vm: GaleriasViewModel
    let cerrar: () -> Void
    let avisar: () -> Void

    @State private var dias = 15
    @State private var guardando = false
    @State private var listo = false
    @State private var antes: Date?
    @State private var estabaVencida = false

    /// Igual que el servidor: se suma a la fecha actual de vencimiento si
    /// todavía no pasó; si ya venció (o no tenía), desde hoy.
    private var nuevaFecha: Date {
        let base = GaleriasViewModel.fecha(cliente.expira).flatMap { $0 > Date() ? $0 : nil } ?? Date()
        return base.addingTimeInterval(Double(dias) * 86400)
    }

    var body: some View {
        let tieneWA = !(cliente.whatsapp ?? "").isEmpty
        MarcoPanel(titulo: listo ? "Listo, más días" : (estabaVencida ? "Reactivar galería" : "Darle más días"),
                   subtitulo: "\(cliente.nombre) podrá entrar a su galería otra vez.", cerrar: cerrar) {
            if !listo {
                VStack(alignment: .leading, spacing: 7) {
                    rotuloPanel("Cuántos días")
                    OpcionesPanel(opciones: [(7, "7 días"), (15, "15 días"), (30, "30 días"), (60, "60 días")], seleccion: $dias)
                }
            }
            HStack(spacing: 10) {
                cajaFecha(estabaVencida ? "VENCIÓ" : "VENCÍA", antes.map(GaleriasViewModel.diaCorto) ?? "sin fecha", nueva: false)
                Image(systemName: "arrow.right").font(.system(size: 12)).foregroundStyle(NoktaTheme.textoTenue)
                cajaFecha("AHORA VENCE", GaleriasViewModel.diaCorto(listo ? (GaleriasViewModel.fecha(cliente.expira) ?? nuevaFecha) : nuevaFecha), nueva: true)
            }
            Text(listo ? (tieneWA ? "¿Le avisas por WhatsApp? El mensaje ya va con la fecha nueva." : "Ya puede entrar de nuevo con su mismo código.")
                       : "Los días se suman a los que le quedan. Después puedes mandarle el aviso por WhatsApp.")
                .font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoSuave)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NoktaTheme.superficie2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } pie: {
            if listo {
                if tieneWA {
                    Button(action: avisar) { Label("Avisarle", systemImage: "message") }.buttonStyle(NoktaBotonSecundario())
                }
                Button("Listo", action: cerrar).buttonStyle(NoktaBotonPrimario())
            } else {
                Button("Cancelar", action: cerrar).buttonStyle(NoktaBotonSecundario())
                Button {
                    guardando = true
                    Task {
                        await vm.reactivar(cliente.codigo, dias: dias)
                        guardando = false
                        withAnimation(.spring(duration: 0.4)) { listo = true }
                    }
                } label: { Label(guardando ? "Guardando…" : "Dar \(dias) días", systemImage: "clock.arrow.circlepath") }
                .buttonStyle(BotonBrasa())
                .disabled(guardando)
            }
        }
        .onAppear { antes = GaleriasViewModel.fecha(cliente.expira); estabaVencida = vm.vencida(cliente) }
    }

    private func cajaFecha(_ t: String, _ v: String, nueva: Bool) -> some View {
        VStack(spacing: 3) {
            Text(t).font(NoktaFont.poppins(9.5, .medium)).tracking(1).foregroundStyle(NoktaTheme.textoTenue)
            Text(v).font(NoktaFont.poppins(19, .light)).foregroundStyle(nueva ? NoktaTheme.exito : NoktaTheme.texto)
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.4), value: v)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(nueva ? NoktaTheme.exito.opacity(0.08) : NoktaTheme.superficie2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(nueva ? NoktaTheme.exito.opacity(0.3) : .clear))
    }
}

/// Recordatorio: muestra el mensaje como burbuja de WhatsApp, se puede
/// cambiar, y al final abre WhatsApp listo para enviar (no se manda solo).
private struct PanelRecordatorio: View {
    let cliente: NoktaCliente
    let vm: GaleriasViewModel
    let tipoInicial: TipoMensaje
    let cerrar: () -> Void

    @State private var tipo: TipoMensaje = .listas
    @State private var texto = ""
    @State private var editando = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        MarcoPanel(titulo: "Mensaje por WhatsApp", subtitulo: "Revisa el mensaje antes de enviarlo. No se manda solo.", cerrar: cerrar) {
            OpcionesPanel(opciones: TipoMensaje.allCases.map { ($0, $0.texto) }, seleccion: $tipo)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Text(NoktaFormato.iniciales(cliente.nombre))
                        .font(NoktaFont.poppins(9.5, .medium)).foregroundStyle(Color(white: 0.7))
                        .frame(width: 28, height: 28).background(Color(red: 0.16, green: 0.22, blue: 0.26), in: Circle())
                    VStack(alignment: .leading, spacing: 0) {
                        Text(cliente.nombre).font(NoktaFont.poppins(12, .medium)).foregroundStyle(Color(red: 0.91, green: 0.93, blue: 0.94))
                        Text("+" + (cliente.whatsapp ?? "")).font(NoktaFont.poppins(10)).foregroundStyle(Color(red: 0.53, green: 0.59, blue: 0.63))
                    }
                }
                .padding(.bottom, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) }
                HStack {
                    Spacer(minLength: 30)
                    Group {
                        if editando {
                            TextEditor(text: $texto)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 170)
                        } else {
                            Text(texto).frame(maxWidth: .infinity, alignment: .leading)
                                .onTapGesture { editando = true }
                        }
                    }
                    .font(NoktaFont.poppins(12.5))
                    .foregroundStyle(Color(red: 0.91, green: 0.93, blue: 0.94))
                    .padding(10)
                    .background(Color(red: 0, green: 0.36, blue: 0.29), in: UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12, bottomTrailingRadius: 3, topTrailingRadius: 12, style: .continuous))
                }
            }
            .padding(12)
            .background(Color(red: 0.04, green: 0.08, blue: 0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Button { editando.toggle() } label: {
                Label(editando ? "Ver como burbuja" : "Cambiar el mensaje", systemImage: editando ? "eye" : "pencil")
                    .font(NoktaFont.poppins(11.5, .medium))
            }
            .buttonStyle(.plain).foregroundStyle(NoktaTheme.marca)
        } pie: {
            Button { copyToClipboard(texto) } label: { Label("Copiar texto", systemImage: "doc.on.doc") }
                .buttonStyle(NoktaBotonSecundario())
            Button {
                if let url = GaleriasViewModel.whatsappURL(cliente, texto: texto) { openURL(url); cerrar() }
            } label: { Label("Abrir WhatsApp", systemImage: "message.fill") }
            .buttonStyle(BotonWhatsApp())
        }
        .onAppear { tipo = tipoInicial; texto = vm.mensaje(cliente, tipoInicial) }
        .onChange(of: tipo) { texto = vm.mensaje(cliente, tipo); editando = false }
    }
}

private struct BotonWhatsApp: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NoktaFont.poppins(12, .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(LinearGradient(colors: [Color(red: 0.17, green: 0.82, blue: 0.42), Color(red: 0.11, green: 0.66, blue: 0.32)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: Color(red: 0.15, green: 0.83, blue: 0.4).opacity(0.3), radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}
