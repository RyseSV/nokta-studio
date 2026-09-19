import SwiftUI

private struct ServicioLineaForm: Identifiable {
    let id = UUID()
    var descripcion = ""
    var monto = ""
}

private struct PreviewItem: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

@Observable
final class DocumentosViewModel {
    var tipo = "cotizacion" {
        didSet {
            if tipo != oldValue { historial = [] }
        }
    }
    var clienteNombre = ""
    var empresa = ""
    var telefono = ""
    var email = ""
    var fechaEmision = Date()
    var notas = ""
    var isSaving = false
    var isRendering = false
    var savedNumero: String?
    var errorMessage: String?
    var historial: [NoktaDocumento] = []
    var historialShown = false

    func guardar(servicios: [(descripcion: String, monto: Double)]) async -> String? {
        errorMessage = nil
        savedNumero = nil
        guard !clienteNombre.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Escribe el nombre del cliente"; return nil }
        guard !servicios.isEmpty, servicios.contains(where: { $0.monto > 0 }) else { errorMessage = "Agrega al menos un servicio con monto"; return nil }

        struct ServicioBody: Encodable { let descripcion: String; let monto: Double }
        struct Body: Encodable {
            let tipo: String, clienteNombre: String, empresa: String, telefono: String, email: String
            let fechaEmision: String, servicios: [ServicioBody], total: Double, notas: String
        }
        struct Resp: Decodable { let ok: Bool?; let numero: String? }

        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let total = servicios.reduce(0.0) { $0 + $1.monto }
        let body = Body(
            tipo: tipo, clienteNombre: clienteNombre, empresa: empresa, telefono: telefono, email: email,
            fechaEmision: f.string(from: fechaEmision),
            servicios: servicios.map { ServicioBody(descripcion: $0.descripcion, monto: $0.monto) },
            total: total, notas: notas
        )
        isSaving = true
        defer { isSaving = false }
        guard let resp: Resp = try? await NoktaAPI.post("/api/documentos", body: body), let numero = resp.numero else {
            errorMessage = "No se pudo guardar el documento"; return nil
        }
        savedNumero = numero
        return numero
    }

    func cargarHistorial() async {
        struct Resp: Decodable { let cotizaciones: [NoktaDocumento]?; let recibos: [NoktaDocumento]? }
        let tipoSolicitado = tipo
        guard let resp: Resp = try? await NoktaAPI.get("/api/documentos"), tipo == tipoSolicitado else { return }
        let docs = tipoSolicitado == "cotizacion" ? (resp.cotizaciones ?? []) : (resp.recibos ?? [])
        historial = clienteNombre.isEmpty ? docs : docs.filter { $0.clienteNombre == clienteNombre }
        historialShown = true
    }

    func eliminar(_ id: String, tipo: String) async {
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp? = try? await NoktaAPI.delete("/api/documentos/\(tipo)/\(id)")
        await cargarHistorial()
    }
}

struct DocumentosView: View {
    @State private var vm = DocumentosViewModel()
    @State private var servicios = [ServicioLineaForm()]
    @State private var previewItem: PreviewItem?
    @State private var eliminarDocConfirm: (id: String, tipo: String)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Documentos").font(NoktaFont.pageTitle).foregroundStyle(NoktaPalette.cream)

                HStack(spacing: 8) {
                    Button("Cotización") { vm.tipo = "cotizacion" }
                        .buttonStyle(.glass).tint(vm.tipo == "cotizacion" ? NoktaPalette.ember : nil)
                    Button("Recibo de pago") { vm.tipo = "recibo" }
                        .buttonStyle(.glass).tint(vm.tipo == "recibo" ? NoktaPalette.ember : nil)
                }

                HStack(alignment: .top, spacing: 20) {
                    formCard
                    if vm.historialShown {
                        historialCard.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NoktaPalette.bg)
        .task(id: vm.tipo) {
            if vm.historialShown { await vm.cargarHistorial() }
        }
        .sheet(item: $previewItem) { item in
            PDFPreviewSheet(url: item.url, title: item.title)
        }
        .alert("¿Eliminar este documento?", isPresented: Binding(get: { eliminarDocConfirm != nil }, set: { if !$0 { eliminarDocConfirm = nil } })) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar", role: .destructive) {
                if let doc = eliminarDocConfirm { Task { await vm.eliminar(doc.id, tipo: doc.tipo) } }
            }
        }
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            field("Nombre del cliente") { TextField("Nombre del cliente", text: $vm.clienteNombre).textFieldStyle(.plain) }
            field("Empresa (opcional)") { TextField("Nombre de empresa", text: $vm.empresa).textFieldStyle(.plain) }
            HStack {
                field("Teléfono") { TextField("+503 0000-0000", text: $vm.telefono).textFieldStyle(.plain) }
                field("Email") { TextField("cliente@correo.com", text: $vm.email).textFieldStyle(.plain) }
            }
            DatePicker("Fecha emisión", selection: $vm.fechaEmision, displayedComponents: .date)

            Divider().overlay(NoktaPalette.border)

            Text("SERVICIOS").font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted)
            ForEach($servicios) { $linea in
                HStack {
                    TextField("Descripción del servicio", text: $linea.descripcion).textFieldStyle(.plain)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: NoktaRadius.button))
                    TextField("0.00", text: $linea.monto).textFieldStyle(.plain)
                        .frame(width: 90)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: NoktaRadius.button))
                    if servicios.count > 1 {
                        Button { servicios.removeAll { $0.id == linea.id } } label: { Image(systemName: "xmark") }
                            .buttonStyle(.glass)
                    }
                }
            }
            Button("+ Agregar línea") { servicios.append(ServicioLineaForm()) }
                .buttonStyle(.glass)

            HStack {
                Spacer()
                Text("Total: ").font(.system(size: 14))
                Text("$" + String(format: "%.2f", totalServicios)).font(.system(size: 15, weight: .semibold)).foregroundStyle(NoktaPalette.ember)
            }

            field("Notas / Condiciones") { TextField("Condiciones de pago, validez, etc.", text: $vm.notas, axis: .vertical).textFieldStyle(.plain) }

            if let errorMessage = vm.errorMessage {
                Text(errorMessage).font(.system(size: 12)).foregroundStyle(NoktaPalette.red)
            }
            if let numero = vm.savedNumero {
                Text("✓ Documento guardado: \(numero)").font(.system(size: 12)).foregroundStyle(NoktaPalette.green)
            }

            HStack {
                Button("Guardar documento") { Task { _ = await vm.guardar(servicios: serviciosValidos) } }
                    .buttonStyle(.glassProminent).tint(NoktaPalette.ember)
                    .disabled(vm.isSaving)
                Button("👁 Vista previa") { Task { await previsualizar() } }
                    .buttonStyle(.glass)
                    .disabled(vm.isRendering)
                Button("📂 Historial") { Task { await vm.cargarHistorial() } }
                    .buttonStyle(.glass)
            }
        }
        .padding(20)
        .frame(width: 420, alignment: .leading)
        .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
    }

    private var historialCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("HISTORIAL DE DOCUMENTOS").font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted).padding(16)
            if vm.historial.isEmpty {
                Text("Sin documentos").font(.system(size: 13)).foregroundStyle(NoktaPalette.muted)
                    .frame(maxWidth: .infinity, alignment: .center).padding(24)
            } else {
                ForEach(vm.historial, id: \.id) { d in
                    HStack {
                        Text(d.numero).frame(maxWidth: .infinity, alignment: .leading)
                        Text(d.clienteNombre).foregroundStyle(NoktaPalette.muted).frame(maxWidth: .infinity, alignment: .leading)
                        Text("$" + String(format: "%.2f", d.total ?? 0)).frame(maxWidth: .infinity, alignment: .leading)
                        Button { eliminarDocConfirm = (id: d.id, tipo: vm.tipo) } label: { Image(systemName: "trash") }
                            .buttonStyle(.glass)
                    }
                    .font(.system(size: 13)).foregroundStyle(NoktaPalette.cream)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    if d.id != vm.historial.last?.id { Divider().overlay(NoktaPalette.border) }
                }
            }
        }
        .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted)
            content()
                .padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(NoktaPalette.cream)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: NoktaRadius.button))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var serviciosValidos: [(descripcion: String, monto: Double)] {
        servicios.map { ($0.descripcion, Double($0.monto) ?? 0) }
    }

    private var totalServicios: Double {
        serviciosValidos.reduce(0) { $0 + $1.monto }
    }

    private func previsualizar() async {
        vm.errorMessage = nil
        guard !vm.clienteNombre.trimmingCharacters(in: .whitespaces).isEmpty else { vm.errorMessage = "Escribe el nombre del cliente"; return }
        vm.isRendering = true
        defer { vm.isRendering = false }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let doc = DocumentoParaPDF(
            numero: vm.savedNumero ?? "PREVIEW", tipo: vm.tipo, clienteNombre: vm.clienteNombre,
            empresa: vm.empresa.isEmpty ? nil : vm.empresa, telefono: vm.telefono.isEmpty ? nil : vm.telefono,
            email: vm.email.isEmpty ? nil : vm.email, fechaEmision: f.string(from: vm.fechaEmision),
            servicios: serviciosValidos, notas: vm.notas.isEmpty ? nil : vm.notas
        )
        let html = PDFTemplates.documento(doc)
        do {
            let url = try await PDFRenderer().renderToPDF(html: html, suggestedName: doc.fileName)
            previewItem = PreviewItem(url: url, title: vm.tipo == "cotizacion" ? "Cotización" : "Recibo")
        } catch {
            vm.errorMessage = error.localizedDescription
        }
    }
}
