import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

/// Port of admin.html's "Usuarios" section — admin-only (see RootView's
/// visibleGroups), manages the login accounts for the panel itself, not
/// business data. Photo upload reuses the same /api/usuarios/:id/foto route
/// the web's canvas-resize flow posts to.
@Observable
final class UsuariosViewModel {
    var usuarios: [NoktaUsuario] = []
    var isLoading = true
    var errorMessage: String?

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
        errorMessage = nil
        do {
            let response: Resp = try await NoktaAPI.delete("/api/usuarios/\(id)")
            guard response.ok == true else {
                errorMessage = "El servidor no confirmó la eliminación. Actualiza la lista antes de reintentar."
                return
            }
            usuarios.removeAll { $0._id == id }
        } catch {
            errorMessage = "No se pudo confirmar la eliminación. \(error.localizedDescription)"
        }
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

/// Iniciales de nombre y apellido ("Carlos Méndez" → "CM", "Gabriel" → "G").
func inicialesNombreApellido(_ nombre: String?) -> String {
    let partes = (nombre ?? "").split(separator: " ").filter { !$0.isEmpty }
    guard let primera = partes.first?.first else { return "·" }
    if partes.count > 1, let ultima = partes.last?.first { return String([primera, ultima]).uppercased() }
    return String(primera).uppercased()
}

private func colorRol(_ rol: String) -> Color { rol == "admin" ? NoktaTheme.marca : NoktaTheme.exito }

/// Foto de la cuenta o, si no tiene, sus iniciales sobre un degradado.
private struct FotoCuenta: View {
    let nombre: String?
    let foto: String?
    var datosLocales: Data? = nil
    var tamanoIniciales: CGFloat = 34

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.82, green: 0.45, blue: 0.27), Color(red: 0.3, green: 0.12, blue: 0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(inicialesNombreApellido(nombre))
                .font(NoktaFont.poppins(tamanoIniciales, .light)).foregroundStyle(.white.opacity(0.92))
            if let datosLocales, let img = platformImage(data: datosLocales) {
                img.resizable().scaledToFill()
            } else if let url = foto.flatMap(URL.init) {
                AsyncImage(url: url) { fase in
                    if let img = fase.image { img.resizable().interpolation(.high).scaledToFill().transition(.opacity) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

/// Usuarios ("gafetes del estudio", 2026-10): cada cuenta es una credencial
/// colgada de su cinta, que se mece; al tocarla se voltea y atrás están su
/// usuario y las acciones.
struct UsuariosView: View {
    @State private var vm = UsuariosViewModel()
    @State private var editForm: UsuarioForm?
    @State private var eliminarConfirm: NoktaUsuario?
    @State private var volteados: Set<String> = []
    @State private var aparecio = false
    @State private var ancho: CGFloat = 1000

    private var subtitulo: String {
        if vm.isLoading && vm.usuarios.isEmpty { return "Cargando cuentas…" }
        let n = vm.usuarios.count, a = vm.usuarios.filter { $0.role == "admin" }.count
        return "\(n) cuenta\(n == 1 ? "" : "s") · \(a) administrador\(a == 1 ? "" : "es")"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                NoktaEncabezado(titulo: "Usuarios", subtitulo: subtitulo) {
                    Button { editForm = UsuarioForm() } label: { Label("Nueva cuenta", systemImage: "plus") }
                        .buttonStyle(NoktaBotonPrimario())
                }
                .noktaEntrada(aparecio, 0)

                if let error = vm.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle").font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.error)
                }

                // Riel del que cuelgan los gafetes
                Capsule()
                    .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.1)], startPoint: .top, endPoint: .bottom))
                    .frame(height: 14)
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 4)
                    .padding(.top, 6)
                    .noktaEntrada(aparecio, 1)

                if vm.isLoading && vm.usuarios.isEmpty {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(NoktaTheme.superficie)
                        .frame(width: 210, height: 300).modifier(NoktaBrillo())
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 240), spacing: 34)], alignment: .leading, spacing: 30) {
                        ForEach(Array(vm.usuarios.enumerated()), id: \.element.id) { i, u in
                            Gafete(usuario: u, indice: i, volteado: volteados.contains(u.id),
                                   voltear: { withAnimation(.spring(duration: 0.7, bounce: 0.15)) { if volteados.contains(u.id) { volteados.remove(u.id) } else { volteados.insert(u.id) } } },
                                   editar: { editForm = UsuarioForm(u) },
                                   eliminar: { eliminarConfirm = u })
                                .noktaEntrada(aparecio, 2 + i)
                        }
                        Button { editForm = UsuarioForm() } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "plus").font(.system(size: 26, weight: .ultraLight))
                                Text("Nueva cuenta").font(NoktaFont.poppins(12))
                            }
                            .foregroundStyle(NoktaTheme.textoTenue)
                            .frame(width: 200, height: 280)
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(NoktaTheme.borde, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 108)
                        .noktaEntrada(aparecio, 2 + vm.usuarios.count)
                    }
                    Text("Toca un gafete para voltearlo").font(NoktaFont.poppins(11.5)).foregroundStyle(NoktaTheme.textoTenue)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, ancho < 600 ? 20 : 40)
            .padding(.vertical, ancho < 600 ? 16 : 32)
            .frame(maxWidth: 1240, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(NoktaTheme.fondo)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { ancho = $0 }
        .task {
            await vm.load()
            withAnimation(.spring(duration: 0.7, bounce: 0.1)) { aparecio = true }
        }
        .refreshable { await vm.load() }
        .sheet(item: $editForm) { form in
            UsuarioFormSheet(form: form, vm: vm) { editForm = nil }
        }
        .alert("¿Quitarle el acceso a esta cuenta?", isPresented: Binding(get: { eliminarConfirm != nil }, set: { if !$0 { eliminarConfirm = nil } })) {
            Button("Cancelar", role: .cancel) {}
            Button("Quitar acceso", role: .destructive) {
                if let u = eliminarConfirm { Task { await vm.eliminar(u._id) } }
            }
        } message: {
            Text("Se borra la cuenta y ya no podrá entrar al panel.")
        }
    }
}

/// Un gafete: cinta, broche y la credencial que se mece y se voltea.
private struct Gafete: View {
    let usuario: NoktaUsuario
    let indice: Int
    let volteado: Bool
    let voltear: () -> Void
    let editar: () -> Void
    let eliminar: () -> Void
    @State private var encima = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var esAdmin: Bool { usuario.role == "admin" }

    var body: some View {
        TimelineView(.animation(paused: encima || reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate + Double(indice) * 0.9
            let angulo = encima || reduceMotion ? 0 : sin(t * 2 * .pi / 3.6) * 2.2
            VStack(spacing: 0) {
                cinta
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.55)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 26, height: 16).offset(y: -2)
                ZStack {
                    frente.opacity(volteado ? 0 : 1)
                    atras.opacity(volteado ? 1 : 0).rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                }
                .frame(width: 200, height: 280)
                .rotation3DEffect(.degrees(volteado ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                .shadow(color: .black.opacity(0.55), radius: 18, y: 14)
                .offset(y: -2)
                .onTapGesture(perform: voltear)
            }
            .rotationEffect(.degrees(angulo), anchor: .top)
        }
        .onHover { encima = $0 }
        .frame(maxWidth: .infinity)
    }

    private var cinta: some View {
        let c = colorRol(usuario.role)
        return Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(c))
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y + 6, width: size.width, height: 6)), with: .color(.black.opacity(0.28)))
                y += 12
            }
        }
        .frame(width: 14, height: 90)
    }

    private var frente: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(red: 0.8, green: 0.76, blue: 0.71)).frame(width: 40, height: 7).padding(.top, 14)
            FotoCuenta(nombre: usuario.nombre, foto: usuario.foto, tamanoIniciales: 40)
                .frame(width: 108, height: 122)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 4)
                .padding(.top, 14)
            Text(usuario.nombre ?? usuario.username)
                .font(NoktaFont.poppins(15, .medium)).foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.1))
                .lineLimit(2).multilineTextAlignment(.center).padding(.horizontal, 12).padding(.top, 12)
            Text(esAdmin ? "ADMIN" : "EDITOR")
                .font(NoktaFont.poppins(9, .semibold)).tracking(2.2).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(colorRol(usuario.role), in: Capsule())
                .padding(.top, 6)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Circle().fill(NoktaTheme.marca).frame(width: 5, height: 5)
                Text("nokta studio").font(NoktaFont.poppins(9.5, .medium)).foregroundStyle(Color(white: 0.58))
            }
            .padding(.bottom, 14)
        }
        .frame(width: 200, height: 280)
        .background(LinearGradient(colors: [Color(red: 0.965, green: 0.95, blue: 0.92), Color(red: 0.91, green: 0.88, blue: 0.83)],
                                   startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var atras: some View {
        VStack(alignment: .leading, spacing: 10) {
            dato("USUARIO", "@" + usuario.username, mono: true)
            dato("ACCESO", esAdmin ? "Total" : "Normal")
            dato("DESDE", desde)
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                botonAtras("Editar", systemImage: "pencil", accion: editar)
                botonAtras("Cambiar contraseña", systemImage: "key", accion: editar)
                if !esAdmin {
                    botonAtras("Quitar acceso", systemImage: "trash", rojo: true, accion: eliminar)
                }
            }
        }
        .padding(16)
        .frame(width: 200, height: 280, alignment: .topLeading)
        .background(LinearGradient(colors: [Color(red: 0.14, green: 0.13, blue: 0.12), Color(red: 0.09, green: 0.09, blue: 0.08)],
                                   startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.07)))
    }

    private var desde: String {
        guard let am = FechaUtil.anioMes(usuario.creado) else { return "—" }
        return "\(FechaUtil.mesesAbrev[am.mes - 1]) \(am.anio)"
    }

    private func dato(_ t: String, _ v: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(NoktaFont.poppins(9, .medium)).tracking(1.6).foregroundStyle(.white.opacity(0.35))
            Text(v).font(mono ? .system(size: 13, design: .monospaced) : NoktaFont.poppins(13))
                .foregroundStyle(Color(red: 0.96, green: 0.95, blue: 0.92)).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func botonAtras(_ t: String, systemImage: String, rojo: Bool = false, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Label(t, systemImage: systemImage)
                .font(NoktaFont.poppins(11.5, .medium))
                .foregroundStyle(rojo ? NoktaTheme.error : Color(red: 0.96, green: 0.95, blue: 0.92))
                .frame(maxWidth: .infinity).frame(height: 30)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.07)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                FotoCuenta(nombre: form.nombre, foto: form.foto, datosLocales: photoData, tamanoIniciales: 20)
                    .frame(width: 60, height: 60).clipShape(Circle())
                    .overlay(Circle().strokeBorder(colorRol(form.role), lineWidth: 1.5).padding(-3))
                VStack(alignment: .leading, spacing: 4) {
                    Text(form.id == nil ? "Nueva cuenta" : "Editar cuenta").font(NoktaFont.poppins(22, .light)).foregroundStyle(NoktaTheme.texto)
                    if let id = form.id {
                        HStack(spacing: 8) {
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Label(form.foto == nil ? "Subir foto" : "Cambiar foto", systemImage: "camera")
                                    .font(NoktaFont.poppins(11.5, .medium)).foregroundStyle(NoktaTheme.marca)
                            }
                            .buttonStyle(.plain)
                            .disabled(isUploadingPhoto)
                            .onChange(of: photoItem) { _, item in subir(item, id: id) }
                            if isUploadingPhoto { ProgressView().controlSize(.small) }
                        }
                    } else {
                        Text("La foto se sube después de crear la cuenta.").font(NoktaFont.poppins(11.5)).foregroundStyle(NoktaTheme.textoSuave)
                    }
                }
            }

            HStack(spacing: 10) {
                campo("Nombre y apellido") { TextField("", text: $form.nombre, prompt: Text("Ej. Carlos Méndez").foregroundStyle(NoktaTheme.textoTenue)) }
                campo("Usuario") {
                    TextField("", text: $form.username, prompt: Text("sin espacios").foregroundStyle(NoktaTheme.textoTenue))
                        .autocorrectionDisabled()
                }
            }
            campo(form.id == nil ? "Contraseña" : "Contraseña nueva") {
                SecureField("", text: $form.password, prompt: Text(form.id == nil ? "Contraseña" : "Déjala vacía para no cambiarla").foregroundStyle(NoktaTheme.textoTenue))
            }
            VStack(alignment: .leading, spacing: 7) {
                rotuloCuenta("Rol")
                NoktaChips(opciones: [("editor", "Editor · acceso normal"), ("admin", "Administrador · acceso total")], seleccion: $form.role)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle").font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.error)
            }

            HStack {
                Button("Cancelar") { dismiss() }.buttonStyle(NoktaBotonSecundario())
                Spacer()
                Button(isSaving ? "Guardando…" : "Guardar") { Task { await guardar() } }
                    .buttonStyle(NoktaBotonPrimario())
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving)
            }
        }
        .padding(26)
        .frame(width: 500)
        .background(NoktaTheme.superficie)
    }

    private func rotuloCuenta(_ t: String) -> some View {
        Text(t.uppercased()).font(NoktaFont.poppins(10, .medium)).tracking(1.2).foregroundStyle(NoktaTheme.textoTenue)
    }

    private func campo<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            rotuloCuenta(t)
            c()
                .textFieldStyle(.plain)
                .font(NoktaFont.poppins(13)).foregroundStyle(NoktaTheme.texto)
                .padding(.horizontal, 12).frame(height: 40)
                .background(NoktaTheme.superficie2, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(NoktaTheme.borde))
        }
    }

    private func subir(_ item: PhotosPickerItem?, id: String) {
        Task {
            guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
            isUploadingPhoto = true
            errorMessage = nil
            defer { isUploadingPhoto = false }
            do {
                let jpeg = try UsuarioFoto.preparar(data)
                if let err = await vm.subirFoto(id, base64: "data:image/jpeg;base64," + jpeg.base64EncodedString()) {
                    errorMessage = err
                } else if let updated = vm.usuarios.first(where: { $0._id == id }) {
                    photoData = jpeg
                    form.foto = updated.foto
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func guardar() async {
        guard !form.nombre.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Escribe el nombre"; return }
        guard !form.username.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Escribe el usuario"; return }
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

/// Decode supported photo formats, apply orientation, and upload actual JPEG
/// bytes sized for an avatar rather than a full-resolution camera original.
enum UsuarioFoto {
    static func preparar(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1400,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw FotoError.imagenInvalida }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw FotoError.imagenInvalida
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= 4_000_000 else { throw FotoError.noSePudoReducir }
        return output as Data
    }

    enum FotoError: LocalizedError {
        case imagenInvalida, noSePudoReducir
        var errorDescription: String? {
            switch self {
            case .imagenInvalida: return "No se pudo leer esa imagen. Selecciona otra foto."
            case .noSePudoReducir: return "No se pudo reducir la foto para subirla. Selecciona otra imagen."
            }
        }
    }
}
