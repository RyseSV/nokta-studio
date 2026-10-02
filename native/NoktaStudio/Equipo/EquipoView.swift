import SwiftUI

/// Port of admin.html's "Mi equipo" section — team members' pay records (not
/// login accounts, see UsuariosView for those). Diseño "visor de cámara"
/// (2026-10): la persona elegida se ve como por el visor de una cámara; su
/// foto es la misma de su cuenta de usuario (la del menú lateral), así que
/// cuando alguien cambia su foto se actualiza aquí sola.
@Observable
final class EquipoViewModel {
    var miembros: [NoktaEquipo] = []
    var usuarios: [UsuarioVinculable] = []
    var seleccion: String?
    var isLoading = true
    var errorMessage: String?

    func load() async {
        isLoading = true
        defer { isLoading = false }
        async let m: [NoktaEquipo]? = try? NoktaAPI.get("/api/equipo")
        async let u: [UsuarioVinculable]? = try? NoktaAPI.get("/api/equipo/usuarios")
        let (mm, uu) = await (m, u)
        if let mm { miembros = mm.sorted { ($0.creado ?? "") < ($1.creado ?? "") } }
        if let uu { usuarios = uu }
        if seleccion == nil || !miembros.contains(where: { $0.id == seleccion }) { seleccion = miembros.first?.id }
    }

    var elegido: NoktaEquipo? { miembros.first { $0.id == seleccion } ?? miembros.first }
    var totalPagado: Double { miembros.reduce(0) { $0 + ($1.pagado ?? 0) } }
    var totalPendiente: Double { miembros.reduce(0) { $0 + ($1.pendiente ?? 0) } }

    private struct Body: Encodable {
        let nombre, rol, tipo: String
        let comision, pagado, pendiente: Double
        let usuarioId: String
    }
    private struct Resp: Decodable { let ok: Bool?; let miembro: NoktaEquipo? }

    /// Nil means the server confirmed the save; an error keeps the form open.
    func guardar(_ form: EquipoForm) async -> String? {
        let body = Body(nombre: form.nombre.trimmingCharacters(in: .whitespaces), rol: form.rol.trimmingCharacters(in: .whitespaces),
                        tipo: form.tipo, comision: form.comision, pagado: form.pagado, pendiente: form.pendiente,
                        usuarioId: form.usuarioId ?? "")
        do {
            let response: Resp
            if let id = form.id {
                response = try await NoktaAPI.put("/api/equipo/\(id)", body: body)
            } else {
                response = try await NoktaAPI.post("/api/equipo", body: body)
            }
            guard response.ok == true else { return "El servidor no confirmó el guardado. Revisa el estado antes de reintentar." }
            if form.id == nil, let nuevo = response.miembro?.id { seleccion = nuevo }
            await load()
            return nil
        } catch {
            return "No se pudo confirmar el guardado. \(error.localizedDescription)"
        }
    }

    /// Pasa un monto de "pendiente" a "pagado".
    func registrarPago(_ m: NoktaEquipo, monto: Double) async -> String? {
        var f = EquipoForm(m)
        f.pagado += monto
        f.pendiente = max(0, f.pendiente - monto)
        return await guardar(f)
    }

    func eliminar(_ id: String) async {
        struct R: Decodable { let ok: Bool? }
        errorMessage = nil
        do {
            let response: R = try await NoktaAPI.delete("/api/equipo/\(id)")
            guard response.ok == true else {
                errorMessage = "El servidor no confirmó la eliminación. Actualiza la lista antes de reintentar."
                return
            }
            miembros.removeAll { $0.id == id }
            if seleccion == id { seleccion = miembros.first?.id }
        } catch {
            errorMessage = "No se pudo confirmar la eliminación. \(error.localizedDescription)"
        }
    }
}

/// Cuenta de usuario que se puede vincular a un miembro (solo nombre y foto).
struct UsuarioVinculable: Codable, Identifiable, Hashable {
    var id: String
    var nombre: String?
    var username: String?
    var foto: String?
}

struct EquipoForm: Identifiable {
    var id: String?
    var nombre = ""
    var rol = ""
    var tipo = "fijo"
    var comision: Double = 0
    var pagado: Double = 0
    var pendiente: Double = 0
    var usuarioId: String?
    init() {}
    init(_ m: NoktaEquipo) {
        id = m.id; nombre = m.nombre ?? ""; rol = m.rol ?? ""; tipo = m.tipo ?? "fijo"
        comision = m.comision ?? 0; pagado = m.pagado ?? 0; pendiente = m.pendiente ?? 0
        usuarioId = (m.usuarioId?.isEmpty == false) ? m.usuarioId : nil
    }
}

private func formaDePago(_ m: NoktaEquipo) -> String {
    let v = m.comision ?? 0
    if m.tipo == "comision" { return "\(v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v))% de comisión" }
    return v > 0 ? "\(NoktaFormato.dinero(v)) por evento" : "Fijo por evento"
}

/// Colores de respaldo cuando alguien no tiene foto.
private let fondosSinFoto: [[Color]] = [
    [Color(red: 0.79, green: 0.46, blue: 0.29), Color(red: 0.23, green: 0.12, blue: 0.07)],
    [Color(red: 0.37, green: 0.5, blue: 0.77), Color(red: 0.09, green: 0.13, blue: 0.24)],
    [Color(red: 0.37, green: 0.65, blue: 0.49), Color(red: 0.07, green: 0.16, blue: 0.11)],
    [Color(red: 0.63, green: 0.42, blue: 0.75), Color(red: 0.15, green: 0.09, blue: 0.23)],
]

/// La foto de la persona (de su cuenta) o, si no tiene, sus iniciales.
private struct FotoMiembro: View {
    let miembro: NoktaEquipo
    let indice: Int
    var tamanoIniciales: CGFloat = 20
    /// En el visor la foto va completa (sin recortar ni agrandar de más) sobre
    /// una copia desenfocada que llena el fondo.
    var completa = false

    var body: some View {
        ZStack {
            let c = fondosSinFoto[indice % fondosSinFoto.count]
            LinearGradient(colors: c, startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(NoktaFormato.iniciales(miembro.nombre ?? ""))
                .font(NoktaFont.poppins(tamanoIniciales, .light))
                .foregroundStyle(.white.opacity(0.85))
            if let url = miembro.foto.flatMap(URL.init) {
                AsyncImage(url: url) { fase in
                    if let img = fase.image {
                        if completa {
                            // La foto completa ocupa el espacio que le dan; la copia
                            // desenfocada va de fondo y no puede agrandar el visor.
                            img.resizable().interpolation(.high).scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background {
                                    img.resizable().scaledToFill()
                                        .blur(radius: 40).overlay(Color.black.opacity(0.35))
                                        .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                                }
                                .transition(.opacity)
                        } else {
                            img.resizable().interpolation(.high).scaledToFill().transition(.opacity)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

struct EquipoView: View {
    @State private var vm = EquipoViewModel()
    @State private var editForm: EquipoForm?
    @State private var pagoDe: NoktaEquipo?
    @State private var eliminarConfirm: String?
    @State private var aparecio = false
    @State private var disparo = false
    @State private var enfoque = false
    @State private var ancho: CGFloat = 1000

    private var ancha: Bool { ancho >= 860 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                NoktaEncabezado(titulo: "Mi equipo", subtitulo: subtitulo) {
                    Button { editForm = EquipoForm() } label: { Label("Agregar persona", systemImage: "plus") }
                        .buttonStyle(NoktaBotonPrimario())
                }
                .noktaEntrada(aparecio, 0)

                if let error = vm.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle").font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.error)
                }

                if vm.miembros.isEmpty {
                    if vm.isLoading {
                        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(NoktaTheme.superficie)
                            .frame(height: 380).modifier(NoktaBrillo())
                    } else {
                        VStack(spacing: 14) {
                            NoktaVacio(icono: "person.3", titulo: "Aún no hay nadie en tu equipo",
                                       detalle: "Agrega a tus fotógrafos, editores y asistentes para llevar lo que les pagas.")
                            Button { editForm = EquipoForm() } label: { Label("Agregar persona", systemImage: "plus") }
                                .buttonStyle(NoktaBotonPrimario())
                        }
                        .frame(maxWidth: .infinity).padding(.bottom, 30).noktaCard()
                    }
                } else if let m = vm.elegido {
                    let fila = ancha
                        ? AnyLayout(HStackLayout(alignment: .top, spacing: 22))
                        : AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
                    fila {
                        visor(m).frame(maxWidth: .infinity).noktaEntrada(aparecio, 1)
                        lado(m).frame(width: ancha ? 300 : nil).frame(maxWidth: ancha ? 300 : .infinity).noktaEntrada(aparecio, 2)
                    }
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
            enfocar()
        }
        .refreshable { await vm.load() }
        .sheet(item: $editForm) { form in
            EquipoFormSheet(form: form, usuarios: vm.usuarios) { updated in
                await vm.guardar(updated)
            }
        }
        .sheet(item: $pagoDe) { m in
            PagoMiembroSheet(miembro: m) { monto in await vm.registrarPago(m, monto: monto) }
        }
        .alert("¿Eliminar a esta persona del equipo?", isPresented: Binding(get: { eliminarConfirm != nil }, set: { if !$0 { eliminarConfirm = nil } })) {
            Button("Cancelar", role: .cancel) {}
            Button("Eliminar", role: .destructive) {
                if let id = eliminarConfirm { Task { await vm.eliminar(id) } }
            }
        } message: {
            Text("Se borra su registro de pagos. Su cuenta de usuario no se toca.")
        }
    }

    private var subtitulo: String {
        if vm.isLoading && vm.miembros.isEmpty { return "Cargando tu equipo…" }
        let n = vm.miembros.count
        let base = "\(n) persona\(n == 1 ? "" : "s")"
        return vm.totalPendiente > 0 ? "\(base) · le debes \(NoktaFormato.dinero(vm.totalPendiente))" : "\(base) · todo al día"
    }

    private func elegir(_ id: String) {
        guard id != vm.seleccion else { return }
        // "Disparo": la pantalla parpadea en negro y cambia la foto.
        withAnimation(.easeIn(duration: 0.1)) { disparo = true }
        Task {
            try? await Task.sleep(for: .milliseconds(110))
            vm.seleccion = id
            withAnimation(.easeOut(duration: 0.25)) { disparo = false }
            enfocar()
        }
    }

    private func enfocar() {
        enfoque = false
        withAnimation(.spring(duration: 0.7, bounce: 0.45).delay(0.05)) { enfoque = true }
    }

    // MARK: Visor

    private func visor(_ m: NoktaEquipo) -> some View {
        let i = vm.miembros.firstIndex { $0.id == m.id } ?? 0
        let pag = m.pagado ?? 0, pen = m.pendiente ?? 0
        let f = pag + pen > 0 ? pag / (pag + pen) : 1
        let hud = Font.system(size: 11, weight: .medium, design: .monospaced)
        return ZStack {
            FotoMiembro(miembro: m, indice: i, tamanoIniciales: 120, completa: true)
                .id(m.id)
            RadialGradient(colors: [.clear, .black.opacity(0.6)], center: .init(x: 0.5, y: 0.42), startRadius: 120, endRadius: 520)
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)

            // Esquinas del visor
            GeometryReader { g in
                let l: CGFloat = 26, a: CGFloat = 18
                Path { p in
                    for (x, y, sx, sy) in [(a, a, 1.0, 1.0), (g.size.width - a, a, -1.0, 1.0), (a, g.size.height - a, 1.0, -1.0), (g.size.width - a, g.size.height - a, -1.0, -1.0)] {
                        p.move(to: CGPoint(x: x, y: y + sy * l)); p.addLine(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x + sx * l, y: y))
                    }
                }
                .stroke(.white.opacity(0.8), lineWidth: 2)
                // Cuadro de enfoque
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(red: 0.42, green: 1, blue: 0.62), lineWidth: 1.5)
                    .shadow(color: Color(red: 0.42, green: 1, blue: 0.62).opacity(0.6), radius: 6)
                    .frame(width: 120, height: 120)
                    .scaleEffect(enfoque ? 1 : 1.5)
                    .opacity(enfoque ? 1 : 0)
                    .position(x: g.size.width / 2, y: g.size.height * 0.4)
            }

            VStack {
                HStack {
                    HStack(spacing: 6) {
                        TimelineView(.periodic(from: .now, by: 0.6)) { ctx in
                            Circle().fill(Color(red: 1, green: 0.3, blue: 0.24)).frame(width: 9, height: 9)
                                .opacity(Int(ctx.date.timeIntervalSince1970 / 0.6) % 2 == 0 ? 1 : 0.25)
                        }
                        Text("MI EQUIPO")
                    }
                    Spacer()
                    Text("\(vm.miembros.count) PERSONA\(vm.miembros.count == 1 ? "" : "S") · \(NoktaFormato.dinero(vm.totalPendiente)) PENDIENTE")
                }
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text((m.rol ?? "").uppercased()).font(.system(size: 10, weight: .medium)).tracking(2).opacity(0.75)
                        Text(m.nombre ?? "—").font(NoktaFont.poppins(28, .light)).tracking(-0.8).lineLimit(1).minimumScaleFactor(0.6)
                        if let u = m.usuarioNombre, m.foto == nil {
                            Text("\(u) aún no sube su foto").font(NoktaFont.poppins(10.5)).opacity(0.6)
                        }
                    }
                    Spacer(minLength: 12)
                    medidor(f).frame(width: 150)
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formaDePago(m).uppercased())
                        Text(pen > 0 ? "LE DEBES \(NoktaFormato.dinero(pen))" : "AL DÍA ✓")
                    }
                    .multilineTextAlignment(.trailing)
                }
            }
            .font(hud)
            .foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black.opacity(0.5), radius: 4)
            .padding(30)

            Color.black.opacity(disparo ? 1 : 0).allowsHitTesting(false)
        }
        .frame(height: ancho < 600 ? 360 : 460)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.easeInOut(duration: 0.3), value: m.foto)
    }

    /// Medidor de exposición: izquierda = todo pagado, derecha = le debes.
    private func medidor(_ fraccionPagada: Double) -> some View {
        VStack(spacing: 5) {
            GeometryReader { g in
                ZStack(alignment: .bottomLeading) {
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(0..<13, id: \.self) { k in
                            Rectangle().fill(.white.opacity(0.75)).frame(width: 1.5, height: k % 3 == 0 ? 12 : 7)
                            if k < 12 { Spacer(minLength: 0) }
                        }
                    }
                    Triangulo().fill(Color(red: 1, green: 0.76, blue: 0.29))
                        .frame(width: 10, height: 7)
                        .offset(x: g.size.width * (1 - fraccionPagada) - 5, y: -15)
                        .animation(.spring(duration: 0.9, bounce: 0.15), value: fraccionPagada)
                }
            }
            .frame(height: 22)
            Text("PAGADO ◂ ▸ LE DEBES").font(.system(size: 8.5, weight: .medium, design: .monospaced)).opacity(0.8)
        }
    }

    // MARK: Lado

    private func lado(_ m: NoktaEquipo) -> some View {
        let pen = m.pendiente ?? 0
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("EL EQUIPO").font(NoktaFont.poppins(10, .medium)).tracking(1.4).foregroundStyle(NoktaTheme.textoTenue)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 10), count: 4), alignment: .leading, spacing: 10) {
                    ForEach(Array(vm.miembros.enumerated()), id: \.element.id) { i, x in
                        let on = x.id == m.id
                        Button { elegir(x.id) } label: {
                            FotoMiembro(miembro: x, indice: i, tamanoIniciales: 20)
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(on ? NoktaTheme.marca : NoktaTheme.borde, lineWidth: on ? 2 : 1))
                                .opacity(on ? 1 : 0.55)
                                .offset(y: on ? -3 : 0)
                                .animation(.spring(duration: 0.35), value: on)
                        }
                        .buttonStyle(.plain)
                        .help(x.nombre ?? "")
                    }
                    Button { editForm = EquipoForm() } label: {
                        Image(systemName: "plus").font(.system(size: 18, weight: .light)).foregroundStyle(NoktaTheme.textoTenue)
                            .frame(width: 64, height: 64)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(NoktaTheme.borde, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help("Agregar persona")
                }
            }

            HStack(spacing: 16) {
                numero("PAGADO", m.pagado ?? 0, NoktaTheme.exito)
                numero("LE DEBES", pen, pen > 0 ? NoktaTheme.aviso : NoktaTheme.textoTenue)
            }

            HStack(spacing: 8) {
                if pen > 0 {
                    Button { pagoDe = m } label: { Label("Registrar pago", systemImage: "checkmark.circle") }
                        .buttonStyle(NoktaBotonPrimario())
                }
                Button { editForm = EquipoForm(m) } label: { Label("Editar", systemImage: "pencil") }
                    .buttonStyle(NoktaBotonSecundario())
                Menu {
                    Button(role: .destructive) { eliminarConfirm = m.id } label: { Label("Eliminar del equipo", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium)).foregroundStyle(NoktaTheme.textoSuave)
                        .frame(width: 36, height: 36)
                        .background(NoktaTheme.superficie2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            }

            Text(m.foto == nil
                 ? (m.usuarioNombre == nil ? "Para ver su foto, vincúlala a su cuenta en Editar. La foto es la que cada quien sube a su perfil."
                                           : "Cuando suba su foto de perfil aparecerá aquí sola.")
                 : "La foto es la de su perfil: si la cambia, se actualiza aquí y en la web.")
                .font(NoktaFont.poppins(11.5)).foregroundStyle(NoktaTheme.textoTenue)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("TODO EL EQUIPO").font(NoktaFont.poppins(10, .medium)).tracking(1.4).foregroundStyle(NoktaTheme.textoTenue)
                Text("Pagado \(NoktaFormato.dinero(vm.totalPagado)) · pendiente \(NoktaFormato.dinero(vm.totalPendiente))")
                    .font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoSuave)
            }
            .padding(.top, 4)
        }
    }

    private func numero(_ t: String, _ v: Double, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(NoktaFont.poppins(10, .medium)).tracking(1.2).foregroundStyle(NoktaTheme.textoTenue)
            Text(NoktaFormato.dinero(v)).font(NoktaFont.poppins(30, .light)).tracking(-1.2).foregroundStyle(c)
                .contentTransition(.numericText(value: v))
                .animation(.snappy, value: v)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Triangulo: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.closeSubpath() }
    }
}

// MARK: - Ventanas

private func rotulo(_ t: String) -> some View {
    Text(t.uppercased()).font(NoktaFont.poppins(10, .medium)).tracking(1.2).foregroundStyle(NoktaTheme.textoTenue)
}

private func caja<C: View>(@ViewBuilder _ c: () -> C) -> some View {
    c()
        .textFieldStyle(.plain)
        .font(NoktaFont.poppins(13)).foregroundStyle(NoktaTheme.texto)
        .padding(.horizontal, 12).frame(height: 40)
        .background(NoktaTheme.superficie2, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(NoktaTheme.borde))
}

private struct EquipoFormSheet: View {
    @State var form: EquipoForm
    let usuarios: [UsuarioVinculable]
    let onGuardar: (EquipoForm) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var cuenta: UsuarioVinculable? { usuarios.first { $0.id == form.usuarioId } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(NoktaTheme.superficie2)
                    if let url = cuenta?.foto.flatMap(URL.init) {
                        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    } else {
                        Text(NoktaFormato.iniciales(form.nombre)).font(NoktaFont.poppins(16, .medium)).foregroundStyle(NoktaTheme.marca)
                    }
                }
                .frame(width: 54, height: 54).clipShape(Circle())
                .overlay(Circle().strokeBorder(NoktaTheme.marca, lineWidth: 1.5).padding(-3))
                VStack(alignment: .leading, spacing: 3) {
                    Text(form.id == nil ? "Agregar persona" : "Editar persona").font(NoktaFont.poppins(22, .light)).foregroundStyle(NoktaTheme.texto)
                    Text("Su foto sale de su cuenta: la que sube a su perfil.").font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoSuave)
                }
            }

            HStack(spacing: 10) {
                campo("Nombre") { TextField("", text: $form.nombre, prompt: Text("Nombre completo").foregroundStyle(NoktaTheme.textoTenue)) }
                campo("Rol") { TextField("", text: $form.rol, prompt: Text("Fotógrafo, editora…").foregroundStyle(NoktaTheme.textoTenue)) }
            }

            VStack(alignment: .leading, spacing: 7) {
                rotulo("Cuenta (para su foto)")
                Menu {
                    Button("Sin cuenta") { form.usuarioId = nil }
                    ForEach(usuarios) { u in
                        Button(u.nombre ?? u.username ?? "—") {
                            form.usuarioId = u.id
                            if form.nombre.trimmingCharacters(in: .whitespaces).isEmpty { form.nombre = u.nombre ?? "" }
                        }
                    }
                } label: {
                    caja {
                        HStack {
                            Text(cuenta.map { ($0.nombre ?? $0.username ?? "") + ($0.foto == nil ? " · sin foto aún" : "") } ?? "Sin cuenta")
                                .foregroundStyle(cuenta == nil ? NoktaTheme.textoTenue : NoktaTheme.texto)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(NoktaTheme.textoTenue)
                        }
                        .contentShape(Rectangle())
                    }
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            }

            VStack(alignment: .leading, spacing: 7) {
                rotulo("Cómo le pagas")
                NoktaChips(opciones: [("fijo", "Fijo por evento"), ("comision", "Comisión %")], seleccion: $form.tipo)
            }

            HStack(spacing: 10) {
                campo(form.tipo == "comision" ? "Comisión (%)" : "Por evento ($)") { TextField("", value: $form.comision, format: .number) }
                campo("Pagado ($)") { TextField("", value: $form.pagado, format: .number) }
                campo("Pendiente ($)") { TextField("", value: $form.pendiente, format: .number) }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle").font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.error)
            }
            HStack {
                Button("Cancelar") { dismiss() }.buttonStyle(NoktaBotonSecundario()).disabled(isSaving)
                Spacer()
                Button(isSaving ? "Guardando…" : "Guardar") { Task { await guardar() } }
                    .buttonStyle(NoktaBotonPrimario())
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving)
                    .opacity(isSaving ? 0.6 : 1)
            }
        }
        .padding(26)
        .frame(width: 480)
        .background(NoktaTheme.superficie)
        .interactiveDismissDisabled(isSaving)
    }

    private func campo<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) { rotulo(t); caja(c) }
    }

    private func guardar() async {
        guard !isSaving else { return }
        guard !form.nombre.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Escribe el nombre de la persona"; return
        }
        isSaving = true
        defer { isSaving = false }
        errorMessage = await onGuardar(form)
        if errorMessage == nil { dismiss() }
    }
}

/// Registrar un pago: pasa el monto de pendiente a pagado.
private struct PagoMiembroSheet: View {
    let miembro: NoktaEquipo
    let onPagar: (Double) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var monto: Double = 0
    @State private var guardando = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Registrar pago").font(NoktaFont.poppins(22, .light)).foregroundStyle(NoktaTheme.texto)
                Text("A \(miembro.nombre ?? "esta persona") le debes \(NoktaFormato.dinero(miembro.pendiente ?? 0)).")
                    .font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoSuave)
            }
            VStack(alignment: .leading, spacing: 7) {
                rotulo("Cuánto le pagaste ($)")
                caja { TextField("", value: $monto, format: .number) }
            }
            Text("Se suma a lo pagado y se resta de lo pendiente.").font(NoktaFont.poppins(11.5)).foregroundStyle(NoktaTheme.textoTenue)
            if let error {
                Label(error, systemImage: "exclamationmark.circle").font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.error)
            }
            HStack {
                Button("Cancelar") { dismiss() }.buttonStyle(NoktaBotonSecundario())
                Spacer()
                Button(guardando ? "Guardando…" : "Pagar \(NoktaFormato.dinero(monto))") {
                    guard monto > 0 else { error = "Escribe un monto mayor que cero"; return }
                    guardando = true
                    Task {
                        error = await onPagar(monto)
                        guardando = false
                        if error == nil { dismiss() }
                    }
                }
                .buttonStyle(NoktaBotonPrimario())
                .keyboardShortcut(.defaultAction)
                .disabled(guardando)
            }
        }
        .padding(26)
        .frame(width: 380)
        .background(NoktaTheme.superficie)
        .onAppear { monto = miembro.pendiente ?? 0 }
    }
}
