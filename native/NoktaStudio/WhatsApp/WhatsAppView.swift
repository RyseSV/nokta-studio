import SwiftUI

// MARK: - Modelos (GET /api/whatsapp/chats y /api/whatsapp/chats/:telefono)

struct WaChat: Decodable, Identifiable, Equatable {
    var telefono: String
    var nombre: String?
    var ultimo: String?
    var autorUltimo: String?
    var fecha: String?
    var noLeidos: Int
    var botPausado: Bool
    var ventanaAbierta: Bool
    var id: String { telefono }
    var titulo: String { nombre ?? "+\(telefono)" }
}

struct WaChatsRespuesta: Decodable {
    var chats: [WaChat]
    var noLeidos: Int
}

struct WaMensajeItem: Decodable, Identifiable, Equatable {
    var id: String
    var autor: String
    var quien: String?
    var texto: String?
    var fecha: String
}

struct WaConversacion: Decodable, Equatable {
    var telefono: String
    var nombre: String?
    var botPausado: Bool
    var ventanaAbierta: Bool
    var mensajes: [WaMensajeItem]
    var titulo: String { nombre ?? "+\(telefono)" }
}

private enum WaFecha {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static func date(_ s: String?) -> Date? { s.flatMap { iso.date(from: $0) } }
    static func hora(_ s: String?) -> String { date(s)?.formatted(date: .omitted, time: .shortened) ?? "" }
    static func corta(_ s: String?) -> String {
        guard let d = date(s) else { return "" }
        return Calendar.current.isDateInToday(d) ? d.formatted(date: .omitted, time: .shortened)
            : d.formatted(.dateTime.day().month(.abbreviated))
    }
    static func dia(_ s: String?) -> String {
        date(s)?.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es"))) ?? ""
    }
}

/// Formato de WhatsApp (*negrita*, _cursiva_) → AttributedString.
/// El texto del cliente no puede crear enlaces disfrazados: se escapa todo lo
/// que Markdown usa salvo * y _, y además se quita cualquier enlace resultante.
private func waTexto(_ s: String) -> AttributedString {
    var seguro = ""
    for ch in s { if "\\[]()<>`#!".contains(ch) { seguro.append("\\") }; seguro.append(ch) }
    let md = seguro.replacingOccurrences(of: #"\*([^*\n]+)\*"#, with: "**$1**", options: .regularExpression)
    let opciones = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    guard var a = try? AttributedString(markdown: md, options: opciones) else { return AttributedString(s) }
    for run in a.runs where run.link != nil { a[run.range].link = nil }
    return a
}

// MARK: - ViewModel

@MainActor
@Observable
final class WhatsAppViewModel {
    var chats: [WaChat] = []
    var conversacion: WaConversacion?
    var seleccion: String?
    var cargando = true
    var enviando = false
    var borrador = ""
    var error: String?
    var onUnreadChange: (Int) -> Void = { _ in }

    func cargar() async {
        do {
            let r: WaChatsRespuesta = try await NoktaAPI.get("/api/whatsapp/chats")
            if r.chats != chats { chats = r.chats }
            onUnreadChange(r.noLeidos)
            error = nil
        } catch {
            self.error = "No se pudo cargar WhatsApp: \(error.localizedDescription)"
        }
        cargando = false
        if seleccion != nil { await cargarConversacion() }
    }

    func abrir(_ telefono: String) async {
        seleccion = telefono
        conversacion = nil
        await cargarConversacion()
        await cargar()
    }

    func cargarConversacion() async {
        guard let tel = seleccion else { return }
        do {
            let c: WaConversacion = try await NoktaAPI.get("/api/whatsapp/chats/\(tel.urlPathComponentEncoded)")
            if tel == seleccion, c != conversacion { conversacion = c }
        } catch {
            self.error = "No se pudo abrir el chat: \(error.localizedDescription)"
        }
    }

    func enviar() async {
        let texto = borrador.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let tel = seleccion, !texto.isEmpty, !enviando else { return }
        enviando = true
        defer { enviando = false }
        struct Cuerpo: Encodable { let texto: String }
        do {
            let _: OKResponse = try await NoktaAPI.post("/api/whatsapp/chats/\(tel.urlPathComponentEncoded)/enviar", body: Cuerpo(texto: texto))
            // Solo se vacía si no escribió nada nuevo mientras se enviaba.
            if borrador.trimmingCharacters(in: .whitespacesAndNewlines) == texto { borrador = "" }
            error = nil
            await cargar()
        } catch {
            self.error = mensaje(error)
        }
    }

    func cambiarBot(activo: Bool) async {
        guard let tel = seleccion else { return }
        struct Cuerpo: Encodable { let activo: Bool }
        do {
            let _: OKResponse = try await NoktaAPI.post("/api/whatsapp/chats/\(tel.urlPathComponentEncoded)/bot", body: Cuerpo(activo: activo))
            await cargar()
        } catch {
            self.error = mensaje(error)
        }
    }

    /// El servidor ya explica el problema (p. ej. las 24 h de WhatsApp):
    /// se muestra su texto tal cual, sin el "Error 409:".
    private func mensaje(_ e: Error) -> String {
        if case NoktaAPIError.http(_, let msg) = e, msg != "—" { return msg }
        return e.localizedDescription
    }
}

// MARK: - Vista

struct WhatsAppView: View {
    /// Chat a abrir al llegar (desde una alerta).
    var abrir: String?
    var onUnreadChange: (Int) -> Void = { _ in }
    @State private var vm = WhatsAppViewModel()
    @State private var aparecio = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var compacto: Bool { sizeClass == .compact }
    #else
    private let compacto = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            NoktaEncabezado(titulo: "WhatsApp", subtitulo: subtitulo)
                .noktaEntrada(aparecio, 0)
            if let e = vm.error {
                Label(e, systemImage: "exclamationmark.circle")
                    .font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.error)
            }
            Group {
                if compacto {
                    if vm.seleccion != nil { chat } else { lista }
                } else {
                    HStack(spacing: 0) {
                        lista.frame(width: 300)
                        Divider().overlay(NoktaTheme.borde)
                        chat
                    }
                }
            }
            .background(NoktaTheme.superficie)
            .clipShape(RoundedRectangle(cornerRadius: NoktaTheme.radioTarjeta, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoktaTheme.radioTarjeta, style: .continuous).stroke(NoktaTheme.borde))
            .noktaEntrada(aparecio, 1)
        }
        .padding(.horizontal, compacto ? 16 : 44)
        .padding(.vertical, compacto ? 16 : 36)
        .frame(maxWidth: 1240, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .background(NoktaTheme.fondo)
        #if os(iOS)
        .navigationTitle("WhatsApp")
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            vm.onUnreadChange = onUnreadChange
            withAnimation(.spring(duration: 0.6, bounce: 0.12)) { aparecio = true }
            if let abrir { await vm.abrir(abrir) } else { await vm.cargar() }
            // Se refresca sola mientras está abierta, como el panel web.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                await vm.cargar()
            }
        }
    }

    private var subtitulo: String {
        if vm.chats.isEmpty { return vm.cargando ? "Cargando…" : "Conversaciones del número de Nokta" }
        let n = vm.chats.reduce(0) { $0 + $1.noLeidos }
        return "\(vm.chats.count) conversación\(vm.chats.count == 1 ? "" : "es")" + (n > 0 ? " · \(n) sin leer" : "")
    }

    private var lista: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if vm.chats.isEmpty {
                    if vm.cargando {
                        ForEach(0..<4, id: \.self) { _ in NoktaFilaCargando() }
                    } else {
                        NoktaVacio(icono: "bubble.left.and.bubble.right", titulo: "Aún no hay mensajes",
                                   detalle: "Cuando un cliente escriba al WhatsApp de Nokta, aparecerá aquí.")
                    }
                }
                ForEach(vm.chats) { c in
                    Button { Task { await vm.abrir(c.telefono) } } label: { fila(c) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func fila(_ c: WaChat) -> some View {
        HStack(spacing: 12) {
            NoktaAvatar(nombre: c.titulo, tamano: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.titulo).font(NoktaFont.poppins(13, .medium)).foregroundStyle(NoktaTheme.texto).lineLimit(1)
                Text(prefijo(c.autorUltimo) + (c.ultimo ?? "").components(separatedBy: "\n").first!)
                    .font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoSuave).lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                Text(WaFecha.corta(c.fecha)).font(NoktaFont.poppins(10)).foregroundStyle(NoktaTheme.textoTenue)
                HStack(spacing: 4) {
                    if c.botPausado { Image(systemName: "pause.circle").font(.system(size: 11)).foregroundStyle(NoktaTheme.textoTenue) }
                    if c.noLeidos > 0 {
                        Text(String(c.noLeidos)).font(NoktaFont.poppins(10, .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color(red: 0.145, green: 0.827, blue: 0.4), in: Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(vm.seleccion == c.telefono ? NoktaTheme.marcaSuave : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(NoktaTheme.borde).frame(height: 1) }
        .contentShape(Rectangle())
    }

    private func prefijo(_ autor: String?) -> String {
        switch autor { case "bot": "🤖 "; case "gabriel": "Tú: "; default: "" }
    }

    @ViewBuilder
    private var chat: some View {
        if let c = vm.conversacion {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    if compacto {
                        Button { vm.seleccion = nil; vm.conversacion = nil } label: {
                            Image(systemName: "chevron.left").font(.system(size: 15, weight: .medium))
                        }
                        .buttonStyle(.plain).foregroundStyle(NoktaTheme.texto)
                    }
                    NoktaAvatar(nombre: c.titulo, tamano: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.titulo).font(NoktaFont.poppins(14, .medium)).foregroundStyle(NoktaTheme.texto)
                        Text("+\(c.telefono) · \(c.botPausado ? "Bot en pausa (atiendes tú)" : "Bot activo")")
                            .font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoSuave)
                    }
                    Spacer()
                    Button { Task { await vm.cambiarBot(activo: c.botPausado) } } label: {
                        Label(c.botPausado ? "Activar bot" : "Pausar bot", systemImage: c.botPausado ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(NoktaBotonSecundario())
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                Divider().overlay(NoktaTheme.borde)
                mensajes(c)
                if !c.ventanaAbierta {
                    Text("Pasaron más de 24 horas desde su último mensaje. WhatsApp solo deja responder gratis dentro de ese plazo: cuando el cliente vuelva a escribir, podrás contestarle.")
                        .font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.aviso)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NoktaTheme.avisoSuave)
                }
                Divider().overlay(NoktaTheme.borde)
                HStack(alignment: .bottom, spacing: 10) {
                    TextField(c.ventanaAbierta ? "Escribe tu respuesta…" : "No se puede responder ahora", text: $vm.borrador, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(NoktaFont.poppins(13))
                        .lineLimit(1...6)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(NoktaTheme.fondo, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .disabled(!c.ventanaAbierta)
                        .onSubmit { Task { await vm.enviar() } }
                    Button { Task { await vm.enviar() } } label: {
                        Text("Enviar").font(NoktaFont.poppins(12, .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 16).frame(height: 40)
                            .background(Color(red: 0.145, green: 0.827, blue: 0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!c.ventanaAbierta || vm.enviando || vm.borrador.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(!c.ventanaAbierta || vm.enviando ? 0.45 : 1)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
        } else {
            NoktaVacio(icono: "bubble.left", titulo: vm.seleccion == nil ? "Elige una conversación" : "Cargando…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func mensajes(_ c: WaConversacion) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(c.mensajes.enumerated()), id: \.element.id) { i, m in
                        if i == 0 || WaFecha.dia(c.mensajes[i - 1].fecha) != WaFecha.dia(m.fecha) {
                            Text(WaFecha.dia(m.fecha))
                                .font(NoktaFont.poppins(10)).foregroundStyle(NoktaTheme.textoTenue)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(NoktaTheme.superficie, in: RoundedRectangle(cornerRadius: 8))
                                .padding(.vertical, 6)
                        }
                        burbuja(m).id(m.id)
                    }
                }
                .padding(18)
            }
            .background(NoktaTheme.fondo)
            .onAppear { proxy.scrollTo(c.mensajes.last?.id, anchor: .bottom) }
            .onChange(of: c.mensajes.last?.id) { _, ultimo in
                withAnimation { proxy.scrollTo(ultimo, anchor: .bottom) }
            }
        }
    }

    private func burbuja(_ m: WaMensajeItem) -> some View {
        let esCliente = m.autor == "cliente"
        let fondo: Color = switch m.autor {
        case "cliente": NoktaTheme.superficie
        case "gabriel": Color(red: 0.145, green: 0.827, blue: 0.4).opacity(0.22)
        default: NoktaTheme.superficie2
        }
        let firma = (m.autor == "bot" ? "🤖 Bot · " : m.autor == "gabriel" ? "\(m.quien ?? "Tú") · " : "") + WaFecha.hora(m.fecha)
        return HStack {
            if !esCliente { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 3) {
                Text(waTexto(m.texto ?? ""))
                    .font(NoktaFont.poppins(13))
                    .foregroundStyle(m.autor == "bot" ? NoktaTheme.textoSuave : NoktaTheme.texto)
                    .textSelection(.enabled)
                Text(firma).font(NoktaFont.poppins(10)).foregroundStyle(NoktaTheme.textoTenue)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12).padding(.top, 9).padding(.bottom, 6)
            .frame(maxWidth: 520, alignment: esCliente ? .leading : .trailing)
            .background(fondo, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(esCliente ? NoktaTheme.borde : .clear))
            if esCliente { Spacer(minLength: 60) }
        }
    }
}
