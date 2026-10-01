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

    func whatsappURL(_ c: NoktaCliente, recordatorio: Bool) -> URL? {
        guard let wa = c.whatsapp?.filter(\.isNumber), !wa.isEmpty else { return nil }
        let dias = diasRestantes(c)
        let evento = tipoLabels[c.tipo ?? ""] ?? c.tipo ?? ""
        let msg: String
        if recordatorio, let dias {
            let cuando = dias == 0 ? "hoy" : dias == 1 ? "mañana" : "en \(dias) días"
            msg = "Hola \(c.nombre) 👋 Te recuerdo que tu galería de \(evento) vence \(cuando). Descargá tus fotos antes de que se cierre el acceso:\n\(Self.link(c))\n\nTu código de acceso es: \(c.codigo)"
        } else {
            let limite = dias != nil ? "El acceso estará disponible por \(dias!) días." : "El acceso no tiene límite de tiempo."
            msg = "Hola \(c.nombre), tus fotos de \(evento) ya están listas 📸\nPodés verlas y descargarlas en este link:\n\(Self.link(c))\n\nTu código de acceso es: \(c.codigo)\n\(limite)"
        }
        var comps = URLComponents(string: "https://wa.me/\(wa.count == 8 ? "503" + wa : wa)")
        comps?.queryItems = [URLQueryItem(name: "text", value: msg)]
        return comps?.url
    }
}

private let galFiltros: [(valor: String, texto: String)] = [
    ("todas", "Todas"), ("activas", "Activas"), ("descargadas", "Descargadas"), ("vencidas", "Vencidas"), ("reactivadas", "Reactivadas"),
]

/// Galerías ("lo urgente primero", 2026-10): la que vence pronto sin
/// descargar sale en grande con borde de luz; a la derecha los números y la
/// actividad reciente.
struct GaleriasView: View {
    @State private var vm = GaleriasViewModel()
    @State private var nuevaShown = false
    @State private var reactivarDe: NoktaCliente?
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
                    Button { nuevaShown = true } label: { Label("Nueva galería", systemImage: "plus") }
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
        .sheet(isPresented: $nuevaShown) {
            NuevaGaleriaSheet { nombre, tipo, dias, whatsapp in
                await vm.crear(nombre: nombre, tipo: tipo, dias: dias, whatsapp: whatsapp)
            }
        }
        .sheet(item: Binding(get: { reactivarDe.map { ReactivarId(codigo: $0.codigo, nombre: $0.nombre) } },
                             set: { if $0 == nil { reactivarDe = nil } })) { ctx in
            ReactivarSheet(nombre: ctx.nombre) { dias in await vm.reactivar(ctx.codigo, dias: dias) }
        }
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
        if let url = vm.whatsappURL(c, recordatorio: true) {
            Button { openURL(url) } label: { Label("Mandarle recordatorio", systemImage: "message") }
                .buttonStyle(BotonBrasa())
        }
        Button { reactivarDe = c } label: { Label("Darle más días", systemImage: "clock.arrow.circlepath") }
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
        if let url = vm.whatsappURL(c, recordatorio: vm.situacion(c) == .porVencer) {
            Button { openURL(url) } label: { Label("Enviar por WhatsApp", systemImage: "message") }
        }
        Button { reactivarDe = c } label: { Label(vm.vencida(c) ? "Reactivar" : "Darle más días", systemImage: "clock.arrow.circlepath") }
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

private struct ReactivarId: Identifiable { let codigo: String; let nombre: String; var id: String { codigo } }

private struct ReactivarSheet: View {
    let nombre: String
    let onConfirm: (Int) async -> Void
    @State private var dias = 15
    @State private var guardando = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Darle más días").font(NoktaFont.poppins(20, .light)).foregroundStyle(NoktaTheme.texto)
                Text("\(nombre) podrá entrar a su galería otra vez. Los días se suman a los que le queden.")
                    .font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoSuave)
            }
            NoktaChips(opciones: [(7, "7 días"), (15, "15 días"), (30, "30 días"), (60, "60 días")], seleccion: $dias)
            HStack {
                Button("Cancelar") { dismiss() }.buttonStyle(NoktaBotonSecundario())
                Spacer()
                Button(guardando ? "Guardando…" : "Dar \(dias) días") {
                    guardando = true
                    Task { await onConfirm(dias); dismiss() }
                }
                .buttonStyle(NoktaBotonPrimario())
                .disabled(guardando)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(NoktaTheme.fondo)
    }
}

private struct NuevaGaleriaSheet: View {
    let onCreate: (String, String, Int, String) async -> String?
    @Environment(\.dismiss) private var dismiss

    @State private var nombre = ""
    @State private var tipo = "boda"
    @State private var dias = 30
    @State private var whatsapp = ""
    @State private var errorMessage: String?
    @State private var resultCodigo: String?
    @State private var creando = false

    private let tipos = ["boda", "xvanios", "graduacion", "corporativo", "deportivo", "otro"]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Nueva galería").font(NoktaFont.poppins(22, .light)).foregroundStyle(NoktaTheme.texto)
                Text("Se crea un código privado para que tu cliente vea y descargue sus fotos.")
                    .font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoSuave)
            }

            if let resultCodigo {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Galería creada", systemImage: "checkmark.circle.fill")
                        .font(NoktaFont.poppins(13, .medium)).foregroundStyle(NoktaTheme.exito)
                    Text(resultCodigo).font(.system(size: 22, weight: .regular, design: .monospaced)).foregroundStyle(NoktaTheme.texto)
                        .textSelection(.enabled)
                    Text("Sube las fotos a su carpeta y mándale el link desde la lista.")
                        .font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoSuave)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NoktaTheme.exito.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                HStack {
                    Button { copyToClipboard(resultCodigo) } label: { Label("Copiar código", systemImage: "key") }
                        .buttonStyle(NoktaBotonSecundario())
                    Spacer()
                    Button("Listo") { dismiss() }.buttonStyle(NoktaBotonPrimario())
                }
            } else {
                campo("Nombre del cliente") {
                    TextField("", text: $nombre, prompt: Text("Ej. Boda Andrea & Luis").foregroundStyle(NoktaTheme.textoTenue))
                }
                VStack(alignment: .leading, spacing: 6) {
                    rotulo("Tipo de evento")
                    Menu {
                        ForEach(tipos, id: \.self) { k in Button(tipoLabels[k] ?? k) { tipo = k } }
                    } label: {
                        HStack {
                            Text(tipoLabels[tipo] ?? tipo).foregroundStyle(NoktaTheme.texto)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(NoktaTheme.textoTenue)
                        }
                        .font(NoktaFont.poppins(13))
                        .padding(.horizontal, 12).frame(height: 38)
                        .background(NoktaTheme.superficie2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                }
                VStack(alignment: .leading, spacing: 6) {
                    rotulo("Días de acceso")
                    NoktaChips(opciones: [(15, "15 días"), (30, "30 días"), (60, "60 días"), (0, "Sin límite")], seleccion: $dias)
                }
                campo("WhatsApp del cliente") {
                    TextField("", text: $whatsapp, prompt: Text("50370000000").foregroundStyle(NoktaTheme.textoTenue))
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.error)
                }
                HStack {
                    Button("Cancelar") { dismiss() }.buttonStyle(NoktaBotonSecundario())
                    Spacer()
                    Button(creando ? "Creando…" : "Crear galería") { Task { await crear() } }
                        .buttonStyle(NoktaBotonPrimario())
                        .disabled(creando)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(NoktaTheme.fondo)
    }

    private func rotulo(_ t: String) -> some View {
        Text(t.uppercased()).font(NoktaFont.poppins(10, .medium)).tracking(1.2).foregroundStyle(NoktaTheme.textoTenue)
    }

    private func campo<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            rotulo(t)
            c()
                .textFieldStyle(.plain)
                .font(NoktaFont.poppins(13)).foregroundStyle(NoktaTheme.texto)
                .padding(.horizontal, 12).frame(height: 38)
                .background(NoktaTheme.superficie2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func crear() async {
        errorMessage = nil
        guard !nombre.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Escribe el nombre del cliente"; return }
        creando = true
        defer { creando = false }
        resultCodigo = await onCreate(nombre.trimmingCharacters(in: .whitespaces), tipo, dias, whatsapp.filter(\.isNumber))
        if resultCodigo == nil { errorMessage = "No se pudo crear la galería. Revisa tu conexión." }
    }
}
