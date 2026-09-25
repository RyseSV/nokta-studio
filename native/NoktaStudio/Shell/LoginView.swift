import SwiftUI

/// The app never had its own login screen — it always relied on the WKWebView
/// showing admin.html's real login form once, then a since-removed CookieSync
/// helper copying that session cookie into NoktaAPI's URLSession on every
/// request. Now that every sidebar section is native (RootView's webPageId
/// is nil everywhere), that WKWebView is unreachable, so this is the only
/// way left to actually sign in.
///
/// Posting directly to /api/admin/login works without any WKWebView
/// involved: NoktaAPI's URLSession already uses `.shared` cookie storage and
/// accepts all cookies, so the Set-Cookie header from this POST lands there
/// directly and stays put — nothing re-syncs over it afterward.
@Observable
final class LoginViewModel {
    var username = ""
    var password = ""
    var remember = true
    var isLoading = false
    var errorMessage: String?

    func login() async -> Bool {
        errorMessage = nil
        let user = username.trimmingCharacters(in: .whitespaces)
        guard !user.isEmpty, !password.isEmpty else {
            errorMessage = "Escribe tu usuario y contraseña"
            return false
        }
        isLoading = true
        defer { isLoading = false }
        struct Body: Encodable { let username: String; let password: String; let remember: Bool }
        struct Resp: Decodable { let ok: Bool? }
        do {
            let resp: Resp = try await NoktaAPI.post("/api/admin/login", body: Body(username: user, password: password, remember: remember))
            if resp.ok == true { return true }
            errorMessage = "Usuario o contraseña incorrectos"
            return false
        } catch NoktaAPIError.http(_, let msg) {
            errorMessage = msg == "—" ? "Usuario o contraseña incorrectos" : msg
            return false
        } catch {
            errorMessage = "No se pudo conectar. Revisa tu internet."
            return false
        }
    }
}

struct LoginView: View {
    @State private var vm = LoginViewModel()
    let onSuccess: () -> Void

    private enum Campo { case usuario, password }
    @FocusState private var foco: Campo?
    @State private var verPassword = false
    @State private var aparecio = false
    /// Bumped on every failed attempt to drive the error shake.
    @State private var intentosFallidos = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                NoktaTheme.fondo.ignoresSafeArea()
                TrazoVivo(anima: !reduceMotion).ignoresSafeArea().allowsHitTesting(false)
                Grano().ignoresSafeArea().allowsHitTesting(false)
                if geo.size.width >= 860 {
                    ancho
                } else {
                    angosto(alto: geo.size.height)
                }
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.8, bounce: 0.15)) { aparecio = true }
            #if os(macOS)
            // Mac: cursor ready in the first field. iPhone: don't pop the
            // keyboard on arrival — it shoves the logo under the status bar.
            foco = vm.username.isEmpty ? .usuario : .password
            #endif
        }
    }

    /// Mac / wide: logo top-left, agency line bottom-left, glass form right.
    private var ancho: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                logo(tamano: 20)
                Spacer()
                Text("AGENCIA CREATIVA")
                    .font(NoktaFont.poppins(11, .medium))
                    .tracking(2.8)
                    .foregroundStyle(NoktaTheme.textoTenue)
                    .padding(.bottom, 14)
                Text("Las ideas\ntoman forma.")
                    .font(NoktaFont.poppins(46, .light))
                    .tracking(-1.8)
                    .foregroundStyle(NoktaTheme.texto)
                    .fixedSize()
            }
            .padding(.horizontal, 64)
            .padding(.top, 52)
            .padding(.bottom, 64)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .opacity(aparecio ? 1 : 0)

            tarjeta(conEncabezado: true)
                .frame(width: 380)
                .padding(.trailing, 96)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .opacity(aparecio ? 1 : 0)
                .offset(y: aparecio ? 0 : 18)
        }
    }

    /// iPhone / narrow: one centered column over the same ribbon.
    private func angosto(alto: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 22) {
                    logo(tamano: 22)
                    VStack(spacing: 8) {
                        Text("Bienvenido de vuelta")
                            .font(NoktaFont.poppins(28, .light))
                            .tracking(-1)
                            .foregroundStyle(NoktaTheme.texto)
                        Text("Ingresa a tu panel de administración")
                            .font(NoktaFont.poppins(13))
                            .foregroundStyle(NoktaTheme.textoSuave)
                    }
                }
                .multilineTextAlignment(.center)
                .opacity(aparecio ? 1 : 0)
                .offset(y: aparecio ? 0 : 12)
                tarjeta(conEncabezado: false)
                    .opacity(aparecio ? 1 : 0)
                    .offset(y: aparecio ? 0 : 18)
                Text("Agencia creativa · © " + String(Calendar.current.component(.year, from: Date())))
                    .font(NoktaFont.poppins(11))
                    .foregroundStyle(NoktaTheme.textoTenue)
                    .opacity(aparecio ? 1 : 0)
            }
            .frame(maxWidth: 360)
            .padding(.horizontal, 20)
            .padding(.vertical, 48)
            // Vertically centered when it fits, scrollable when it doesn't.
            .frame(maxWidth: .infinity, minHeight: max(560, alto))
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func logo(tamano: CGFloat) -> some View {
        HStack(spacing: tamano * 0.4) {
            Circle().fill(NoktaTheme.marca).frame(width: tamano * 0.38, height: tamano * 0.38)
            HStack(spacing: tamano * 0.25) {
                Text("nokta").font(NoktaFont.poppins(tamano, .medium)).foregroundStyle(NoktaTheme.texto)
                Text("studio").font(NoktaFont.poppins(tamano, .light)).foregroundStyle(NoktaTheme.textoTenue)
            }
            .tracking(-tamano * 0.03)
        }
    }

    private func tarjeta(conEncabezado: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if conEncabezado {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Bienvenido de vuelta")
                        .font(NoktaFont.poppins(24, .light))
                        .tracking(-0.8)
                        .foregroundStyle(NoktaTheme.texto)
                    Text("Ingresa a tu panel de administración")
                        .font(NoktaFont.poppins(12))
                        .foregroundStyle(NoktaTheme.textoSuave)
                }
                .padding(.bottom, 4)
            }
            campo("Usuario", icono: "person", activo: foco == .usuario) {
                TextField("", text: $vm.username, prompt: Text("Tu usuario").foregroundStyle(NoktaTheme.textoTenue))
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .focused($foco, equals: .usuario)
                    .submitLabel(.next)
                    .onSubmit { foco = .password }
            }

            campo("Contraseña", icono: "lock", activo: foco == .password) {
                Group {
                    if verPassword {
                        TextField("", text: $vm.password, prompt: Text("Tu contraseña").foregroundStyle(NoktaTheme.textoTenue))
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                    } else {
                        SecureField("", text: $vm.password, prompt: Text("Tu contraseña").foregroundStyle(NoktaTheme.textoTenue))
                    }
                }
                .textContentType(.password)
                .focused($foco, equals: .password)
                .submitLabel(.go)
                .onSubmit { Task { await submit() } }
            } accesorio: {
                Button {
                    verPassword.toggle()
                    foco = .password
                } label: {
                    Image(systemName: verPassword ? "eye.slash" : "eye")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(NoktaTheme.textoTenue)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(verPassword ? "Ocultar contraseña" : "Mostrar contraseña")
            }

            HStack(spacing: 12) {
                Text("Recordar sesión en este dispositivo")
                    .font(NoktaFont.poppins(12))
                    .foregroundStyle(NoktaTheme.textoSuave)
                Spacer(minLength: 0)
                Toggle("Recordar sesión en este dispositivo", isOn: $vm.remember)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(NoktaTheme.marca)
                    .controlSize(.small)
            }

            if let err = vm.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle").font(.system(size: 13, weight: .light))
                    Text(err).font(NoktaFont.poppins(12))
                }
                .foregroundStyle(NoktaTheme.error)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NoktaTheme.error.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .modifier(Temblor(intentos: intentosFallidos))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button { Task { await submit() } } label: {
                HStack(spacing: 8) {
                    if vm.isLoading {
                        ProgressView().controlSize(.small).tint(NoktaTheme.fondo)
                        Text("Ingresando…")
                    } else {
                        Text("Ingresar")
                        Image(systemName: "arrow.right").font(.system(size: 12, weight: .medium))
                    }
                }
                .font(NoktaFont.poppins(14, .medium))
                .foregroundStyle(NoktaTheme.fondo)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(NoktaTheme.texto, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(vm.isLoading)
            .opacity(vm.isLoading ? 0.85 : 1)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 4)
        }
        .padding(28)
        .background {
            // Frosted glass so the ribbon reads through without hurting legibility.
            let forma = RoundedRectangle(cornerRadius: 22, style: .continuous)
            forma.fill(.ultraThinMaterial)
            forma.fill(NoktaTheme.fondo.opacity(0.62))
        }
        .overlay(BordeDeLuz(radio: 22, anima: !reduceMotion))
        .animation(.snappy(duration: 0.25), value: vm.errorMessage)
    }

    private func campo<F: View>(
        _ titulo: String, icono: String, activo: Bool,
        @ViewBuilder field: () -> F
    ) -> some View {
        campo(titulo, icono: icono, activo: activo, field: field) { EmptyView() }
    }

    private func campo<F: View, A: View>(
        _ titulo: String, icono: String, activo: Bool,
        @ViewBuilder field: () -> F, @ViewBuilder accesorio: () -> A
    ) -> some View {
        let forma = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(alignment: .leading, spacing: 7) {
            Text(titulo).font(NoktaFont.poppins(12, .medium)).foregroundStyle(NoktaTheme.textoSuave)
            HStack(spacing: 10) {
                Image(systemName: icono)
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(activo ? NoktaTheme.marca : NoktaTheme.textoTenue)
                    .frame(width: 18)
                field()
                    .textFieldStyle(.plain)
                    .font(NoktaFont.poppins(14))
                    .foregroundStyle(NoktaTheme.texto)
                accesorio()
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(NoktaTheme.superficie2.opacity(0.6), in: forma)
            .overlay(forma.strokeBorder(activo ? NoktaTheme.marca.opacity(0.7) : NoktaTheme.borde, lineWidth: 1))
            .animation(.easeOut(duration: 0.15), value: activo)
        }
    }

    private func submit() async {
        foco = nil
        if await vm.login() {
            onSuccess()
        } else {
            withAnimation(.default) { intentosFallidos += 1 }
            foco = .password
        }
    }
}

/// Horizontal shake for the error message (like a rejected macOS password).
private struct Temblor: GeometryEffect {
    var intentos: Int
    var animatableData: CGFloat
    init(intentos: Int) { self.intentos = intentos; animatableData = CGFloat(intentos) }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(animatableData * .pi * 4), y: 0))
    }
}

/// Hairline frame with a light (ember → cream) that keeps travelling round
/// it — the "borde de luz", one lap every 7 s.
private struct BordeDeLuz: View {
    var radio: CGFloat
    var anima: Bool

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: radio, style: .continuous)
        ZStack {
            forma.strokeBorder(NoktaTheme.borde, lineWidth: 1)
            TimelineView(.animation(paused: !anima)) { ctx in
                let vuelta = anima ? ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 7) / 7 : 0.15
                forma.strokeBorder(
                    AngularGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: 0.70),
                            .init(color: NoktaTheme.marca, location: 0.82),
                            .init(color: NoktaTheme.texto.opacity(0.6), location: 0.88),
                            .init(color: .clear, location: 0.96),
                            .init(color: .clear, location: 1),
                        ],
                        center: .center,
                        angle: .degrees(vuelta * 360)
                    ),
                    lineWidth: 1.2
                )
            }
        }
        .allowsHitTesting(false)
    }
}

/// The website's ribbon, drawn live: 14 fine strands that twist as they
/// follow the ember dot across the screen. Vector, so it's sharp at any size.
private struct TrazoVivo: View {
    var anima: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.animation(paused: !anima)) { ctx in
            let t = anima ? ctx.date.timeIntervalSinceReferenceDate * 1000 : 20_000
            Canvas { g, size in
                dibujar(g, size: size, t: t)
            }
        }
    }

    private func punto(_ u: Double, _ t: Double, _ w: Double, _ h: Double) -> CGPoint {
        CGPoint(
            x: w * (0.5 + 0.47 * sin(u + t * 0.00011) * cos(u * 0.37)),
            y: h * (0.5 + 0.36 * sin(u * 1.9 + t * 0.00017))
        )
    }

    private func dibujar(_ g: GraphicsContext, size: CGSize, t: Double) {
        let w = size.width, h = size.height
        let tinta: Color = scheme == .dark ? Color(hex: 0xF4F1EA) : Color(hex: 0x191816)
        let hilos = 14, pasos = 220, largo = 5.2
        let cabeza = (t * 0.00035).truncatingRemainder(dividingBy: .pi * 6)
        for k in 0..<hilos {
            let off = Double(k - hilos / 2) * 2.2
            var path = Path()
            for i in 0...pasos {
                let u = cabeza - largo + largo * Double(i) / Double(pasos)
                let p = punto(u, t, w, h), q = punto(u + 0.01, t, w, h)
                var nx = -(q.y - p.y), ny = q.x - p.x
                let nl = max(hypot(nx, ny), 0.0001)
                nx /= nl; ny /= nl
                let giro = sin(u * 1.3 + t * 0.0004)
                let pt = CGPoint(x: p.x + nx * off * giro, y: p.y + ny * off * giro)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            let centro = 1 - abs(Double(k - hilos / 2)) / Double(hilos / 2)
            let alfa = scheme == .dark ? 0.10 + 0.22 * centro : 0.07 + 0.16 * centro
            g.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [tinta.opacity(0), tinta.opacity(alfa)]),
                    startPoint: punto(cabeza - largo, t, w, h), endPoint: punto(cabeza, t, w, h)
                ),
                lineWidth: 1
            )
        }
        let c = punto(cabeza, t, w, h)
        let marca = NoktaTheme.marca
        g.fill(
            Path(ellipseIn: CGRect(x: c.x - 26, y: c.y - 26, width: 52, height: 52)),
            with: .radialGradient(Gradient(colors: [marca.opacity(0.55), marca.opacity(0)]), center: c, startRadius: 0, endRadius: 26)
        )
        g.fill(Path(ellipseIn: CGRect(x: c.x - 4.5, y: c.y - 4.5, width: 9, height: 9)), with: .color(marca))
    }
}

/// Very faint film grain so large flat backgrounds don't read as "flat".
/// Drawn once (fixed seed), rasterized.
private struct Grano: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { g, size in
            var rng = SeededRandom(seed: 7)
            let puntos = Int(size.width * size.height / 90)
            let color: Color = scheme == .dark ? .white : .black
            for _ in 0..<puntos {
                let x = Double(rng.next() % UInt64(max(1, Int(size.width))))
                let y = Double(rng.next() % UInt64(max(1, Int(size.height))))
                let a = Double(rng.next() % 100) / 100
                g.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)),
                       with: .color(color.opacity(scheme == .dark ? 0.035 * a : 0.03 * a)))
            }
        }
        .drawingGroup()
    }
}

private struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 33
    }
}
