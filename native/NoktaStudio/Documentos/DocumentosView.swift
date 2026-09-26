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
            if tipo != oldValue { historial = []; savedNumero = nil }
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
    @State private var aparecio = false
    @State private var ancho: CGFloat = 1000

    private var ancha: Bool { ancho >= 860 }
    private var esCot: Bool { vm.tipo == "cotizacion" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                NoktaEncabezado(titulo: "Documentos", subtitulo: "Cotizaciones y recibos con tu diseño; el PDF se arma mientras escribes.") {
                    NoktaChips(opciones: [("cotizacion", "Cotización"), ("recibo", "Recibo de pago")], seleccion: $vm.tipo)
                }
                .noktaEntrada(aparecio, 0)

                let layout = ancha
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: 28))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: 28))
                layout {
                    formulario
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .noktaEntrada(aparecio, 1)
                    columnaPrevia
                        .frame(width: ancha ? 340 : nil)
                        .frame(maxWidth: ancha ? 340 : .infinity)
                        .noktaEntrada(aparecio, 2)
                }
            }
            .padding(ancho < 600 ? 20 : 36)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NoktaTheme.fondo)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { ancho = $0 }
        .onAppear { withAnimation(.spring(duration: 0.6, bounce: 0.12)) { aparecio = true } }
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

    // MARK: Formulario

    private var formulario: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                CampoDoc(esCot ? "Para (cliente)" : "Cliente") {
                    TextField("", text: $vm.clienteNombre, prompt: Text("Nombre del cliente").foregroundStyle(NoktaTheme.textoTenue))
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12, alignment: .top)], alignment: .leading, spacing: 14) {
                    CampoDoc("Empresa") { TextField("", text: $vm.empresa, prompt: Text("Opcional").foregroundStyle(NoktaTheme.textoTenue)) }
                    CampoDoc("Email") { TextField("", text: $vm.email, prompt: Text("cliente@correo.com").foregroundStyle(NoktaTheme.textoTenue)) }
                    CampoDoc("Teléfono") { TextField("", text: $vm.telefono, prompt: Text("+503 0000-0000").foregroundStyle(NoktaTheme.textoTenue)) }
                    CampoDoc("Fecha de emisión") {
                        DatePicker("", selection: $vm.fechaEmision, displayedComponents: .date)
                            .labelsHidden().datePickerStyle(.compact)
                            .environment(\.locale, Locale(identifier: "es"))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    EtiquetaDoc("Conceptos")
                    Spacer()
                    Text("Total " + NoktaFormato.dinero(totalServicios))
                        .font(NoktaFont.poppins(12, .medium)).foregroundStyle(NoktaTheme.marca)
                        .contentTransition(.numericText(value: totalServicios))
                        .animation(.spring(duration: 0.4), value: totalServicios)
                }
                ForEach($servicios) { $linea in
                    HStack(spacing: 10) {
                        CajaDoc {
                            TextField("", text: $linea.descripcion, prompt: Text("Describe el servicio…").foregroundStyle(NoktaTheme.textoTenue))
                        }
                        CajaDoc {
                            HStack(spacing: 4) {
                                Text("$").foregroundStyle(NoktaTheme.textoSuave)
                                TextField("", text: $linea.monto, prompt: Text("0.00").foregroundStyle(NoktaTheme.textoTenue))
                                    #if os(iOS)
                                    .keyboardType(.decimalPad)
                                    #endif
                            }
                        }
                        .frame(width: 120)
                        Button {
                            withAnimation(.spring(duration: 0.3)) { servicios.removeAll { $0.id == linea.id } }
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                                .foregroundStyle(NoktaTheme.textoTenue)
                                .frame(width: 30, height: 30)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .opacity(servicios.count > 1 ? 1 : 0)
                        .disabled(servicios.count <= 1)
                        .help("Quitar concepto")
                    }
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -8)), removal: .opacity))
                }
                Button {
                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) { servicios.append(ServicioLineaForm()) }
                } label: {
                    Label("Agregar concepto", systemImage: "plus")
                        .font(NoktaFont.poppins(12, .medium)).foregroundStyle(NoktaTheme.marca)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }

            CampoDoc("Notas y condiciones") {
                TextField("", text: $vm.notas, prompt: Text(esCot ? "Ej: 50% de anticipo para iniciar, válida 30 días…" : "Ej: Pagado por transferencia…").foregroundStyle(NoktaTheme.textoTenue), axis: .vertical)
                    .lineLimit(2...5)
            }
        }
    }

    // MARK: Vista previa + acciones

    private var columnaPrevia: some View {
        VStack(alignment: .leading, spacing: 14) {
            EtiquetaDoc("Así sale el PDF")
            HojaDocumento(
                esCot: esCot,
                numero: vm.savedNumero ?? (esCot ? "COT-…" : "REC-…"),
                fecha: fechaTexto,
                cliente: vm.clienteNombre,
                contacto: [vm.empresa, vm.email, vm.telefono].filter { !$0.isEmpty },
                lineas: serviciosValidos.filter { !$0.descripcion.isEmpty || $0.monto > 0 },
                total: totalServicios,
                notas: vm.notas
            )
            .animation(.spring(duration: 0.4), value: esCot)

            if let errorMessage = vm.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.error)
            }
            if let numero = vm.savedNumero {
                Label("Guardado como \(numero)", systemImage: "checkmark.circle")
                    .font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.exito)
            }

            Button { Task { await guardarYVer() } } label: {
                ZStack {
                    if vm.isSaving || vm.isRendering { ProgressView().controlSize(.small).tint(.white) }
                    else { Text("Guardar y descargar PDF") }
                }
                .font(NoktaFont.poppins(13, .medium)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 46)
                .background(
                    LinearGradient(colors: [Color(red: 0.855, green: 0.478, blue: 0.282), Color(red: 0.72, green: 0.32, blue: 0.157)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
                .shadow(color: NoktaTheme.marca.opacity(0.35), radius: 12, y: 6)
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(vm.isSaving || vm.isRendering)
            .keyboardShortcut(.return, modifiers: .command)

            HStack(spacing: 8) {
                Button { Task { await previsualizar() } } label: { Label("Solo ver", systemImage: "eye") }
                    .buttonStyle(NoktaBotonSecundario())
                    .disabled(vm.isRendering)
                Button {
                    if vm.historialShown { withAnimation { vm.historialShown = false } }
                    else { Task { await vm.cargarHistorial() } }
                } label: { Label(vm.historialShown ? "Ocultar historial" : "Historial", systemImage: "clock.arrow.circlepath") }
                    .buttonStyle(NoktaBotonSecundario())
            }

            if vm.historialShown { historial.transition(.opacity.combined(with: .offset(y: 8))) }
        }
        .animation(.spring(duration: 0.35), value: vm.historialShown)
    }

    private var historial: some View {
        VStack(alignment: .leading, spacing: 8) {
            EtiquetaDoc(esCot ? "Cotizaciones anteriores" : "Recibos anteriores").padding(.top, 6)
            if vm.historial.isEmpty {
                Text(vm.clienteNombre.isEmpty ? "Sin documentos todavía" : "Sin documentos de \(vm.clienteNombre)")
                    .font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoTenue)
            }
            ForEach(vm.historial, id: \.id) { d in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.clienteNombre).font(NoktaFont.poppins(12.5, .medium)).foregroundStyle(NoktaTheme.texto).lineLimit(1)
                        Text("\(d.numero) · \(d.fechaEmision ?? "")").font(NoktaFont.poppins(10.5)).foregroundStyle(NoktaTheme.textoTenue).lineLimit(1)
                    }
                    Spacer()
                    Text(NoktaFormato.dinero(d.total ?? 0)).font(NoktaFont.poppins(13)).foregroundStyle(NoktaTheme.texto)
                    Button { eliminarDocConfirm = (id: d.id, tipo: vm.tipo) } label: {
                        Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(NoktaTheme.textoTenue)
                            .frame(width: 26, height: 26).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help("Eliminar")
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(NoktaTheme.superficie, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(NoktaTheme.borde))
            }
        }
    }

    private var fechaTexto: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "es"); f.dateFormat = "d MMM yyyy"
        return f.string(from: vm.fechaEmision).replacingOccurrences(of: ".", with: "")
    }

    private var serviciosValidos: [(descripcion: String, monto: Double)] {
        servicios.map { ($0.descripcion, Double($0.monto.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")) ?? 0) }
    }

    private var totalServicios: Double {
        serviciosValidos.reduce(0) { $0 + $1.monto }
    }

    private func guardarYVer() async {
        guard await vm.guardar(servicios: serviciosValidos) != nil else { return }
        await previsualizar()
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
            previewItem = PreviewItem(url: url, title: esCot ? "Cotización" : "Recibo")
        } catch {
            vm.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Piezas

private struct EtiquetaDoc: View {
    let texto: String
    init(_ texto: String) { self.texto = texto }
    var body: some View {
        Text(texto.uppercased()).font(NoktaFont.poppins(10, .medium)).tracking(1.4).foregroundStyle(NoktaTheme.textoTenue)
    }
}

private struct CajaDoc<C: View>: View {
    @ViewBuilder var contenido: () -> C
    var body: some View {
        contenido()
            .textFieldStyle(.plain)
            .font(NoktaFont.poppins(13))
            .foregroundStyle(NoktaTheme.texto)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(NoktaTheme.superficie, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(NoktaTheme.borde))
    }
}

private struct CampoDoc<C: View>: View {
    let titulo: String
    @ViewBuilder var contenido: () -> C
    init(_ titulo: String, @ViewBuilder contenido: @escaping () -> C) { self.titulo = titulo; self.contenido = contenido }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EtiquetaDoc(titulo)
            CajaDoc(contenido: contenido)
        }
    }
}

/// Réplica en vivo del PDF "tarjeta cálida" (colores fijos: es papel).
private struct HojaDocumento: View {
    let esCot: Bool
    let numero: String
    let fecha: String
    let cliente: String
    let contacto: [String]
    let lineas: [(descripcion: String, monto: Double)]
    let total: Double
    let notas: String

    private let crema = Color(red: 0.953, green: 0.933, blue: 0.902)
    private let crema2 = Color(red: 0.98, green: 0.969, blue: 0.949)
    private let tinta = Color(red: 0.11, green: 0.11, blue: 0.10)
    private let naranja = Color(red: 0.72, green: 0.32, blue: 0.157)
    private let verde = Color(red: 0.18, green: 0.545, blue: 0.353)

    private static let logo: Image? = {
        guard let url = Bundle.main.url(forResource: "nokta_lockup_color_transparent", withExtension: "png") else { return nil }
        #if os(macOS)
        return NSImage(contentsOf: url).map { Image(nsImage: $0) }
        #else
        return UIImage(contentsOfFile: url.path).map { Image(uiImage: $0) }
        #endif
    }()

    private func bloque(_ t: String, _ p: String, _ s: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(NoktaFont.poppins(6.5, .semibold)).tracking(1.2).foregroundStyle(naranja)
            Text(p.isEmpty ? "—" : p).font(NoktaFont.poppins(9, .medium)).foregroundStyle(p.isEmpty ? tinta.opacity(0.3) : tinta).lineLimit(1)
            if let s, !s.isEmpty { Text(s).font(NoktaFont.poppins(7.5)).foregroundStyle(.gray).lineLimit(1) }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .topLeading)
        .background(crema2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    var body: some View {
        let partes = NoktaFormato.dinero(total).replacingOccurrences(of: "$", with: "").split(separator: ".", maxSplits: 1)
        let entero = partes.first.map(String.init) ?? "0"
        let dec = partes.count > 1 ? String(partes[1]) : "00"
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    if let logo = Self.logo { logo.resizable().scaledToFit().frame(height: 26) }
                    else { Text("nokta").font(NoktaFont.poppins(14, .medium)).foregroundStyle(tinta) }
                    Spacer()
                    Text(esCot ? "COTIZACIÓN" : "PAGADO")
                        .font(NoktaFont.poppins(6.5, .semibold)).tracking(1.2)
                        .foregroundStyle(esCot ? naranja : verde)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(esCot ? crema : Color(red: 0.894, green: 0.949, blue: 0.918), in: Capsule())
                        .contentTransition(.opacity)
                }
                Text(esCot ? "Propuesta" : "Recibo de pago")
                    .font(NoktaFont.poppins(21, .light)).tracking(-0.8).foregroundStyle(tinta)
                    .padding(.top, 16)
                    .contentTransition(.opacity)
                Text("\(numero) · \(fecha)").font(NoktaFont.poppins(7.5)).foregroundStyle(.gray).padding(.top, 2)
                HStack(spacing: 6) {
                    bloque(esCot ? "PARA" : "CLIENTE", cliente, contacto.first)
                    bloque("DETALLES", "Emitido \(fecha)", "\(lineas.count) concepto\(lineas.count == 1 ? "" : "s")")
                }
                .padding(.top, 12)
                VStack(spacing: 0) {
                    ForEach(Array(lineas.enumerated()), id: \.offset) { _, l in
                        HStack {
                            Text(l.descripcion.isEmpty ? "—" : l.descripcion).foregroundStyle(tinta.opacity(0.6)).lineLimit(1)
                            Spacer()
                            Text(NoktaFormato.dinero(l.monto)).foregroundStyle(tinta).fontWeight(.medium)
                        }
                        .font(NoktaFont.poppins(8))
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color(red: 0.9, green: 0.875, blue: 0.83)).frame(height: 0.6)
                        }
                        .transition(.opacity.combined(with: .offset(y: 4)))
                    }
                }
                .padding(.top, 8)
                HStack(alignment: .firstTextBaseline) {
                    Text("Total").font(NoktaFont.poppins(8)).foregroundStyle(.gray)
                    Spacer()
                    (Text("$" + entero) + Text(".").foregroundStyle(naranja) + Text(dec))
                        .font(NoktaFont.poppins(24, .light)).tracking(-1).foregroundStyle(tinta)
                        .contentTransition(.numericText(value: total))
                }
                .padding(.top, 10)
                if !notas.isEmpty {
                    Text(notas).font(NoktaFont.poppins(7.5)).foregroundStyle(.gray).lineLimit(3)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(crema2, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .padding(.top, 10)
                }
                Text(esCot ? "Gracias por considerar a Nokta. ✦" : "Gracias por confiar en Nokta. ✦")
                    .font(NoktaFont.poppins(7.5)).foregroundStyle(.gray).padding(.top, 12)
            }
            .padding(EdgeInsets(top: 18, leading: 22, bottom: 16, trailing: 18))
            .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
                    .fill(LinearGradient(colors: [Color(red: 0.816, green: 0.404, blue: 0.227), naranja], startPoint: .top, endPoint: .bottom))
                    .frame(width: 4)
            }
            .shadow(color: Color(red: 0.24, green: 0.16, blue: 0.08).opacity(0.18), radius: 12, y: 8)
            Text("Nokta Studio · contacto@noktastudio.com").font(NoktaFont.poppins(6.5)).foregroundStyle(Color(red: 0.66, green: 0.62, blue: 0.57))
        }
        .padding(16)
        .background(crema, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
        .animation(.spring(duration: 0.35), value: lineas.count)
        .animation(.spring(duration: 0.4), value: total)
    }
}
