import SwiftUI

/// Read-only history of generated contracts — mirrors admin.html's
/// Contratos page. Generation itself lives in TrabajoDetailView, where the
/// client/trabajo context already exists; this is only "control de lo que
/// ya hice" (see the conversation that asked for it).
@Observable
final class ContratosViewModel {
    var contratos: [NoktaContrato] = []
    var isLoading = true

    func load() async {
        isLoading = true
        defer { isLoading = false }
        if let c: [NoktaContrato] = try? await NoktaAPI.get("/api/contratos") {
            contratos = c.sorted { ($0.creado ?? "") > ($1.creado ?? "") }
        }
    }

    func eliminar(_ id: String) async {
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp? = try? await NoktaAPI.delete("/api/contratos/\(id)")
        contratos.removeAll { $0.id == id }
    }
}

private struct ContratoPreviewItem: Identifiable { let id = UUID(); let url: URL; let title: String }

struct ContratosView: View {
    @State private var vm = ContratosViewModel()
    @State private var previewItem: ContratoPreviewItem?
    @State private var previewErrorMessage: String?
    @State private var eliminarConfirm: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Contratos").font(NoktaFont.pageTitle).foregroundStyle(NoktaPalette.cream)
                    Spacer()
                }
                Text("Generados desde el detalle de cada trabajo — aquí solo se listan.")
                    .font(.system(size: 12)).foregroundStyle(NoktaPalette.muted)

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
