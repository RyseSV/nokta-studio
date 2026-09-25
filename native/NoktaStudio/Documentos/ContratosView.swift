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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Contratos").font(NoktaFont.pageTitle).foregroundStyle(NoktaPalette.cream)
                    Spacer()
                    Button("＋ Nuevo contrato") { elegirTrabajoShown = true }
                        .buttonStyle(.glassProminent).tint(NoktaPalette.ember)
                }
                Text("Elige un trabajo para generar su contrato, o revisa los que ya hiciste.")
                    .font(.system(size: 12)).foregroundStyle(NoktaPalette.muted)

                if let error = vm.errorMessage {
                    Text(error).font(.system(size: 12)).foregroundStyle(NoktaPalette.red)
                }

                if vm.contratos.isEmpty {
                    Text(vm.isLoading ? "Cargando…" : "Sin contratos generados todavía")
                        .font(.system(size: 13)).foregroundStyle(NoktaPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(40)
                } else {
                    VStack(spacing: 0) {
                        headerRow
                        ForEach(vm.contratos) { c in
                            row(c)
                            if c.id != vm.contratos.last?.id { Divider().overlay(NoktaPalette.border) }
                        }
                    }
                    .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
                }
            }
            .padding(32)
        }
        .background(NoktaPalette.bg)
        .task { await vm.load() }
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
            ElegirTrabajoSheet(trabajos: vm.trabajos) { t in
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

    private func generar(_ datos: ContratoParaPDF) async {
        do {
            let url = try await ContratoGenerator.generar(datos)
            previewItem = ContratoPreviewItem(url: url, title: "Contrato · \(datos.clienteNombre)")
            await vm.load()
        } catch {
            contratoErrorMessage = error.localizedDescription
        }
    }

    private var headerRow: some View {
        HStack {
            Text("CLIENTE").frame(maxWidth: .infinity, alignment: .leading)
            Text("SERVICIO").frame(maxWidth: .infinity, alignment: .leading)
            Text("TOTAL").frame(maxWidth: .infinity, alignment: .leading)
            Text("FECHA DEL CONTRATO").frame(maxWidth: .infinity, alignment: .leading)
            Text("").frame(width: 90)
        }
        .font(NoktaFont.tableHead).foregroundStyle(NoktaPalette.muted)
        .padding(.horizontal, 20).padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(NoktaPalette.border).frame(height: 1) }
    }

    private func row(_ c: NoktaContrato) -> some View {
        HStack {
            Text(c.clienteNombre ?? "—").frame(maxWidth: .infinity, alignment: .leading)
            Text(c.servicioTipo ?? "—").foregroundStyle(NoktaPalette.muted).frame(maxWidth: .infinity, alignment: .leading)
            Text("$" + String(format: "%.2f", c.total)).frame(maxWidth: .infinity, alignment: .leading)
            Text(c.fechaContrato ?? "—").foregroundStyle(NoktaPalette.muted).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button("👁") { Task { await ver(c) } }.buttonStyle(.glass)
                Button(role: .destructive) { eliminarConfirm = c.id } label: { Image(systemName: "trash") }
                    .buttonStyle(.glass)
            }.frame(width: 90)
        }
        .font(.system(size: 13)).foregroundStyle(NoktaPalette.cream)
        .padding(.horizontal, 20).padding(.vertical, 12)
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

/// Trabajo picker for "+ Nuevo contrato" — lets you start a contract from
/// the Contratos page instead of having to open the trabajo first.
private struct ElegirTrabajoSheet: View {
    let trabajos: [NoktaTrabajo]
    let onElegir: (NoktaTrabajo) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var busqueda = ""

    private var filtrados: [NoktaTrabajo] {
        guard !busqueda.trimmingCharacters(in: .whitespaces).isEmpty else { return trabajos }
        return trabajos.filter { $0.cliente.localizedCaseInsensitiveContains(busqueda) || $0.servicio.localizedCaseInsensitiveContains(busqueda) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Elige el trabajo").font(.system(size: 16, weight: .semibold)).foregroundStyle(NoktaPalette.cream)
            TextField("Buscar cliente o servicio", text: $busqueda).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(spacing: 0) {
                    if filtrados.isEmpty {
                        Text("Sin resultados").font(.system(size: 13)).foregroundStyle(NoktaPalette.muted)
                            .frame(maxWidth: .infinity, alignment: .center).padding(24)
                    }
                    ForEach(filtrados, id: \.id) { t in
                        Button { onElegir(t) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.cliente).font(.system(size: 13, weight: .medium)).foregroundStyle(NoktaPalette.cream)
                                    Text(t.servicio).font(.system(size: 11)).foregroundStyle(NoktaPalette.muted)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if t.id != filtrados.last?.id { Divider().overlay(NoktaPalette.border) }
                    }
                }
            }
            .frame(maxHeight: 360)
            .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
            Button("Cancelar") { dismiss() }.buttonStyle(.glass)
        }
        .padding(24)
        .frame(maxWidth: 420)
    }
}
