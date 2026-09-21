import SwiftUI
import PhotosUI

/// Port of admin.html's "Usuarios" section — admin-only (see RootView's
/// visibleGroups), manages the login accounts for the panel itself, not
/// business data. Photo upload reuses the same /api/usuarios/:id/foto route
/// the web's canvas-resize flow posts to.
@Observable
final class UsuariosViewModel {
    var usuarios: [NoktaUsuario] = []
    var isLoading = true

    func load() async {
        isLoading = true
        defer { isLoading = false }
        if let u: [NoktaUsuario] = try? await NoktaAPI.get("/api/usuarios") { usuarios = u }
    }

    /// Returns an error message on failure, nil on success.
    func guardar(_ form: UsuarioForm) async -> String? {
        struct Resp: Decodable { let ok: Bool?; let error: String?; let usuario: NoktaUsuario? }
        if let id = form.id {
            struct Body: Encodable { let nombre, username, role, icono: String; let password: String? }
            let body = Body(nombre: form.nombre, username: form.username, role: form.role, icono: form.icono, password: form.password.isEmpty ? nil : form.password)
            guard let resp: Resp = try? await NoktaAPI.put("/api/usuarios/\(id)", body: body) else { return "No se pudo guardar" }
            if resp.ok != true { return resp.error ?? "No se pudo guardar" }
        } else {
            struct Body: Encodable { let nombre, username, password, role, icono: String }
            guard !form.password.isEmpty else { return "La contraseña es requerida" }
            let body = Body(nombre: form.nombre, username: form.username, password: form.password, role: form.role, icono: form.icono)
            guard let resp: Resp = try? await NoktaAPI.post("/api/usuarios", body: body) else { return "No se pudo guardar" }
            if resp.usuario == nil { return resp.error ?? "No se pudo guardar" }
        }
        await load()
        return nil
    }

    func eliminar(_ id: String) async {
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp? = try? await NoktaAPI.delete("/api/usuarios/\(id)")
        usuarios.removeAll { $0._id == id }
    }

    func subirFoto(_ id: String, base64: String) async -> String? {
        struct Body: Encodable { let base64: String }
        struct Resp: Decodable { let ok: Bool?; let url: String?; let error: String? }
        guard let resp: Resp = try? await NoktaAPI.post("/api/usuarios/\(id)/foto", body: Body(base64: base64)) else { return "Error de conexión" }
        if resp.ok != true { return resp.error ?? "Error al subir foto" }
        await load()
        return nil
    }
}

struct UsuarioForm: Identifiable {
    var id: String?
    var nombre = ""
    var username = ""
    var password = ""
    var role = "editor"
    var icono = "dark"
    var foto: String?

    init() {}
    init(_ u: NoktaUsuario) {
        id = u._id; nombre = u.nombre ?? ""; username = u.username; role = u.role
        icono = u.icono ?? "dark"; foto = u.foto
    }
}

struct UsuariosView: View {
    @State private var vm = UsuariosViewModel()
    @State private var editForm: UsuarioForm?
    @State private var eliminarConfirm: NoktaUsuario?

    private static let roleLabels = ["admin": "Administrador", "editor": "Editor"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Usuarios").font(NoktaFont.pageTitle).foregroundStyle(NoktaPalette.cream)
                    Spacer()
                    Button("＋ Nuevo usuario") { editForm = UsuarioForm() }
                        .buttonStyle(.glassProminent).tint(NoktaPalette.ember)
                }

                if vm.usuarios.isEmpty {
                    Text(vm.isLoading ? "Cargando…" : "No hay usuarios")
                        .font(.system(size: 13)).foregroundStyle(NoktaPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(40)
                } else {
                    VStack(spacing: 0) {
                        ForEach(vm.usuarios) { u in
                            row(u)
                            if u._id != vm.usuarios.last?._id { Divider().overlay(NoktaPalette.border) }
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
        .sheet(item: $editForm) { form in
            UsuarioFormSheet(form: form, vm: vm) { editForm = nil }
        }
        .alert("¿Eliminar este usuario?", isPresented: Binding(get: { eliminarConfirm != nil }, set: { if !$0 { eliminarConfirm = nil } })) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar", role: .destructive) {
                if let u = eliminarConfirm { Task { await vm.eliminar(u._id) } }
            }
        }
    }

    private func row(_ u: NoktaUsuario) -> some View {
        HStack(spacing: 12) {
            avatar(u).frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(u.nombre ?? "—").font(.system(size: 13, weight: .medium)).foregroundStyle(NoktaPalette.cream)
                Text("@" + u.username).font(.system(size: 11, design: .monospaced)).foregroundStyle(NoktaPalette.muted)
            }
            Spacer()
            Text(Self.roleLabels[u.role] ?? u.role)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(u.role == "admin" ? Color.blue : NoktaPalette.green)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background((u.role == "admin" ? Color.blue : NoktaPalette.green).opacity(0.15), in: Capsule())
            if u.role != "admin" {
                Button(role: .destructive) { eliminarConfirm = u } label: { Image(systemName: "trash") }.buttonStyle(.glass)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { editForm = UsuarioForm(u) }
    }

    @ViewBuilder
    private func avatar(_ u: NoktaUsuario) -> some View {
        if let foto = u.foto, let url = URL(string: foto) {
            AsyncImage(url: url) { $0.resizable() } placeholder: { Circle().fill(NoktaPalette.ember) }
                .aspectRatio(contentMode: .fill).clipShape(Circle())
        } else {
            ZStack {
                Circle().fill(NoktaPalette.ember)
                Text(String((u.nombre ?? "?").prefix(1)).uppercased()).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            }
        }
    }
}

private struct UsuarioFormSheet: View {
    @State var form: UsuarioForm
    let vm: UsuariosViewModel
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var isUploadingPhoto = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(form.id == nil ? "Nuevo usuario" : "Editar usuario").font(.system(size: 16, weight: .semibold)).foregroundStyle(NoktaPalette.cream)

            if let id = form.id {
                photoPicker(for: id)
            }

            TextField("Nombre", text: $form.nombre).textFieldStyle(.roundedBorder)
            TextField("Usuario", text: $form.username).textFieldStyle(.roundedBorder).autocorrectionDisabled()
            SecureField(form.id == nil ? "Contraseña *" : "Dejar vacío para no cambiar", text: $form.password).textFieldStyle(.roundedBorder)
            Picker("Rol", selection: $form.role) {
                Text("Editor").tag("editor")
                Text("Administrador").tag("admin")
            }.pickerStyle(.segmented)
            Picker("Ícono", selection: $form.icono) {
                Text("Oscuro").tag("dark")
                Text("Crema").tag("cream")
            }.pickerStyle(.segmented)

            if let errorMessage {
                Text(errorMessage).font(.system(size: 12)).foregroundStyle(NoktaPalette.red)
            }

            HStack {
                Button("Cancelar") { dismiss() }
                Spacer()
                Button(isSaving ? "Guardando…" : "✓ Guardar") { Task { await guardar() } }
                    .buttonStyle(.glassProminent).tint(NoktaPalette.ember)
                    .disabled(isSaving || form.nombre.trimmingCharacters(in: .whitespaces).isEmpty || form.username.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(maxWidth: 420)
    }

    private func photoPicker(for id: String) -> some View {
        HStack(spacing: 12) {
            Group {
                if let photoData, let img = platformImage(data: photoData) { img.resizable() }
                else if let foto = form.foto, let url = URL(string: foto) {
                    AsyncImage(url: url) { $0.resizable() } placeholder: { Circle().fill(NoktaPalette.ember) }
                } else {
                    ZStack { Circle().fill(NoktaPalette.ember); Text(String(form.nombre.prefix(1)).uppercased()).foregroundStyle(.white) }
                }
            }
            .aspectRatio(contentMode: .fill).frame(width: 56, height: 56).clipShape(Circle())

            PhotosPicker(selection: $photoItem, matching: .images) {
                Text("Cambiar foto").font(.system(size: 12))
            }
            .buttonStyle(.glass)
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
                    photoData = data
                    isUploadingPhoto = true
                    defer { isUploadingPhoto = false }
                    if let err = await vm.subirFoto(id, base64: "data:image/jpeg;base64," + data.base64EncodedString()) {
                        errorMessage = err
                    } else if let updated = vm.usuarios.first(where: { $0._id == id }) {
                        form.foto = updated.foto
                    }
                }
            }
            if isUploadingPhoto { ProgressView().controlSize(.small) }
        }
    }

    private func guardar() async {
        isSaving = true
        defer { isSaving = false }
        if let err = await vm.guardar(form) {
            errorMessage = err
        } else {
            onDone()
        }
    }
}

private func platformImage(data: Data) -> Image? {
    #if os(macOS)
    guard let nsImage = NSImage(data: data) else { return nil }
    return Image(nsImage: nsImage)
    #else
    guard let uiImage = UIImage(data: data) else { return nil }
    return Image(uiImage: uiImage)
    #endif
}
