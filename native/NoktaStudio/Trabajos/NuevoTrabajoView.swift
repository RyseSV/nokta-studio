import SwiftUI

private struct ServicioGroup { let title: String; let servicios: [String] }
private let serviciosPorGrupo: [ServicioGroup] = [
    ServicioGroup(title: "Eventos", servicios: [
        "Fotografía de eventos", "Fotografía corporativa", "Fotografía de producto",
        "Fotografía gastronómica", "Retratos", "Cobertura audiovisual", "Foto + Video", "Clases",
    ]),
    ServicioGroup(title: "Paquetes mensuales", servicios: [
        "Marketing digital", "Gestión de redes", "Community management", "Paquete completo",
    ]),
    ServicioGroup(title: "Edición de video", servicios: ["Edición de video", "Motion graphics", "Reels sueltos"]),
    ServicioGroup(title: "Branding", servicios: ["Identidad visual", "Branding"]),
    ServicioGroup(title: "Web", servicios: ["Diseño y desarrollo web"]),
]

@Observable
final class NuevoTrabajoViewModel {
    var cliente = ""
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
    var errorMessage: String?
    var savedMessage: String?

    var grupo: String { ServicioGrupoMap.grupo(for: servicio) }

    private static let isoDay = DateFormatter.isoDay

    func reset() {
        cliente = ""; servicio = ""; notas = ""
        fecha = Date(); horaInicio = ""; horaFin = ""; lugar = ""; montoA = ""; anticipoA = ""
        empresaB = ""; pagoMensual = ""; fechaInicio = Date(); diaCobro = ""
        cantPiezas = ""; formato = "vertical"; montoC = ""; anticipoC = ""; fechaEntregaC = Date()
        empresaDE = ""; alcance = ""; montoDE = ""; anticipoDE = ""; fechaEntregaDE = Date()
    }

    func guardar() async {
        errorMessage = nil
        savedMessage = nil
        guard !cliente.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Escribe el nombre del cliente"; return
        }
        guard !servicio.isEmpty else { errorMessage = "Selecciona un servicio"; return }

        var fields: [String: AnyEncodableValue] = [
            "cliente": .string(cliente),
            "servicio": .string(servicio),
            "grupo": .string(grupo),
            "grupoNombre": .string(ServicioGrupoMap.nombres[grupo] ?? grupo),
            "notas": .string(notas),
            "estado": .string("pendiente"),
        ]

        switch grupo {
        case "A":
            guard let monto = Double(montoA), monto > 0 else { errorMessage = "Completa el monto"; return }
            let anticipo = Double(anticipoA) ?? 0
            fields["fecha"] = .string(Self.isoDay.string(from: fecha))
            fields["horaInicio"] = .string(horaInicio)
            fields["horaFin"] = .string(horaFin)
            fields["lugar"] = .string(lugar)
            fields["monto"] = .double(monto)
            fields["anticipo"] = .double(anticipo)
            fields["saldo"] = .double(max(0, monto - anticipo))
        case "B":
            guard let pm = Double(pagoMensual), pm > 0 else { errorMessage = "Completa el pago mensual"; return }
            let inicioStr = Self.isoDay.string(from: fechaInicio)
            fields["empresa"] = .string(empresaB)
            fields["pagoMensual"] = .double(pm)
            fields["monto"] = .double(pm)
            fields["fechaInicio"] = .string(inicioStr)
            fields["fecha"] = .string(inicioStr)
            fields["estadoContrato"] = .string("activo")
            if let dia = Int(diaCobro) { fields["diaCobro"] = .int(dia) }
        case "C":
            guard let monto = Double(montoC), monto > 0 else { errorMessage = "Completa el monto"; return }
            let anticipo = Double(anticipoC) ?? 0
            let entregaStr = Self.isoDay.string(from: fechaEntregaC)
            fields["cantPiezas"] = .string(cantPiezas)
            fields["formato"] = .string(formato)
            fields["monto"] = .double(monto)
            fields["anticipo"] = .double(anticipo)
            fields["saldo"] = .double(max(0, monto - anticipo))
            fields["fechaEntrega"] = .string(entregaStr)
            fields["fecha"] = .string(entregaStr)
        default: // D, E
            guard let monto = Double(montoDE), monto > 0 else { errorMessage = "Completa el monto"; return }
            let anticipo = Double(anticipoDE) ?? 0
            let entregaStr = Self.isoDay.string(from: fechaEntregaDE)
            fields["empresa"] = .string(empresaDE)
            fields["alcance"] = .string(alcance)
            fields["monto"] = .double(monto)
            fields["anticipo"] = .double(anticipo)
            fields["saldo"] = .double(max(0, monto - anticipo))
            fields["fechaEntrega"] = .string(entregaStr)
            fields["fecha"] = .string(entregaStr)
        }

        isSaving = true
        defer { isSaving = false }
        do {
            struct Resp: Decodable { let ok: Bool? }
            let _: Resp = try await NoktaAPI.post("/api/trabajos", body: AnyEncodableDict(fields))
            savedMessage = "✓ Trabajo registrado"
            reset()
        } catch {
            errorMessage = error.localizedDescription
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

struct NuevoTrabajoView: View {
    @State private var vm = NuevoTrabajoViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Nuevo trabajo").font(NoktaFont.pageTitle).foregroundStyle(NoktaPalette.cream)

                GlassEffectContainer(spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        field("Cliente") { TextField("Nombre del cliente", text: $vm.cliente).textFieldStyle(.plain) }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("SERVICIO").font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted)
                            Picker("", selection: $vm.servicio) {
                                Text("Selecciona un servicio").tag("")
                                ForEach(serviciosPorGrupo, id: \.title) { group in
                                    Section(group.title) {
                                        ForEach(group.servicios, id: \.self) { s in Text(s).tag(s) }
                                    }
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }

                        if !vm.servicio.isEmpty {
                            grupoFields
                        }

                        field("Notas") { TextField("Notas adicionales", text: $vm.notas, axis: .vertical).textFieldStyle(.plain) }

                        if let error = vm.errorMessage {
                            Text(error).font(.system(size: 13)).foregroundStyle(NoktaPalette.red)
                        }
                        if let saved = vm.savedMessage {
                            Text(saved).font(.system(size: 13)).foregroundStyle(NoktaPalette.green)
                        }

                        Button {
                            Task { await vm.guardar() }
                        } label: {
                            if vm.isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Text("Guardar trabajo")
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .tint(NoktaPalette.ember)
                        .disabled(vm.isSaving)
                    }
                    .padding(20)
                    .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
                }
            }
            .padding(32)
        }
        .background(NoktaPalette.bg)
    }

    @ViewBuilder
    private var grupoFields: some View {
        switch vm.grupo {
        case "A":
            DatePicker("Fecha", selection: $vm.fecha, displayedComponents: .date)
            HStack {
                field("Hora inicio") { TextField("HH:MM", text: $vm.horaInicio).textFieldStyle(.plain) }
                field("Hora fin") { TextField("HH:MM", text: $vm.horaFin).textFieldStyle(.plain) }
            }
            field("Lugar") { TextField("Lugar del evento", text: $vm.lugar).textFieldStyle(.plain) }
            HStack {
                field("Monto ($)") { TextField("0.00", text: $vm.montoA).textFieldStyle(.plain) }
                field("Anticipo ($)") { TextField("0.00", text: $vm.anticipoA).textFieldStyle(.plain) }
            }
        case "B":
            field("Empresa") { TextField("Empresa del cliente", text: $vm.empresaB).textFieldStyle(.plain) }
            HStack {
                field("Pago mensual ($)") { TextField("0.00", text: $vm.pagoMensual).textFieldStyle(.plain) }
                field("Día de cobro") { TextField("1-31", text: $vm.diaCobro).textFieldStyle(.plain) }
            }
            DatePicker("Inicio de contrato", selection: $vm.fechaInicio, displayedComponents: .date)
        case "C":
            HStack {
                field("Piezas") { TextField("ej. 50 fotos", text: $vm.cantPiezas).textFieldStyle(.plain) }
                VStack(alignment: .leading, spacing: 6) {
                    Text("FORMATO").font(NoktaFont.cardLabel).foregroundStyle(NoktaPalette.muted)
                    Picker("", selection: $vm.formato) {
                        Text("Vertical").tag("vertical")
                        Text("Horizontal").tag("horizontal")
                        Text("Ambos").tag("ambos")
                    }
                    .labelsHidden().pickerStyle(.menu)
                }
            }
            DatePicker("Entrega estimada", selection: $vm.fechaEntregaC, displayedComponents: .date)
            HStack {
                field("Monto ($)") { TextField("0.00", text: $vm.montoC).textFieldStyle(.plain) }
                field("Anticipo ($)") { TextField("0.00", text: $vm.anticipoC).textFieldStyle(.plain) }
            }
        default:
            field("Empresa") { TextField("Empresa del cliente", text: $vm.empresaDE).textFieldStyle(.plain) }
            field("Alcance") { TextField("Alcance del proyecto", text: $vm.alcance, axis: .vertical).textFieldStyle(.plain) }
            DatePicker("Entrega estimada", selection: $vm.fechaEntregaDE, displayedComponents: .date)
            HStack {
                field("Monto ($)") { TextField("0.00", text: $vm.montoDE).textFieldStyle(.plain) }
                field("Anticipo ($)") { TextField("0.00", text: $vm.anticipoDE).textFieldStyle(.plain) }
            }
        }
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
}
