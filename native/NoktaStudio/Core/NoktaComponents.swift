import SwiftUI

// Shared building blocks for the premium redesign (2026-09). Every section
// uses these so the whole app reads as one family with the Dashboard.

// MARK: - Formatting

enum NoktaFormato {
    /// "$4,850" for whole amounts, "$4,850.50" when there are cents.
    static func dinero(_ v: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.minimumFractionDigits = v.rounded() == v ? 0 : 2
        f.maximumFractionDigits = 2
        return "$" + (f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v))
    }

    static func iniciales(_ nombre: String) -> String {
        let i = nombre.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        return i.isEmpty ? "·" : i
    }
}

// MARK: - Motion

extension View {
    /// Staggered rise-and-fade entrance. `orden` sets the delay step (capped so
    /// long lists don't take forever to settle).
    func noktaEntrada(_ visible: Bool, _ orden: Int) -> some View {
        modifier(NoktaEntrada(visible: visible, orden: orden))
    }

    /// Subtle highlight under the pointer (Mac) — rows feel alive.
    func noktaHover(radio: CGFloat = 10) -> some View { modifier(NoktaHover(radio: radio)) }
}

private struct NoktaEntrada: ViewModifier {
    var visible: Bool
    var orden: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 14)
            .animation(
                reduceMotion ? nil : .spring(duration: 0.55, bounce: 0.12).delay(Double(min(orden, 12)) * 0.045),
                value: visible
            )
    }
}

private struct NoktaHover: ViewModifier {
    var radio: CGFloat
    @State private var encima = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radio, style: .continuous)
                    .fill(NoktaTheme.superficie2.opacity(encima ? 1 : 0))
                    .padding(.horizontal, -10)
            )
            .onHover { h in withAnimation(.easeOut(duration: 0.15)) { encima = h } }
    }
}

/// Soft moving sheen for loading placeholders (instead of "Cargando…").
struct NoktaBrillo: ViewModifier {
    @State private var fase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, NoktaTheme.texto.opacity(0.07), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: fase * geo.size.width * 1.4)
                }
                .clipped()
                .allowsHitTesting(false)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { fase = 1 }
            }
    }
}

// MARK: - Header

struct NoktaEncabezado<Acciones: View>: View {
    var titulo: String
    var subtitulo: String?
    @ViewBuilder var acciones: () -> Acciones
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var compacto: Bool { sizeClass == .compact }
    #else
    private let compacto = false
    #endif

    var body: some View {
        let texto = VStack(alignment: .leading, spacing: 4) {
            Text(titulo)
                .font(NoktaFont.poppins(compacto ? 28 : 34, .light))
                .tracking(compacto ? -0.7 : -1)
                .foregroundStyle(NoktaTheme.texto)
            if let subtitulo {
                Text(subtitulo)
                    .font(NoktaFont.poppins(compacto ? 13 : 14))
                    .foregroundStyle(NoktaTheme.textoSuave)
                    .contentTransition(.numericText())
            }
        }
        if compacto {
            VStack(alignment: .leading, spacing: 14) { texto; HStack(spacing: 10) { acciones() } }
        } else {
            HStack(alignment: .bottom, spacing: 12) { texto; Spacer(minLength: 16); acciones() }
        }
    }
}

extension NoktaEncabezado where Acciones == EmptyView {
    init(titulo: String, subtitulo: String? = nil) {
        self.init(titulo: titulo, subtitulo: subtitulo, acciones: { EmptyView() })
    }
}

// MARK: - Buttons

struct NoktaBotonPrimario: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NoktaFont.poppins(12, .medium))
            .foregroundStyle(NoktaTheme.fondo)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(NoktaTheme.texto, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

struct NoktaBotonSecundario: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let forma = RoundedRectangle(cornerRadius: 10, style: .continuous)
        configuration.label
            .font(NoktaFont.poppins(12, .medium))
            .foregroundStyle(NoktaTheme.texto)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(NoktaTheme.superficie, in: forma)
            .overlay(forma.strokeBorder(NoktaTheme.borde, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

// MARK: - Search

struct NoktaBuscador: View {
    @Binding var texto: String
    var placeholder = "Buscar…"
    @FocusState private var foco: Bool

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: 10, style: .continuous)
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .light))
                .foregroundStyle(NoktaTheme.textoTenue)
            TextField("", text: $texto, prompt: Text(placeholder).foregroundStyle(NoktaTheme.textoTenue))
                .textFieldStyle(.plain)
                .font(NoktaFont.poppins(12))
                .foregroundStyle(NoktaTheme.texto)
                .focused($foco)
                .autocorrectionDisabled()
            if !texto.isEmpty {
                Button { texto = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                        .foregroundStyle(NoktaTheme.textoTenue)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(NoktaTheme.superficie, in: forma)
        .overlay(forma.strokeBorder(foco ? NoktaTheme.marca.opacity(0.6) : NoktaTheme.borde, lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: foco)
        .animation(.easeOut(duration: 0.15), value: texto.isEmpty)
    }
}

// MARK: - Filter chips

/// Segmented chips with a highlight that glides to the selected option.
struct NoktaChips<Valor: Hashable>: View {
    var opciones: [(valor: Valor, texto: String)]
    @Binding var seleccion: Valor
    @Namespace private var ns

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(opciones, id: \.valor) { op in
                    let activo = op.valor == seleccion
                    Button {
                        withAnimation(.snappy(duration: 0.3)) { seleccion = op.valor }
                    } label: {
                        Text(op.texto)
                            .font(NoktaFont.poppins(12, activo ? .medium : .regular))
                            .foregroundStyle(activo ? NoktaTheme.texto : NoktaTheme.textoSuave)
                            .padding(.horizontal, 13).padding(.vertical, 6)
                            .background {
                                if activo {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(NoktaTheme.superficie2)
                                        .matchedGeometryEffect(id: "chip", in: ns)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(NoktaTheme.superficie, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(NoktaTheme.borde, lineWidth: 1))
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Small pieces

/// Colored dot + label, e.g. Pagado / Pendiente / Activo / Pausado.
struct NoktaEstado: View {
    var texto: String
    var color: Color
    var tamano: CGFloat = 12

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(texto).font(NoktaFont.poppins(tamano))
        }
        .foregroundStyle(color)
        .fixedSize()
    }
}

struct NoktaAvatar: View {
    var nombre: String
    var tamano: CGFloat = 34

    var body: some View {
        Text(NoktaFormato.iniciales(nombre))
            .font(NoktaFont.poppins(tamano * 0.32, .medium))
            .foregroundStyle(NoktaTheme.textoSuave)
            .frame(width: tamano, height: tamano)
            .background(NoktaTheme.superficie2, in: Circle())
    }
}

/// Icon + value tile used for the little summary rows at the top of sections.
struct NoktaIndicador: View {
    var icono: String
    var titulo: String
    var valor: Double
    var detalle: String?
    var acento: Color?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icono)
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(acento ?? NoktaTheme.textoSuave)
                .frame(width: 40, height: 40)
                .background(acento?.opacity(0.12) ?? NoktaTheme.superficie2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(titulo).font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoSuave)
                Text(NoktaFormato.dinero(valor))
                    .font(NoktaFont.poppins(22))
                    .tracking(-0.6)
                    .foregroundStyle(acento ?? NoktaTheme.texto)
                    .contentTransition(.numericText(value: valor))
                    .animation(.snappy, value: valor)
                if let detalle {
                    Text(detalle).font(NoktaFont.poppins(11))
                        .foregroundStyle(acento?.opacity(0.85) ?? NoktaTheme.textoTenue)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .noktaCard(padding: 18)
    }
}

struct NoktaVacio: View {
    var icono: String
    var titulo: String
    var detalle: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icono)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(NoktaTheme.textoTenue)
                .frame(width: 56, height: 56)
                .background(NoktaTheme.superficie2, in: Circle())
            Text(titulo).font(NoktaFont.poppins(14, .medium)).foregroundStyle(NoktaTheme.texto)
            if let detalle {
                Text(detalle).font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoSuave)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

/// Placeholder row with a moving sheen, shown while a list first loads.
struct NoktaFilaCargando: View {
    var body: some View {
        HStack(spacing: 14) {
            Circle().fill(NoktaTheme.superficie2).frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(NoktaTheme.superficie2).frame(width: 150, height: 11)
                RoundedRectangle(cornerRadius: 4).fill(NoktaTheme.superficie2).frame(width: 100, height: 9)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 4).fill(NoktaTheme.superficie2).frame(width: 60, height: 11)
        }
        .padding(.vertical, 10)
        .modifier(NoktaBrillo())
    }
}

/// Stable, readable text for NoktaEstado from a trabajo — same rule as the
/// Trabajos list / Dashboard: monthly contracts (grupo B) and "Clases" show
/// the client relationship; one-off jobs show Pagado / Pendiente.
enum NoktaEstadoTrabajo {
    static func de(_ t: NoktaTrabajo, estados: [NoktaClienteEstado]) -> (texto: String, color: Color) {
        if t.grupoResuelto == "B" || t.servicio == "Clases" {
            let er = estados.first { $0.nombre == t.cliente }?.estado ?? "activo"
            let color = er == "activo" ? NoktaTheme.exito : er == "pausado" ? NoktaTheme.aviso : NoktaTheme.error
            return (ESTADO_CLIENTE_LABEL[er] ?? er.capitalized, color)
        }
        return t.estado == "pagado" ? ("Pagado", NoktaTheme.exito) : ("Pendiente", NoktaTheme.aviso)
    }
}
