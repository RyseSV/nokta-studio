import SwiftUI

/// Read-only history of generated contracts — mirrors admin.html's
/// Contratos page. Generation itself lives in TrabajoDetailView, where the
/// client/trabajo context already exists; this is only "control de lo que
/// ya hice" (see the conversation that asked for it).
@Observable
final class ContratosViewModel {
    var contratos: [NoktaContrato] = []
    var trabajos: [NoktaTrabajo] = []
    var isLoading = true
    var errorMessage: String?

    func load() async {
        isLoading = true
        defer { isLoading = false }
        async let c: [NoktaContrato]? = try? NoktaAPI.get("/api/contratos")
        async let t: [NoktaTrabajo]? = try? NoktaAPI.get("/api/trabajos")
        if let c = await c { contratos = c.sorted { ($0.creado ?? "") > ($1.creado ?? "") } }
        if let t = await t { trabajos = t.sorted { ($0.fecha ?? $0.fechaInicio ?? "") > ($1.fecha ?? $1.fechaInicio ?? "") } }
    }

    func eliminar(_ id: String) async {
        struct Resp: Decodable { let ok: Bool? }
        errorMessage = nil
        do {
            let response: Resp = try await NoktaAPI.delete("/api/contratos/\(id)")
            guard response.ok == true else {
                errorMessage = "El servidor no confirmó la eliminación. Actualiza la lista antes de reintentar."
                return
            }
            contratos.removeAll { $0.id == id }
        } catch {
            errorMessage = "No se pudo confirmar la eliminación. \(error.localizedDescription)"
        }
    }
}

private struct ContratoPreviewItem: Identifiable { let id = UUID(); let url: URL; let title: String }

struct ContratosView: View {
    @State private var vm = ContratosViewModel()
    @State private var previewItem: ContratoPreviewItem?
    @State private var previewErrorMessage: String?
    @State private var eliminarConfirm: String?
    @State private var elegirTrabajoShown = false
    @State private var trabajoParaContrato: NoktaTrabajo?
    @State private var contratoErrorMessage: String?
    @State private var busqueda = ""
    @State private var aparecio = false
    @State private var ancho: CGFloat = 1000

    private var compacto: Bool { ancho < 600 }

    private var filtrados: [NoktaContrato] {
        let q = busqueda.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return vm.contratos }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return vm.contratos.filter { ($0.clienteNombre ?? "").range(of: q, options: opts) != nil || ($0.servicioTipo ?? "").range(of: q, options: opts) != nil }
    }

    /// Trabajos que todavía no tienen contrato generado (para crearlo con un clic).
    private var sinContrato: [NoktaTrabajo] {
        let conContrato = Set(vm.contratos.compactMap(\.trabajoId))
        return Array(vm.trabajos.filter { !conContrato.contains($0.id) }.prefix(6))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: compacto ? 18 : 26) {
                NoktaEncabezado(
                    titulo: "Contratos",
                    subtitulo: vm.isLoading && vm.contratos.isEmpty ? "Cargando tus contratos…"
                        : vm.contratos.isEmpty ? "Genera el contrato de cualquier trabajo en segundos."
                        : "\(vm.contratos.count) contrato\(vm.contratos.count == 1 ? "" : "s") generado\(vm.contratos.count == 1 ? "" : "s")"
                ) {
                    if !vm.contratos.isEmpty {
                        NoktaBuscador(texto: $busqueda, placeholder: "Buscar cliente o servicio…")
                            .frame(maxWidth: compacto ? .infinity : 240)
                    }
                    Button { elegirTrabajoShown = true } label: { Label("Nuevo contrato", systemImage: "plus") }
                        .buttonStyle(NoktaBotonPrimario())
                }
                .noktaEntrada(aparecio, 0)

                if let error = vm.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.error)
                }

                if vm.isLoading && vm.contratos.isEmpty {
                    LazyVGrid(columns: columnas, spacing: 16) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(NoktaTheme.superficie)
                                .frame(height: 200).modifier(NoktaBrillo())
                        }
                    }
                } else if vm.contratos.isEmpty {
                    vacio.noktaEntrada(aparecio, 1)
                } else {
                    if filtrados.isEmpty {
                        NoktaVacio(icono: "magnifyingglass", titulo: "Nada coincide", detalle: "Prueba con otro nombre o servicio.").noktaCard()
                    } else {
                        LazyVGrid(columns: columnas, spacing: 16) {
                            ForEach(Array(filtrados.enumerated()), id: \.element.id) { i, c in
                                TarjetaContrato(contrato: c, ver: { Task { await ver(c) } }, eliminar: { eliminarConfirm = c.id })
                                    .noktaEntrada(aparecio, 1 + i)
                            }
                        }
                        .animation(.snappy(duration: 0.35), value: filtrados.map(\.id))
                    }
                }

                if !vm.isLoading && !sinContrato.isEmpty {
                    sugeridos.noktaEntrada(aparecio, 4)
                }
            }
            .padding(.horizontal, compacto ? 20 : 44)
            .padding(.vertical, compacto ? 16 : 36)
            .frame(maxWidth: 1240, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(NoktaTheme.fondo)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { ancho = $0 }
        .task {
            withAnimation(.spring(duration: 0.6, bounce: 0.12)) { aparecio = true }
            await vm.load()
        }
        .refreshable { await vm.load() }
        .sheet(item: $previewItem) { item in
            PDFPreviewSheet(url: item.url, title: item.title)
        }
        .alert("No se pudo abrir el contrato", isPresented: Binding(get: { previewErrorMessage != nil }, set: { if !$0 { previewErrorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(previewErrorMessage ?? "")
        }
        .alert("¿Eliminar este contrato del historial?", isPresented: Binding(get: { eliminarConfirm != nil }, set: { if !$0 { eliminarConfirm = nil } })) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar", role: .destructive) {
                if let id = eliminarConfirm { Task { await vm.eliminar(id) } }
            }
        } message: {
            Text("El PDF ya generado no se ve afectado.")
        }
        .sheet(isPresented: $elegirTrabajoShown) {
            ElegirTrabajoSheet(trabajos: vm.trabajos, conContrato: Set(vm.contratos.compactMap(\.trabajoId))) { t in
                elegirTrabajoShown = false
                trabajoParaContrato = t
            }
        }
        .sheet(item: $trabajoParaContrato) { t in
            ContratoSheet(trabajo: t) { datos in
                Task { await generar(datos) }
                trabajoParaContrato = nil
            }
        }
        .alert("No se pudo generar el contrato", isPresented: Binding(get: { contratoErrorMessage != nil }, set: { if !$0 { contratoErrorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(contratoErrorMessage ?? "")
        }
    }

    private var columnas: [GridItem] {
        [GridItem(.adaptive(minimum: compacto ? 280 : 280, maximum: 460), spacing: 16)]
    }

    private var vacio: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(NoktaTheme.marca)
                .frame(width: 64, height: 64)
                .background(NoktaTheme.marca.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text("Aún no has generado contratos")
                .font(NoktaFont.poppins(20, .light)).foregroundStyle(NoktaTheme.texto)
            Text("Elige un trabajo y el contrato se llena solo con sus datos:\ncliente, servicio, fechas, anticipo y saldo.")
                .font(NoktaFont.poppins(12.5)).foregroundStyle(NoktaTheme.textoSuave)
                .multilineTextAlignment(.center)
            Button { elegirTrabajoShown = true } label: { Label("Crear el primero", systemImage: "plus") }
                .buttonStyle(NoktaBotonPrimario())
                .padding(.top, 4)
        }
        .padding(.vertical, 40).padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .noktaBordeLuz(NoktaTheme.marca, radio: 22)
    }

    private var sugeridos: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("TRABAJOS SIN CONTRATO").font(NoktaFont.poppins(10, .medium)).tracking(1.4).foregroundStyle(NoktaTheme.textoTenue)
                Spacer()
                Text("Un clic para generarlo").font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoTenue)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], spacing: 10) {
                ForEach(sinContrato, id: \.id) { t in
                    Button { trabajoParaContrato = t } label: {
                        HStack(spacing: 12) {
                            NoktaAvatar(nombre: t.cliente, tamano: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.cliente).font(NoktaFont.poppins(13, .medium)).foregroundStyle(NoktaTheme.texto).lineLimit(1)
                                Text(t.servicio).font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoTenue).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Label("Crear", systemImage: "plus")
                                .font(NoktaFont.poppins(11, .medium)).foregroundStyle(NoktaTheme.marca)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(NoktaTheme.superficie, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(NoktaTheme.borde))
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .noktaHover(radio: 14)
                }
            }
        }
        .padding(.top, 8)
    }

    private func generar(_ datos: ContratoParaPDF) async {
        do {
            let url = try await ContratoGenerator.generar(datos)
            previewItem = ContratoPreviewItem(url: url, title: "Contrato · \(datos.clienteNombre)")
            await vm.load()
        } catch {
            contratoErrorMessage = error.localizedDescription
        }
    }

    private func ver(_ c: NoktaContrato) async {
        let datos = ContratoParaPDF(
            trabajoId: c.trabajoId, ciudad: c.ciudad ?? "", fechaContrato: c.fechaContrato ?? "",
            clienteNombre: c.clienteNombre ?? "", clienteDui: c.clienteDui ?? "", clienteTelefono: c.clienteTelefono ?? "",
            clienteEmail: c.clienteEmail ?? "", clienteDireccion: c.clienteDireccion ?? "",
            servicioTipo: c.servicioTipo ?? "", servicioFecha: c.servicioFecha ?? "", servicioLugar: c.servicioLugar ?? "",
            entregables: c.entregables ?? "", anticipoMonto: c.anticipoMonto ?? 0, anticipoFecha: c.anticipoFecha ?? "",
            saldoMonto: c.saldoMonto ?? 0, saldoFecha: c.saldoFecha ?? "", plazoDias: c.plazoDias ?? "", mora: c.mora ?? 10
        )
        do {
            let url = try await PDFRenderer().renderToPDF(html: PDFTemplates.contrato(datos), suggestedName: datos.fileName)
            previewItem = ContratoPreviewItem(url: url, title: "Contrato · \(datos.clienteNombre)")
        } catch {
            previewErrorMessage = error.localizedDescription
        }
    }
}

/// Un contrato generado: cliente, servicio, total y cómo se paga.
private struct TarjetaContrato: View {
    let contrato: NoktaContrato
    let ver: () -> Void
    let eliminar: () -> Void

    var body: some View {
        let c = contrato
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "doc.text")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(NoktaTheme.marca)
                    .frame(width: 38, height: 38)
                    .background(NoktaTheme.marca.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Spacer()
                if let f = c.fechaContrato, !f.isEmpty {
                    Text(f).font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoSuave)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(NoktaTheme.superficie2, in: Capsule())
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 22)
            Text(c.clienteNombre ?? "—").font(NoktaFont.poppins(15, .medium)).foregroundStyle(NoktaTheme.texto).lineLimit(1)
            Text([c.servicioTipo, c.servicioLugar].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoTenue).lineLimit(1).padding(.top, 2)
            Text(NoktaFormato.dinero(c.total))
                .font(NoktaFont.poppins(32, .light)).tracking(-1.4)
                .foregroundStyle(NoktaTheme.texto)
                .padding(.top, 10)
            (Text("Anticipo ").foregroundStyle(NoktaTheme.textoSuave)
             + Text(NoktaFormato.dinero(c.anticipoMonto ?? 0)).foregroundStyle(NoktaTheme.marca)
             + Text(" · Saldo ").foregroundStyle(NoktaTheme.textoSuave)
             + Text(NoktaFormato.dinero(c.saldoMonto ?? 0)).foregroundStyle(NoktaTheme.texto))
                .font(NoktaFont.poppins(11)).lineLimit(1)
                .padding(.top, 4)
            HStack(spacing: 8) {
                Button(action: ver) { Label("Ver PDF", systemImage: "eye") }
                    .buttonStyle(NoktaBotonSecundario())
                Spacer()
                Menu {
                    Button(role: .destructive, action: eliminar) { Label("Eliminar del historial", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium))
                        .foregroundStyle(NoktaTheme.textoSuave)
                        .frame(width: 34, height: 34)
                        .background(NoktaTheme.superficie2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .leading)
        .noktaBordeLuz(NoktaTheme.marca, radio: 20)
    }
}

/// Selector de trabajo para "Nuevo contrato".
private struct ElegirTrabajoSheet: View {
    let trabajos: [NoktaTrabajo]
    var conContrato: Set<String> = []
    let onElegir: (NoktaTrabajo) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var busqueda = ""

    private var filtrados: [NoktaTrabajo] {
        let q = busqueda.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return trabajos }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return trabajos.filter { $0.cliente.range(of: q, options: opts) != nil || $0.servicio.range(of: q, options: opts) != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Elige el trabajo").font(NoktaFont.poppins(20, .light)).foregroundStyle(NoktaTheme.texto)
                Text("El contrato se llena con sus datos; podrás revisarlos antes de generar.")
                    .font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoSuave)
            }
            NoktaBuscador(texto: $busqueda, placeholder: "Buscar cliente o servicio…")
            ScrollView {
                VStack(spacing: 4) {
                    if filtrados.isEmpty {
                        Text("Sin resultados").font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoTenue)
                            .frame(maxWidth: .infinity).padding(24)
                    }
                    ForEach(filtrados, id: \.id) { t in
                        Button { onElegir(t) } label: {
                            HStack(spacing: 12) {
                                NoktaAvatar(nombre: t.cliente, tamano: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.cliente).font(NoktaFont.poppins(13, .medium)).foregroundStyle(NoktaTheme.texto).lineLimit(1)
                                    Text(t.servicio).font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoTenue).lineLimit(1)
                                }
                                Spacer()
                                if conContrato.contains(t.id) {
                                    Text("Ya tiene contrato").font(NoktaFont.poppins(10)).foregroundStyle(NoktaTheme.textoTenue)
                                }
                                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(NoktaTheme.textoTenue)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .noktaHover(radio: 10)
                    }
                }
            }
            .frame(maxHeight: 380)
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.buttonStyle(NoktaBotonSecundario()).keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(minWidth: 420, maxWidth: 480)
        .background(NoktaTheme.fondo)
    }
}
