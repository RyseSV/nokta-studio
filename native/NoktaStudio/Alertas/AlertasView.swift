import SwiftUI

/// Per-type look: SF Symbol, color and a short title.
private struct AlertaTipo {
    let icono: String
    let color: Color
    let titulo: String
}

private func alertaTipo(_ a: NoktaAlerta) -> AlertaTipo {
    switch a.tipo {
    case "quincena_vencida": AlertaTipo(icono: "clock.badge.exclamationmark", color: NoktaTheme.error, titulo: "Quincena sin pagar")
    case "pago_pendiente": AlertaTipo(icono: "banknote", color: NoktaTheme.aviso, titulo: "Pago pendiente")
    case "link_venciendo": AlertaTipo(icono: "link", color: NoktaTheme.aviso, titulo: "Link por vencer")
    case "evento_proximo": AlertaTipo(icono: "calendar", color: NoktaTheme.marca, titulo: "Evento próximo")
    case "descarga": AlertaTipo(icono: "arrow.down.to.line", color: NoktaPalette.blue, titulo: "Descargaron una galería")
    default: AlertaTipo(icono: "bell", color: NoktaTheme.textoSuave, titulo: a.tipo)
    }
}

/// Lower = more urgent. Money owed first, then links about to expire, then
/// upcoming events, then the rest.
private func urgencia(_ a: NoktaAlerta) -> Int {
    switch a.tipo {
    case "quincena_vencida": 0
    case "pago_pendiente": 1
    case "link_venciendo": (a.datos.diasRestantes ?? 99) <= 2 ? 2 : 4
    case "evento_proximo": 3
    default: 5
    }
}

@MainActor
@Observable
final class AlertasViewModel {
    var alertas: [NoktaAlerta] = []
    var isLoading = true
    var isMutating = false
    var errorMessage: String?
    var trabajoIdMostrado: String?
    /// Fired after every load/mutation so the caller can mirror the unread
    /// count elsewhere (e.g. RootView's sidebar badge).
    var onUnreadChange: (Int) -> Void = { _ in }

    private func notifyUnreadChange() {
        onUnreadChange(alertas.filter { !$0.leida }.count)
    }

    func load() async {
        guard !isMutating else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fetched: [NoktaAlerta] = try await NoktaAPI.get("/api/alertas")
            // Keep read records on the server so automatic alerts stay deduplicated.
            alertas = fetched.filter { !$0.leida }
            notifyUnreadChange()
        } catch {
            errorMessage = "No se pudieron cargar las alertas: \(error.localizedDescription)"
        }
    }

    func marcarLeida(_ id: String) async {
        await marcarLeidas(path: "/api/alertas/\(id)/leer", id: id)
    }

    func marcarTodasLeidas() async {
        await marcarLeidas(path: "/api/alertas/leer", id: nil)
    }

    private func marcarLeidas(path: String, id: String?) async {
        guard !isLoading, !isMutating else { return }
        isMutating = true
        errorMessage = nil
        defer { isMutating = false }
        do {
            let _: OKResponse = try await NoktaAPI.put(path, body: [String: String]())
            if let id {
                alertas.removeAll { $0.id == id }
            } else {
                alertas.removeAll()
            }
            notifyUnreadChange()
        } catch {
            errorMessage = "No se pudieron marcar las alertas como leídas: \(error.localizedDescription)"
        }
    }

}

struct AlertasView: View {
    @State private var vm = AlertasViewModel()
    /// Lets RootView's sidebar badge update the instant an alert is read
    /// here, instead of waiting for its own 30s poll.
    var onUnreadChange: (Int) -> Void = { _ in }
    @State private var aparecio = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var compacto: Bool { sizeClass == .compact }
    #else
    private let compacto = false
    #endif

    /// Most urgent first; ties broken by most recent.
    private var ordenadas: [NoktaAlerta] {
        vm.alertas.sorted { (urgencia($0), $1.fecha) < (urgencia($1), $0.fecha) }
    }

    var body: some View {
        let lista = ordenadas
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                NoktaEncabezado(titulo: "Alertas", subtitulo: subtitulo(lista)) {
                    Button { Task { await vm.marcarTodasLeidas() } } label: {
                        Label("Marcar todo como leído", systemImage: "checkmark")
                    }
                    .buttonStyle(NoktaBotonSecundario())
                    .disabled(vm.isLoading || vm.isMutating || vm.alertas.isEmpty)
                }
                .noktaEntrada(aparecio, 0)

                if let errorMessage = vm.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.error)
                }

                if lista.isEmpty {
                    if vm.isLoading {
                        VStack(spacing: 0) { ForEach(0..<4, id: \.self) { _ in NoktaFilaCargando() } }.noktaCard()
                    } else {
                        NoktaVacio(icono: "checkmark", titulo: "Todo al día", detalle: "No tienes alertas pendientes.")
                            .noktaCard()
                            .noktaEntrada(aparecio, 1)
                    }
                } else {
                    if let primera = lista.first {
                        AlertaDestacada(alerta: primera, urgente: urgencia(primera) <= 2, compacto: compacto,
                                        abrir: accion(primera), listo: { await vm.marcarLeida(primera.id) })
                            .id(primera.id)
                            .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity),
                                                    removal: .move(edge: .trailing).combined(with: .opacity)))
                            .noktaEntrada(aparecio, 1)
                    }
                    if lista.count > 1 {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(lista.dropFirst().enumerated()), id: \.element.id) { i, a in
                                FilaAlerta(alerta: a, abrir: accion(a), listo: { await vm.marcarLeida(a.id) })
                                    .transition(.asymmetric(insertion: .opacity,
                                                            removal: .move(edge: .trailing).combined(with: .opacity)))
                                    .noktaEntrada(aparecio, 2 + i)
                            }
                        }
                        .padding(.leading, 22)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(NoktaTheme.borde).frame(width: 1).padding(.leading, 7).padding(.vertical, 14)
                        }
                        .noktaCard(padding: compacto ? 14 : 20)
                    }
                }
            }
            .animation(.spring(duration: 0.45, bounce: 0.12), value: lista.map(\.id))
            .padding(.horizontal, compacto ? 16 : 44)
            .padding(.vertical, compacto ? 16 : 36)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(NoktaTheme.fondo)
        #if os(iOS)
        .navigationTitle("Alertas")
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            vm.onUnreadChange = onUnreadChange
            withAnimation(.spring(duration: 0.6, bounce: 0.12)) { aparecio = true }
            await vm.load()
        }
        .refreshable { await vm.load() }
        .sheet(item: Binding(get: {
            vm.trabajoIdMostrado.map { TrabajoSheetContext(id: $0) }
        }, set: { if $0 == nil { vm.trabajoIdMostrado = nil } })) { ctx in
            NavigationStack {
                TrabajoDetailView(trabajoId: ctx.id, onBack: { vm.trabajoIdMostrado = nil })
            }
            .frame(minWidth: 980, minHeight: 560)
        }
    }

    private func subtitulo(_ lista: [NoktaAlerta]) -> String {
        if lista.isEmpty { return vm.isLoading ? "Revisando…" : "Todo al día" }
        let urgentes = lista.filter { urgencia($0) <= 2 }.count
        return "\(lista.count) sin leer" + (urgentes > 0 ? " · \(urgentes) urgente\(urgentes == 1 ? "" : "s")" : "")
    }

    /// Same actions the native app already had: alerts tied to a trabajo open it.
    private func accion(_ a: NoktaAlerta) -> (titulo: String, hacer: () -> Void)? {
        guard let id = a.datos.id else { return nil }
        switch a.tipo {
        case "pago_pendiente": return ("Ver trabajo", { vm.trabajoIdMostrado = id })
        case "quincena_vencida": return ("Ver quincenas", { vm.trabajoIdMostrado = id })
        case "evento_proximo":
            // Standalone calendar events aren't trabajos — nothing to open here.
            if a.datos.key?.hasPrefix("ev-") == true { return nil }
            return (a.datos.key?.contains("-ses-") == true ? "Ver clase" : "Ver trabajo", { vm.trabajoIdMostrado = id })
        default: return nil
        }
    }
}

// MARK: - Pieces

private func descripcion(_ a: NoktaAlerta) -> String {
    let d = a.datos
    switch a.tipo {
    case "descarga":
        return "\(d.nombre ?? "") descargó \((d.tipo ?? "") == "todo" ? "toda la galería" : "sus favoritas")"
    case "link_venciendo":
        let dias = d.diasRestantes ?? 0
        return "\(d.nombre ?? "") · \(d.codigo ?? "") · vence en \(dias) día\(dias == 1 ? "" : "s")"
    case "pago_pendiente":
        return "\(d.cliente ?? "") · \(d.servicio ?? "") · saldo \(NoktaFormato.dinero(d.saldo ?? 0))"
    case "evento_proximo":
        return "\(d.cliente ?? "") · \(d.tipo ?? "") · \(diaRelativo(d.fecha))" + ((d.hora ?? "").isEmpty ? "" : " · \(d.hora!)")
    case "quincena_vencida":
        return d.mensaje ?? ""
    default:
        return d.mensaje ?? ""
    }
}

/// Big sentence for the featured alert.
private func frase(_ a: NoktaAlerta) -> String {
    let d = a.datos
    switch a.tipo {
    case "quincena_vencida": return d.cliente.map { "\($0) tiene una quincena sin pagar" } ?? "Hay una quincena sin pagar"
    case "pago_pendiente": return "\(d.cliente ?? "Un cliente") te debe \(NoktaFormato.dinero(d.saldo ?? 0))"
    case "link_venciendo":
        let dias = d.diasRestantes ?? 0
        return "La galería de \(d.nombre ?? "un cliente") vence en \(dias) día\(dias == 1 ? "" : "s")"
    case "evento_proximo":
        let hora = (d.hora ?? "").isEmpty ? "" : " a las \(d.hora!)"
        return "\(d.cliente ?? "Tienes un evento") · \(d.tipo ?? "evento") \(diaRelativo(d.fecha))\(hora)"
    case "descarga": return "\(d.nombre ?? "Un cliente") descargó su galería"
    default: return alertaTipo(a).titulo
    }
}

/// "hoy", "mañana" or a short date for a "YYYY-MM-DD".
private func diaRelativo(_ fecha: String?) -> String {
    guard let fecha, fecha.count >= 10 else { return "" }
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
    guard let d = f.date(from: String(fecha.prefix(10))) else { return FechaUtil.fechaCorta(fecha) }
    let cal = Calendar.current
    if cal.isDateInToday(d) { return "hoy" }
    if cal.isDateInTomorrow(d) { return "mañana" }
    return "el " + FechaUtil.fechaCorta(fecha)
}

private func haceCuanto(_ iso: String) -> String {
    let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let d = f1.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
    let s = Date().timeIntervalSince(d)
    if s < 3600 { return "hace \(max(1, Int(s / 60))) min" }
    if s < 86400 { return "hace \(Int(s / 3600)) h" }
    if s < 172800 { return "ayer" }
    if s < 604800 { return "hace \(Int(s / 86400)) días" }
    let out = DateFormatter(); out.dateFormat = "d MMM"; out.locale = Locale(identifier: "es_MX")
    return out.string(from: d)
}

private struct AlertaDestacada: View {
    let alerta: NoktaAlerta
    let urgente: Bool
    let compacto: Bool
    let abrir: (titulo: String, hacer: () -> Void)?
    let listo: () async -> Void
    @State private var pulso = false
    @State private var encima = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let t = alertaTipo(alerta), c = t.color
        let forma = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let icono = ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(c, lineWidth: 2)
                .scaleEffect(pulso ? 1.6 : 1)
                .opacity(pulso ? 0 : 0.7)
            Image(systemName: t.icono).font(.system(size: 22, weight: .light)).foregroundStyle(c)
                .frame(width: 58, height: 58)
                .background(c.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .frame(width: 58, height: 58)
        let texto = VStack(alignment: .leading, spacing: 4) {
            Text(urgente ? "URGENTE" : "LO MÁS IMPORTANTE").font(NoktaFont.poppins(10, .medium)).tracking(2).foregroundStyle(c)
            Text(frase(alerta)).font(NoktaFont.poppins(compacto ? 20 : 26, .light)).tracking(-0.7).foregroundStyle(NoktaTheme.texto)
                .fixedSize(horizontal: false, vertical: true)
            Text(descripcion(alerta) + " · " + haceCuanto(alerta.fecha))
                .font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoSuave)
        }
        let botones = HStack(spacing: 8) {
            if let abrir { Button(abrir.titulo, action: abrir.hacer).buttonStyle(NoktaBotonPrimario()) }
            Button { Task { await listo() } } label: { Label("Listo", systemImage: "checkmark") }
                .buttonStyle(NoktaBotonSecundario())
        }
        Group {
            if compacto {
                VStack(alignment: .leading, spacing: 16) { HStack(spacing: 16) { icono; Spacer() }; texto; botones }
            } else {
                HStack(spacing: 22) { icono; texto; Spacer(minLength: 12); botones }
            }
        }
        .padding(compacto ? 20 : 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                forma.fill(NoktaTheme.superficie)
                Circle().fill(c.opacity(0.18)).frame(width: 360, height: 360).blur(radius: 90).offset(x: 120, y: -200)
            }
            .clipShape(forma)
        }
        .overlay(forma.strokeBorder(c.opacity(encima ? 0.7 : 0.35), lineWidth: 1))
        .shadow(color: c.opacity(encima ? 0.2 : 0), radius: 20, y: 8)
        .onHover { h in withAnimation(.easeOut(duration: 0.2)) { encima = h } }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) { pulso = true }
        }
    }
}

private struct FilaAlerta: View {
    let alerta: NoktaAlerta
    let abrir: (titulo: String, hacer: () -> Void)?
    let listo: () async -> Void
    @State private var encima = false

    var body: some View {
        let t = alertaTipo(alerta), c = t.color
        HStack(spacing: 14) {
            Image(systemName: t.icono).font(.system(size: 14, weight: .light)).foregroundStyle(c)
                .frame(width: 36, height: 36)
                .background(c.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(t.titulo).font(NoktaFont.poppins(13, .medium)).foregroundStyle(encima ? c : NoktaTheme.texto)
                Text(descripcion(alerta)).font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoSuave).lineLimit(2)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                if let abrir { Button(abrir.titulo, action: abrir.hacer).buttonStyle(NoktaBotonSecundario()) }
                Button { Task { await listo() } } label: { Image(systemName: "checkmark") }
                    .buttonStyle(NoktaBotonSecundario())
                    .help("Marcar como leída")
            }
            #if os(macOS)
            .opacity(encima ? 1 : 0)
            #endif
            Text(haceCuanto(alerta.fecha)).font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoTenue)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .leading) {
            Circle().fill(NoktaTheme.superficie).overlay(Circle().strokeBorder(c, lineWidth: 2))
                .frame(width: 11, height: 11).offset(x: -20)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(NoktaTheme.borde).frame(height: 1) }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { encima = h } }
    }
}

private struct TrabajoSheetContext: Identifiable { let id: String }

private extension FechaUtil {
    static func fechaHoraCorta(_ iso: String) -> String {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = withFractional.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let d else { return iso }
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy, HH:mm"
        f.locale = Locale(identifier: "es_MX")
        return f.string(from: d)
    }
}
