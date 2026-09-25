import SwiftUI

/// Port of admin.html's "Mi equipo" section (NEGOCIO group) — team members'
/// pay records (not login accounts, see UsuariosView for those).
@Observable
final class EquipoViewModel {
    var miembros: [NoktaEquipo] = []
    var isLoading = true
    var errorMessage: String?

    func load() async {
        isLoading = true
        defer { isLoading = false }
        if let m: [NoktaEquipo] = try? await NoktaAPI.get("/api/equipo") { miembros = m }
    }

    /// Nil means the server confirmed the save; an error keeps the form open.
    func guardar(_ form: EquipoForm) async -> String? {
        struct Body: Encodable { let nombre, rol, tipo: String; let comision, pagado, pendiente: Double }
        struct Resp: Decodable { let ok: Bool? }
        let body = Body(nombre: form.nombre, rol: form.rol, tipo: form.tipo, comision: form.comision, pagado: form.pagado, pendiente: form.pendiente)
        do {
            let response: Resp
            if let id = form.id {
                response = try await NoktaAPI.put("/api/equipo/\(id)", body: body)
            } else {
                response = try await NoktaAPI.post("/api/equipo", body: body)
            }
            guard response.ok == true else { return "El servidor no confirmó el guardado. Revisa el estado antes de reintentar." }
            await load()
            return nil
        } catch {
            return "No se pudo confirmar el guardado. \(error.localizedDescription)"
        }
    }

    func eliminar(_ id: String) async {
        struct Resp: Decodable { let ok: Bool? }
        errorMessage = nil
        do {
            let response: Resp = try await NoktaAPI.delete("/api/equipo/\(id)")
            guard response.ok == true else {
                errorMessage = "El servidor no confirmó la eliminación. Actualiza la lista antes de reintentar."
                return
            }
            miembros.removeAll { $0.id == id }
        } catch {
            errorMessage = "No se pudo confirmar la eliminación. \(error.localizedDescription)"
        }
    }
}

struct EquipoForm: Identifiable {
    var id: String?
    var nombre = ""
    var rol = ""
    var tipo = "fijo"
    var comision: Double = 0
    var pagado: Double = 0
    var pendiente: Double = 0

    init() {}
    init(_ m: NoktaEquipo) {
        id = m.id; nombre = m.nombre ?? ""; rol = m.rol ?? ""; tipo = m.tipo ?? "fijo"
        comision = m.comision ?? 0; pagado = m.pagado ?? 0; pendiente = m.pendiente ?? 0
    }
}

struct EquipoView: View {
    @State private var vm = EquipoViewModel()
    @State private var editForm: EquipoForm?
    @State private var eliminarConfirm: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Mi equipo").font(NoktaFont.pageTitle).foregroundStyle(NoktaPalette.cream)
                    Spacer()
                    Button("＋ Agregar miembro") { editForm = EquipoForm() }
                        .buttonStyle(.glassProminent).tint(NoktaPalette.ember)
                }

                if let error = vm.errorMessage {
                    Text(error).font(.system(size: 12)).foregroundStyle(NoktaPalette.red)
                }

                if vm.miembros.isEmpty {
                    Text(vm.isLoading ? "Cargando…" : "No hay miembros registrados")
                        .font(.system(size: 13)).foregroundStyle(NoktaPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(40)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                        ForEach(vm.miembros) { m in card(m) }
                    }
                }
            }
            .padding(32)
        }
        .background(NoktaPalette.bg)
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(item: $editForm) { form in
            EquipoFormSheet(form: form) { updated in
                await vm.guardar(updated)
            }
        }
        .alert("¿Eliminar este miembro?", isPresented: Binding(get: { eliminarConfirm != nil }, set: { if !$0 { eliminarConfirm = nil } })) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar", role: .destructive) {
                if let id = eliminarConfirm { Task { await vm.eliminar(id) } }
            }
        }
    }

    private func card(_ m: NoktaEquipo) -> some View {
        HStack(spacing: 12) {
            Text(String((m.nombre ?? "?").prefix(1)).uppercased())
                .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(NoktaPalette.ember, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(m.nombre ?? "—").font(.system(size: 13, weight: .medium)).foregroundStyle(NoktaPalette.cream)
                Text(m.rol ?? "—").font(.system(size: 11)).foregroundStyle(NoktaPalette.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Pagado: $" + String(format: "%.2f", m.pagado ?? 0)).font(.system(size: 11)).foregroundStyle(NoktaPalette.green)
                Text("Pendiente: $" + String(format: "%.2f", m.pendiente ?? 0)).font(.system(size: 11)).foregroundStyle(NoktaPalette.yellow)
            }
            Button { editForm = EquipoForm(m) } label: { Image(systemName: "pencil") }.buttonStyle(.glass)
            Button(role: .destructive) { eliminarConfirm = m.id } label: { Image(systemName: "trash") }.buttonStyle(.glass)
        }
        .padding(14)
        .glassEffect(.regular.tint(NoktaPalette.card), in: RoundedRectangle(cornerRadius: NoktaRadius.card))
    }
}

private struct EquipoFormSheet: View {
    @State var form: EquipoForm
    let onGuardar: (EquipoForm) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(form.id == nil ? "Nuevo miembro" : "Editar miembro").font(.system(size: 16, weight: .semibold)).foregroundStyle(NoktaPalette.cream)
            TextField("Nombre", text: $form.nombre).textFieldStyle(.roundedBorder)
            TextField("Rol (Fotógrafo, editor...)", text: $form.rol).textFieldStyle(.roundedBorder)
            Picker("Tipo de pago", selection: $form.tipo) {
                Text("Fijo por evento").tag("fijo")
                Text("Comisión %").tag("comision")
            }.pickerStyle(.segmented)
            HStack(spacing: 10) {
                labeled("Comisión % / Monto fijo") { TextField("0", value: $form.comision, format: .number).textFieldStyle(.roundedBorder) }
                labeled("Pagado ($)") { TextField("0", value: $form.pagado, format: .number).textFieldStyle(.roundedBorder) }
                labeled("Pendiente ($)") { TextField("0", value: $form.pendiente, format: .number).textFieldStyle(.roundedBorder) }
            }
            if let errorMessage {
                Text(errorMessage).font(.system(size: 12)).foregroundStyle(NoktaPalette.red)
            }
            HStack {
                Button("Cancelar") { dismiss() }.disabled(isSaving)
                Spacer()
                Button(isSaving ? "Guardando…" : "✓ Guardar") { Task { await guardar() } }
                    .buttonStyle(.glassProminent).tint(NoktaPalette.ember)
                    .disabled(isSaving || form.nombre.trimmingCharacters(in: .whitespaces).isEmpty || form.rol.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
        .interactiveDismissDisabled(isSaving)
    }

    private func guardar() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = await onGuardar(form)
        if errorMessage == nil { dismiss() }
    }

    private func labeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10)).foregroundStyle(NoktaPalette.muted)
            content()
        }
    }
}
